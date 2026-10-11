ENTRY(_start)
MEMORY { rom (rx) : ORIGIN = 0x08000000, LENGTH = 8M }
SECTIONS {
  .text : { KEEP(*(.init)) *(.text*) *(.rodata*) } > rom
  /DISCARD/ : { *(.ARM.exidx*) *(.ARM.extab*) *(.comment*) }
}
