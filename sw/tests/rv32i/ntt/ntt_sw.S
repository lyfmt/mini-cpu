// NTT 评估程序，软件模乘版（设计文档第七节"怎么证明它有用"）。
//
// NTT 主体在 sw/ntt/ntt_body.S，两个版本共用；这里只定义 MODMUL：
// 调用软件模乘子程序 modmul_sw（jal 调用，jalr 返回）。
// 只用 rv32i 指令。另一个版本见 sw/tests/rv32i_qmul/ntt/ntt_qmul.S。
//
// 失败码：k + 1（1..256），第一处与期望输出不等的是第 k 个系数。
#include "test.h"

// 主体固定写 MODMUL a2, s5, a1；子程序的参数就放在这几个寄存器里，
// 只需把 ζ 复制进 a0（子程序会移位改写它，而 ζ 在整组蝴蝶里都要用）。
.macro MODMUL rd, rs1, rs2
    .ifnc \rd, a2
        .error "MODMUL: modmul_sw returns its result in a2"
    .endif
    .ifnc \rs2, a1
        .error "MODMUL: modmul_sw takes its second operand in a1"
    .endif
    addi    a0, \rs1, 0
    jal     ra, modmul_sw
    PAD_JUMP
.endm

#include "../../../ntt/ntt_body.S"

// ------------------------------------------------------------------
// modmul_sw：a2 <- a0 · a1 mod q
//   要求 a0、a1 在 [0, q)，s8 = q。改写 a0、a1、a3。
//
// 1. 移位加法求乘积：每轮取 a1 的最低位，为 1 时把 a0 加进乘积；
//    a0 左移、a1 右移，a1 变成 0 就停。用掩码代替分支，循环里只有一个回跳。
// 2. 移位减法取模：d 从 q·2^11 开始，每轮"乘积 ≥ d 就减去 d"，d 右移，
//    直到 d < q，共 12 轮。乘积 ≤ (q−1)² < q·2^12，所以从 q·2^11 开始足够。
//    同样用掩码代替分支。
// ------------------------------------------------------------------
modmul_sw:
    addi    a2, x0, 0
.Lmul:
    andi    a3, a1, 1
    PAD_DATA
    sub     a3, x0, a3              // 这一位为 1 时全 1
    PAD_DATA
    and     a3, a3, a0
    PAD_DATA
    add     a2, a2, a3
    slli    a0, a0, 1
    srli    a1, a1, 1
    PAD_DATA
    bne     a1, x0, .Lmul
    PAD_JUMP

    slli    a0, s8, 11              // d = q·2^11
    PAD_DATA
.Lmod:
    sltu    a3, a2, a0
    PAD_DATA
    addi    a3, a3, -1              // 乘积 ≥ d 时全 1
    PAD_DATA
    and     a3, a3, a0
    PAD_DATA
    sub     a2, a2, a3
    srli    a0, a0, 1
    PAD_DATA
    bgeu    a0, s8, .Lmod
    PAD_JUMP

    jalr    x0, 0(ra)
    PAD_JUMP
