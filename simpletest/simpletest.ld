OUTPUT_ARCH( "riscv" )
ENTRY(_start)

MEMORY
{
    xip_memory  (rx)  : ORIGIN = 0x58000000, LENGTH = 1M
    psram_memory(rx)  : ORIGIN = 0x54000000, LENGTH = 64M
    itcm_memory (rx)  : ORIGIN = 0x3effc800, LENGTH = 14K  /* not in the manual but some memory is here */
    dtcm_memory (rx)  : ORIGIN = 0x3f000000, LENGTH = 32K
    ram_memory  (!rx) : ORIGIN = 0x3ef80000, LENGTH = 512K
    /*xram_memory (!rx) : ORIGIN = 0x40004000, LENGTH = 16K*/
    xram_memory (!rx) : ORIGIN = 0x40000000, LENGTH = 16K
}

SECTIONS
{
    .text :
    {
        . = ALIGN(4);
        __text_code_start__ = .;

        KEEP (*(SORT_NONE(_start)))
        *(.text)
        *(.rodata)
        *(.rodata.*)

        *(.srodata)
        *(.srodata.*)

        . = ALIGN(4);
        __text_code_end__ = .;
    } > itcm_memory

    .dtcm_region :
    {
        . = ALIGN(4);
        __tcm_data_start__ = .;

        *(.data)
        *(.data.*)

        . = ALIGN(4);
        __tcm_data_end__ = .;
    } > dtcm_memory

    .dtcm_noload (NOLOAD) :
    {
        . = ALIGN(0x4);
        *(.bss)
        __stack_bottom = .;
        . = ALIGN(0x4);
        . = . + 4096;
        . = ALIGN(0x4);
        __stack_top = .;
    } > dtcm_memory
}

