set base gits/bl_mcu_sdk
#set CC result-toolchain-linux/bin/riscv64-unknown-linux-gnu-gcc
set CC riscv64-unknown-linux-gnu-gcc
set CFLAGS "-DBL808=1"

if {[llength $argv] > 0} {
  set base [lindex $argv 0]
}
if {![file isdirectory $base]} {
  puts "Error: Base directory [list $base] doesn't exist."
  puts "Usage: tclsh $argv0 ?basedir?"
  exit 1
}

set include_dirs {
  drivers/lhal/include/arch/risc-v/t-head/Core/Include
  drivers/soc/bl808/std/include/hardware
  drivers/soc/bl808/std/include
  drivers/lhal/include
  drivers/lhal/include/arch
}

set src {
++SECTION:std
#include <stdint.h>
++SECTION:arch
#include <csi_core.h>
++SECTION:bl808
#include <bl808.h>
// some bugfixes
#define IPC_CPU0_IPC_IUSR_LEN      (16U)
}
foreach x [glob -dir $base/drivers/soc/bl808/std/include -tails *.h] {
  append src "#include <$x>\n"
}

set f [open "parse_regs_tmp.c" w]
puts $f $src
close $f

#set f [open "|$CC [join [lmap x $include_dirs {lindex "-I$base/$x"}] " "] $CFLAGS -E -dD parse_regs_tmp.c" "r"]
exec $CC {*}[lmap x $include_dirs {lindex "-I$base/$x"}] {*}$CFLAGS -E -dD parse_regs_tmp.c >parse_regs_tmp.c.out1
set f [open "parse_regs_tmp.c.out1" r]
set text [read $f]
close $f

set section_texts {}
set i 0
set prev_section {begin}
while {$i < [string length $text] && [regexp -start $i -indices -line {^[+][+]SECTION:(.*)$} $text all name]} {
  dict set section_texts $prev_section [string range $text $i [lindex $all 0]-1]
  set i [lindex $all 1]
  incr i
  set prev_section [string range $text {*}$name]
}
dict set section_texts $prev_section [string range $text $i end]

#puts [dict keys $section_texts]
#puts [dict get $section_texts bl808]

set text2 [dict get $section_texts bl808]
regsub -all {[\\]\r?\n} $text2 { } text2

proc process_define_value {name value accept_words} {
  regsub -all {\(\(uint\d+\w*\)([^()]+)\)} $value {(\1)} value
  regsub -all {\(\(uint\d+\w*\)\(([^()]+)\)\)} $value {(\1)} value
  regsub -all {\(\(void ?[*]\)([^()]+)\)} $value {(\1)} value
  regsub -all -nocase {\y(\d+|0x[0-9a-f]+)[lu]+\y} $value {\1} value

  set error {}
  if {$accept_words && [regexp {\A\(?(\w+)\)?\Z} $value -> value2]} {
    set type word
    set value $value2
  } elseif {$name eq $value || "($name)" eq $value || $name eq "IPC_CPU1_IPC_IUSR" && $value eq "IPC_AP_IPC_IUSR"} {
    set type identity
    set value $name
  } elseif {$value eq ""} {
    set type empty
  } elseif {[catch {expr $value} value2] || ![string is wideinteger $value2]} {
    set type failed
    set error $value2
  } else {
    set value [format "0x%08x" $value2]
    set type number
  }

  list $type $value $error
}

regsub -all {[\t]+} $text2 { } text2

set enums {}
set i 0
while {$i < [string length $text2] && [regexp -start $i -indices -lineanchor {^\s*typedef enum \{([^{}]+)\} *(\S+);} $text2 all body name]} {
  set i [lindex $all 1]; incr i
  set enum_name [string range $text2 {*}$name]
  set body [string range $text2 {*}$body]
  #puts "Found enum [list $enum_name]"
  regsub -all -line {^# \d+ ".*"$} $body {} body

  set prev_value -1
  foreach x [split $body ,] {
    if {[string trim $x] eq ""} {continue}
    if {![regexp -nocase {\A\s*(\S+)\s*(?:=\s*([0-9a-fx]+|[!]\S+)\s*)?\Z} $x -> name value]} {
      puts "WARN: Couldn't parse value in enum [list $name]: [list $x]"
      break
    } else {
      if {$value eq ""} {
        set value [expr {$prev_value+1}]
      } elseif {[string index $value 0] eq "!" && [dict exists $enums $enum_name [set other [string range $value 1 end]]]} {
        set value [expr {! [dict get $enums $enum_name $other]}]
      }
      dict set enums $enum_name $name [format "0x%x" $value]
      set prev_value $value
    }
  }
}

set defines {}
set failed 0
set i 0
while {$i < [string length $text2] && [regexp -start $i -indices -line {^#define ([^() ]+) (.*)$} $text2 all name value]} {
  set i [lindex $all 1]; incr i
  set name [string range $text2 {*}$name]
  set value [string range $text2 {*}$value]

  if {[string first __attribute__ $value] >= 0} {continue}
  if {[string first __attribute( $value] >= 0} {continue}
  if {$name in {P_tmpdir errno ATTR_UNI_SYMBOL BL_DRV_DUMMY}} {continue}

  lassign [process_define_value $name $value 0] type value error

  if {$type eq "failed" && (![dict exists $defines $name] || [lindex [dict get $defines $name] 0] ne "failed")} {
    incr failed
    if {$failed < 10} {
      #puts "WARN: Value of #define [list $name] is not a number: [list $value] -> $error"
    }
  }

  set new [list $type $value]
  if {[dict exists $defines $name] && [set old [dict get $defines $name]] ne $new} {
    puts "WARN: Replacing value of [list $name] by $new, was $old"
  }
  dict set defines $name $new
}
puts "Collected [dict size $defines] #defines, $failed couldn't be parsed but we will send them through gcc again"

# Let's call gcc again with all the values that we couldn't parse.
# We make all the enum values available as #defines so gcc will replace them for us.
dict for {_ x} $enums {
  dict for {name value} $x {
    append src "#define $name $value\n"
  }
}
dict for {name x} $defines {
  lassign $x type value
  if {$type ne "failed"} {continue}
  append src "++VALUE_OF__$name\n$value\n"
}
append src "++END\n"

set f [open "parse_regs_tmp.c" w]
puts $f $src
close $f

exec $CC {*}[lmap x $include_dirs {lindex "-I$base/$x"}] {*}$CFLAGS -E -dD parse_regs_tmp.c >parse_regs_tmp.c.out2
set f [open "parse_regs_tmp.c.out2" r]
set text3 [read $f]
close $f

set i 0
while {$i < [string length $text3] && [regexp -start $i -indices -line {^[+][+]VALUE_OF__(.*)$} $text3 all name]} {
  set name [string range $text3 {*}$name]
  set i [lindex $all 1]; incr i
  if {[regexp -start $i -indices -line {^[+][+]} $text3 end]} {
    set i [lindex $end 0]
  } else {
    set i [string length $text3]
  }
  set value [string range $text3 [lindex $all 1]+1 $i-1]
  regsub -all -line {^# \d+ ".*"( \d+)*$} $value {} value
  set value [string trim $value]

  lassign [process_define_value $name $value 1] type value error

  if {$type ne "failed"} {
    incr failed -1
    dict set defines $name [list $type $value]
  } else {
    puts [list DEBUG $name $type $value $error $x]
  }
} 
puts "Collected [dict size $defines] #defines, $failed couldn't be parsed after re-evaluating with GCC"

dict for {name x} $defines {
  lassign $x type value
  if {$type ne "failed"} {continue}
  puts [list DEBUG $name $type $value]
}

set defines_no_fields {}
set regs {}
set state 0
set reg {}
set field {}
dict for {name x} $defines {
  lassign $x type value
  if {$type eq "number" && [string match {*_OFFSET} $name]} {
    set state 1
    set reg [regsub {_OFFSET$} $name {}]
    dict set defines_no_fields $name $x
    dict set regs $reg offset $value
  } elseif {($state == 1 || $state == 2) && $type eq "identity"} {
    dict unset defines_no_fields ${reg}_OFFSET
    set state 2
    set field $name
    foreach x {pos len msk umsk} {
      lassign [dict get $defines ${name}_[string toupper $x]] _ $x
    }
    dict set regs $reg fields $name [dict create pos $pos len $len]
    if {$msk != (((1<<$len)-1)<<$pos) || $umsk != (((1<<64)-1) & ~$msk)} {
      puts "WARN: Mask for field [list $name] in [list $reg] is not as expected! ($msk != (((1<<$len)-1)<<$pos) || $umsk != (((1<<64)-1) & ~$msk))"
    }
  } elseif {$state == 2 && [string match ${field}_* $name]} {
    set suffix [string range $name [string length $field]+1 end]
    switch -- $suffix {
      POS - LEN - MSK - UMSK {}
      default {
        dict set defines_no_fields $name $x
      }
    }
  } else {
    if {$state == 1 && ![dict exists $regs $reg fields]} {
      #dict unset regs $reg
    }
    set state 0
    dict set defines_no_fields $name $x
  }
}

set py {}
dict for {name x} $defines_no_fields {
  lassign $x type value
  if {$type eq "number"} {
    append py "$name = $value\n"
  }
}
dict for {_ x} $enums {
  dict for {name value} $x {
    append py "$name = $value\n"
  }
}
set f [open bl808_consts.py w]
puts $f $py
close $f

set py {
from reg_lib import *

def consts():
  import bl808_consts
  return bl808_consts
}

# find *_BASE and *_END values and collect them in MemoryMap
set bases {}
append py "class MemoryMap(object):\n"
dict for {name x} $defines_no_fields {
  lassign $x type value
  if {$type ne "number"} {continue}

  if {[regexp {\A(.*)_BASE$\Z} $name -> name2]} {
    dict set bases $name2 $value

    if {[dict exists $defines_no_fields ${name2}_END]} {
      lassign [dict get $defines_no_fields ${name2}_END] _ value2
      append py "  $name2 = MemoryRegion(start=$value, end=$value2)\n"
    } else {
      append py "  $name = $value\n"
    }
  }
}

# generate classes for enums that have a common prefix in their value names
set enum_prefix_used {}
dict for {enum_name x} $enums {
  dict for {name value} $x {break}
  set parts [split $name _]
  set match 0
  for {set i [expr {[llength $parts]-1}]} {$i > 0} {incr i -1} {
    set prefix [join [lrange $parts 0 $i-1] _]_
    set match 1
    dict for {name value} $x {
      if {![string equal -length [string length $prefix] $prefix $name]} {
        set match 0
        break
      }
    }
    if {$match} {break}
  }

  # use a different name for some 
  dict for {name value} $x {break}
  set changed_names {
    SF_Ctrl_Pad_Type SF_CTRL_PAD
    SF_Ctrl_Remap_Type SF_CTRL_REMAP
    SF_Ctrl_RW_Type    SF_CTRL_RW
    SF_Ctrl_IO_Type    SF_CTRL_IO
    SF_Ctrl_Pad_Type   SF_CTRL_PAD
    SF_Ctrl_Mode_Type  SF_CTRL_MODE
    SF_Ctrl_AES_Key_Type  SF_CTRL_AES_BITS
    SF_Ctrl_AES_Mode_Type SF_CTRL_AES_MODE
    GLB_DSP_MUXPLL_320M_CLK_SEL_Type GLB_DSP_MUXPLL_SEL_320M
    GLB_DSP_MUXPLL_240M_CLK_SEL_Type GLB_DSP_MUXPLL_SEL_240M
    GLB_DSP_MUXPLL_160M_CLK_SEL_Type GLB_DSP_MUXPLL_SEL_160M
    GLB_MCU_MUXPLL_80M_CLK_SEL_Type  GLB_DSP_MUXPLL_SEL_80M
    GLB_EM_Type         GLB_EM
    GLB_DMA_CLK_ID_Type GLB_DMA_CLK
    PSRAM_Winbond_Drive_Strength PSRAM_DS
    PSRAM_Burst_Type             PSRAM_BURST
    PSRAM_ApMem_Refresh_Speed    PSRAM_REFRESH
    PSRAM_Latency_ApMem_Type     PSRAM_LATENCY
    PSRAM_Fixed_Latency_Enable   PSRAM_FIXED_LATENCY

    BL_Err_Type  BL_RESULT
    BL_Fun_Type  BL_FUN
    BL_Sts_Type  BL_STS
    BL_Mask_Type BL_MASK
    ActiveStatus ACTIVE_STATUS
    CCI_ID_Type  CCI_ID
  }
  if {[dict exists $changed_names $enum_name]} {
    set clsname [dict get $changed_names $enum_name]
  } else {
    set clsname [string range $prefix 0 end-1]
  }

  if {!$match} {
    if {![dict exists $changed_names $enum_name]} {
      puts "INFO: No common prefix for $enum_name ($name)"
      continue
    } else {
      set prefix ""
    }
  }

  if {[dict exists $enum_prefix_used $clsname]} {
    puts "WARN: Enum name [list $clsname] would be used by two enums! ([list $name / $enum_name and [dict get $enum_prefix_used $clsname]])"
    continue
  }
  dict set enum_prefix_used $clsname [list $name / $enum_name]

  append py "\nclass $clsname:\n"
  dict for {name value} $x {
    set name [string range $name [string length $prefix] end]
    if {[string match {[0-9]*} $name]} {
      set name [regsub {\A([^_]*_)*(?=[a-zA-Z])} $prefix {}]$name
    }
    append py "  $name = $value\n"
  }
}

# generate register instances
set regs2 $regs
dict for {reg _} $regs2 {
  dict set regs2 $reg peripheral {}
}
set base_name_mapping {
  IPC0 IPC
  IPC1 IPC
  IPC2 IPC
}
set base_names [dict keys $bases]
lappend base_names {*}[dict values $base_name_mapping]
foreach base [lsort -unique $base_names] {
  set prefix ${base}_
  dict for {reg _} $regs2 {
    if {[string equal -length [string length $prefix] $prefix $reg]} {
      dict set regs2 $reg peripheral $base
    }
  }
}
dict set bases {} 0
dict for {base address} $bases {
  set base2 $base
  set base [regsub {\A\Z} $base UNKNOWN]
  if {[dict exists $base_name_mapping $base2]} {
    set base2 [dict get $base_name_mapping $base2]
  }
  set prefix1 ${base}_
  append py "\ndef _${base}_regs():\n  return \[\n"
  set empty 1
  dict for {reg x} $regs2 {
    set fields {}
    dict with x {}
    if {$peripheral ne $base2} {continue}
    set prefix2 ${reg}_
    if {[string equal -length [string length $prefix1] $prefix1 $reg]} {
      set reg2 [string range $reg [string length $prefix1] end]
    } else {
      set reg2 $reg
    }
    set empty 0
    if {$reg ne $reg2} {
      append py [format "    # %s\n" $reg]
    }
    append py [format "    Register(\"%s\", 0x%04x" $reg2 $offset]
    dict for {name x} $fields {
      dict with x {}
      if {[string equal -length [string length $prefix2] $prefix2 $name]} {
        set name [string range $name [string length $prefix2] end]
      } elseif {[string equal -length [string length $prefix1] $prefix1 $name]} {
        set name [string range $name [string length $prefix1] end]
      }
      regsub {\AREG_GPIO_\d+_|\AGPIO_\d+_|\AREG2_} $name {} name
      append py [format ",\n      (\"%s\", %d, %d)" $name $pos $len]
    }
    append py "),\n"
  }
  append py "  \]\n"
  append py "$base = Peripheral(\"$base\", $address, _${base}_regs)\n"
}

append py "\n"
foreach name {CORE_ID_ADDRESS CORE_ID_M0 CORE_ID_D0 CORE_ID_LP IPC_SYNC_ADDR1 IPC_SYNC_ADDR2 IPC_SYNC_FLAG} {
  lassign [dict get $defines_no_fields $name] type value
  if {$type eq "number"} {
    append py "$name = $value\n"
  }
}

set f [open bl808_regs.py w]
puts $f $py
close $f

