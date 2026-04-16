// Minimal reset handler for the custom_fpga firmware image.

	.section .text.start
	.global reset_vec
	.global start

reset_vec:
start:
	la sp, _stack_top

	// Copy the optional .data section from firmware ROM to SRAM.
	la a0, _sidata
	la a1, _sdata
	la a2, _edata
1:
	beq a1, a2, 2f
	lw a3, 0(a0)
	sw a3, 0(a1)
	addi a0, a0, 4
	addi a1, a1, 4
	j 1b

	// Zero the .bss section in SRAM.
2:
	la a0, _sbss
	la a1, _ebss
3:
	beq a0, a1, 4f
	sw zero, 0(a0)
	addi a0, a0, 4
	j 3b

4:
	call main
	beq a0, zero, custom_pass

custom_fail:
	li t0, 0x10000000
	li t1, 'F'
	sw t1, 0(t0)
	li t1, 'A'
	sw t1, 0(t0)
	li t1, 'I'
	sw t1, 0(t0)
	li t1, 'L'
	sw t1, 0(t0)
	li t1, '\n'
	sw t1, 0(t0)
	ebreak

custom_pass:
	li t0, 0x10000000
	li t1, 'O'
	sw t1, 0(t0)
	li t1, 'K'
	sw t1, 0(t0)
	li t1, '\n'
	sw t1, 0(t0)

	li t0, 0x20000000
	li t1, 123456789
	sw t1, 0(t0)
	ebreak
