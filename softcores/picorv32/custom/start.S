// Minimal reset handler for custom/main.c under the stock PicoRV32 testbench.

	.section .text
	.global reset_vec
	.global start

reset_vec:
start:
	lui sp, (128*1024)>>12
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
