.syntax unified
.cpu arm7tdmi
.arm
.text
.global banked_register_check
.type banked_register_check,%function

.macro check reg, value
    ldr r1, =\value
    cmp \reg, r1
    bne .Lbank_fail
.endm
.macro common
    check r8, 0x80
    check r9, 0x90
    check r10, 0xa0
    check r11, 0xb0
    check r12, 0xc0
.endm
.macro enter mode
    mov r3, #\mode
    msr cpsr_c, r3
.endm
.macro setup mode, spval, lrval, status
    enter \mode
    ldr sp, =\spval
    ldr lr, =\lrval
    ldr r3, =\status
    msr spsr_fsxc, r3
.endm
.macro bankcheck mode, spval, lrval, status
    enter \mode
    check sp, \spval
    check lr, \lrval
    mrs r7, spsr
    check r7, \status
.endm

banked_register_check:
    stmdb sp!, {r4-r11,lr}
    mov r4, sp                    @ Unbanked pointer to the caller's stack.
    mov r8, #0x80
    mov r9, #0x90
    mov r10, #0xa0
    mov r11, #0xb0
    mov r12, #0xc0
    mov sp, #0x13
    mov lr, #0x14
    setup 0xd1, 0x113, 0x114, 0xa000001f
    mov r8, #0x81
    mov r9, #0x91
    mov r10, #0xa1
    mov r11, #0xb1
    mov r12, #0xc1
    setup 0xd2, 0x213, 0x214, 0x6000001f
    setup 0xd3, 0x313, 0x314, 0x9000001f
    setup 0xd7, 0x413, 0x414, 0x5000001f
    setup 0xdb, 0x513, 0x514, 0x7000001f

    mov r2, #1
    enter 0xdf
    check sp, 0x13
    check lr, 0x14
    common
    mov r2, #2
    bankcheck 0xd1, 0x113, 0x114, 0xa000001f
    check r8, 0x81
    check r9, 0x91
    check r10, 0xa1
    check r11, 0xb1
    check r12, 0xc1
    mov r2, #3
    bankcheck 0xd2, 0x213, 0x214, 0x6000001f
    common
    mov r2, #4
    bankcheck 0xd3, 0x313, 0x314, 0x9000001f
    common
    mov r2, #5
    bankcheck 0xd7, 0x413, 0x414, 0x5000001f
    common
    mov r2, #6
    bankcheck 0xdb, 0x513, 0x514, 0x7000001f
    common

    @ STM^ and LDM^ access user R8-R14 while FIQ remains active.
    mov r2, #7
    enter 0xd1
    ldr r3, =0x03002000
    stmia r3, {r8-r14}^
    ldr r7, [r3,#0]
    check r7, 0x80
    ldr r7, [r3,#4]
    check r7, 0x90
    ldr r7, [r3,#8]
    check r7, 0xa0
    ldr r7, [r3,#12]
    check r7, 0xb0
    ldr r7, [r3,#16]
    check r7, 0xc0
    ldr r7, [r3,#20]
    check r7, 0x13
    ldr r7, [r3,#24]
    check r7, 0x14
    mov r2, #8
    ldr r7, =0x133
    str r7, [r3,#20]
    ldr r7, =0x144
    str r7, [r3,#24]
    ldmia r3, {r8-r14}^
    check sp, 0x113
    check lr, 0x114
    check r8, 0x81
    check r9, 0x91
    check r10, 0xa1
    check r11, 0xb1
    check r12, 0xc1
    enter 0xdf
    check sp, 0x133
    check lr, 0x144
    common
    mov r0, #0
    b .Lbank_return
.Lbank_fail:
    mov r0, r2
.Lbank_return:
    enter 0xdf
    mov sp, r4
    ldmia sp!, {r4-r11,pc}
.size banked_register_check, .-banked_register_check
.ltorg
