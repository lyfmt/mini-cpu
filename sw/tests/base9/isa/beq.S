// beq rs1, rs2, offset：rs1 = rs2 时 PC <- PC + 符号扩展(offset)
//
// 应该跳却没跳，或不该跳却跳了，都会走到对应的 TEST_FAIL。
//
// 失败码：
//   1  5 = 5（不同寄存器）应向前跳
//   2  5 != 6 不应跳
//   3  0x00000001 与 0x80000001 只差最高位，不应跳
//   4  0x80000000 与 0x80000001 只差最低位，不应跳
//   5  -1 = 0xffffffff（两种方式构造）应跳
//   6  beq x0, x0 应跳
//   7  beq x7, x7（同一寄存器）应跳
//   8  向后跳的循环：执行 5 次后计数为 5
//   9  向后跳到前面的代码块（短距离）
//  10  向后跳的目标块里的标记
//  11  远距离向前跳（偏移 > 2 KB，用到 B 型立即数的第 11 位 inst[7]）
//  12  远距离向后跳（偏移 < -2 KB）
//  13  远距离向后跳的目标块里的标记
#include "test.h"

TEST_BEGIN
    LI      x1, 5
    LI      x2, 5
    LI      x3, 6
    LI      x4, 0x00000001
    LI      x5, 0x80000001
    LI      x6, 0x80000000
    LI      x7, -1
    LI      x8, 0xfffff000
    LI      x9, 0xfff, x20
    LI      x11, 1
    LI      x12, 5
    LI      x10, 0
    PAD_DATA
    add     x8, x8, x9          // 0xfffff000 + 0xfff = 0xffffffff
    PAD_DATA

    beq     x1, x2, 1f
    PAD_JUMP
    TEST_FAIL 1
1:
    beq     x1, x3, .Lfail2
    PAD_JUMP
    beq     x4, x5, .Lfail3
    PAD_JUMP
    beq     x6, x5, .Lfail4
    PAD_JUMP
    beq     x7, x8, 1f
    PAD_JUMP
    TEST_FAIL 5
1:
    beq     x0, x0, 1f
    PAD_JUMP
    TEST_FAIL 6
1:
    beq     x7, x7, 1f
    PAD_JUMP
    TEST_FAIL 7
1:

    // 向后跳的循环：x10 从 0 加到 5
.Lloop:
    add     x10, x10, x11
    PAD_DATA
    slt     x13, x10, x12       // x10 < 5 ?
    PAD_DATA
    beq     x13, x11, .Lloop    // 向后跳
    PAD_JUMP
    CHECK   x10, 5, 8

    // 短距离向后跳
    beq     x0, x0, .Lfwd9
    PAD_JUMP
    TEST_FAIL 9
.Lback9:
    ori     x14, x0, 0x99
    beq     x0, x0, .Ldone9
    PAD_JUMP
    TEST_FAIL 9
.Lfwd9:
    beq     x0, x0, .Lback9
    PAD_JUMP
    TEST_FAIL 9
.Ldone9:
    CHECK   x14, 0x99, 10

    // 远距离：中间隔着 520 条不会执行的空指令（2080 字节）
    beq     x0, x0, .Lfar_fwd
    PAD_JUMP
    TEST_FAIL 11
.Lfar_back:
    ori     x15, x0, 0x55
    beq     x0, x0, .Lfar_done
    PAD_JUMP
    TEST_FAIL 12
    .rept   520
    NOP0
    .endr
.Lfar_fwd:
    beq     x0, x0, .Lfar_back
    PAD_JUMP
    TEST_FAIL 12
.Lfar_done:
    CHECK   x15, 0x55, 13
TEST_END

.Lfail2:
    TEST_FAIL 2
.Lfail3:
    TEST_FAIL 3
.Lfail4:
    TEST_FAIL 4
