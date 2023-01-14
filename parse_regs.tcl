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
  } elseif {$name eq $value || "($name)" eq $value} {
    set type identity
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
set fields {}
set state 0
set reg {}
set field {}
dict for {name x} $defines {
  lassign $x type value
  if {$type eq "number" && [string match {*_OFFSET} $name]} {
    set state 1
    set reg $name
    dict set defines_no_fields $name $x
  } elseif {($state == 1 || $state == 2) && $type eq "identity"} {
    set state 2
    set field $name
    foreach x {pos len msk umsk} {
      lassign [dict get $defines ${name}_[string toupper $x]] _ $x
    }
    dict set fields $reg $name [dict create pos $pos len $len]
    if {$msk != (((1<<$len)-1)<<$pos) || $umsk != (((1<<64)-1) & ~$msk)} {
      puts "WARN: Mask for field [list $name] in [list $reg] is not as expected! ($msk != (((1<<$len)-1)<<$pos) || $umsk != (((1<<64)-1) & ~$msk))"
    }
  } elseif {$state == 2 && [string match ${field}_* $name]} {
    set suffix [string range $name [string length $field]+1 end]
    switch -- $suffix {
      POS - LEN - MSK - UMSK {}
      default {
        puts [list DEBUG $suffix]
        dict set defines_no_fields $name $x
      }
    }
  } else {
    set state 0
    dict set defines_no_fields $name $x
  }
}

set py {}
dict for {_ x} $enums {
  dict for {name value} $x {
    append py "$name = $value\n"
  }
}
dict for {name x} $defines_no_fields {
  lassign $x type value
  if {$type eq "number"} {
    append py "$name = $value\n"
  }
}
append py {
def deffield(reg, name, pos, len):
  globals()[name+"_POS"] = pos
  globals()[name+"_LEN"] = len
}
dict for {reg x} $fields {
  dict for {field x} $x {
    dict with x {}
    append py [format "deffield(%s, \"%s\", %d, %d)\n" $reg $field $pos $len]
  }
}
set f [open bl808_regs.py w]
puts $f $py
close $f
