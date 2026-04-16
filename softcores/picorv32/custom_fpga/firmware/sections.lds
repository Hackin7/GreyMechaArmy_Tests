ENTRY(reset_vec)

MEMORY {
	rom (rx)  : ORIGIN = 0x00000000, LENGTH = 0x00002000
	ram (rwx) : ORIGIN = 0x00002000, LENGTH = 0x00002000
}

SECTIONS {
	.text : {
		. = ALIGN(4);
		KEEP(*(.text.start))
		*(.text*)
		*(.rodata*)
		. = ALIGN(4);
		_etext = .;
	} > rom

	_sidata = LOADADDR(.data);
	.data : AT(_etext) {
		. = ALIGN(4);
		_sdata = .;
		*(.sdata*)
		*(.data*)
		. = ALIGN(4);
		_edata = .;
	} > ram

	.bss (NOLOAD) : {
		. = ALIGN(4);
		_sbss = .;
		*(.sbss*)
		*(.bss*)
		*(COMMON)
		. = ALIGN(4);
		_ebss = .;
	} > ram

	_stack_top = ORIGIN(ram) + LENGTH(ram);
}
