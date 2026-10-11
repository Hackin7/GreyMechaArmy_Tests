.syntax unified
.cpu arm7tdmi
.arm
.section .init,"ax"
.global _start
_start:
    b entry
    .space 0x9c
    .ascii "GREYGBA TEST"
    .ascii "GMAE"
    .ascii "00"
    .byte 0x96
    .space 13
entry:
    mov r0, #0xdf
    msr cpsr_c, r0
    ldr sp, =0x03007f00
    bl diagnostic
1:  b 1b
