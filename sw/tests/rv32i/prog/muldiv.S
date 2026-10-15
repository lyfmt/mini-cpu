// 程序测试：软件乘法和除法（rv32i 没有 M 扩展）。
//
// mulu：移位相加，x10 = (x11 * x12) mod 2^32。
// divu：恢复余数法，x10 = x11 / x12，x11 = x11 mod x12（无符号，x12 != 0；
// 除数大于 0x80000000 时余数左移可能溢出，这里的数据都不会触发）。
// 期望值由一段独立的 Python 算出。最后把 mulu 和 divu 连起来算一次
// (a * b) mod 3329，就是 qmul 的软件版本。
//
// 失败码：
//   1..8    乘法各项
//   9..26   除法各项（每项商、余数各一个码）
//   27      0x242d2080 mod 3329（= (0x12345678 * 0x9abcdef0 mod 2^32) mod 3329）
#include "test.h"

.macro MUL a, b, expect, code
    LI      x11, \a, x7
    LI      x12, \b, x7
    PAD_DATA
    jal     x1, mulu
    PAD_JUMP
    CHECK   x10, \expect, \code
.endm

.macro DIV a, b, quot, rem, code_q, code_r
    LI      x11, \a, x7
    LI      x12, \b, x7
    PAD_DATA
    jal     x1, divu
    PAD_JUMP
    CHECK   x10, \quot, \code_q
    CHECK   x11, \rem, \code_r
.endm

TEST_BEGIN
    MUL     12345, 6789, 0x04fed79d, 1
    MUL     0xffffffff, 0xffffffff, 0x00000001, 2
    MUL     0x00010000, 0x00010000, 0x00000000, 3
    MUL     0, 0x12345678, 0, 4
    MUL     1, 0x87654321, 0x87654321, 5
    MUL     0x12345678, 0x9abcdef0, 0x242d2080, 6
    MUL     3329, 3329, 0x00a91a01, 7
    MUL     0x80000000, 3, 0x80000000, 8

    DIV     100, 7, 0xe, 0x2, 9, 10
    DIV     0xffffffff, 1, 0xffffffff, 0, 11, 12
    DIV     1000000007, 12345, 0x13c6c, 0x15fb, 13, 14
    DIV     7, 100, 0, 7, 15, 16
    DIV     0x80000000, 0x10, 0x08000000, 0, 17, 18
    DIV     0xfedcba98, 0x1234, 0x000e0042, 0x930, 19, 20
    DIV     0xffffffff, 0xffffffff, 1, 0, 21, 22
    DIV     0, 5, 0, 0, 23, 24
    DIV     0x00a91a01, 3329, 3329, 0, 25, 26

    // (a * b) mod 3329
    LI      x11, 0x12345678, x7
    LI      x12, 0x9abcdef0, x7
    PAD_DATA
    jal     x1, mulu
    PAD_JUMP
    addi    x11, x10, 0
    LI      x12, 3329, x7
    PAD_DATA
    jal     x1, divu
    PAD_JUMP
    CHECK   x11, 0x252, 27
TEST_END

// x10 = x11 * x12（低 32 位）；用到 x13、x14
mulu:
    addi    x10, x0, 0
    addi    x13, x11, 0
    addi    x14, x12, 0
.Lmul_loop:
    PAD_DATA
    beq     x14, x0, .Lmul_done
    PAD_JUMP
    andi    x5, x14, 1
    PAD_DATA
    beq     x5, x0, .Lmul_skip
    PAD_JUMP
    add     x10, x10, x13
.Lmul_skip:
    slli    x13, x13, 1
    srli    x14, x14, 1
    jal     x0, .Lmul_loop
    PAD_JUMP
.Lmul_done:
    jalr    x0, 0(x1)
    PAD_JUMP

// x10 = x11 / x12，x11 = x11 mod x12；用到 x13、x14、x15
divu:
    addi    x10, x0, 0                  // 商
    addi    x13, x0, 0                  // 余数
    addi    x14, x0, 32                 // 剩余位数
.Ldiv_loop:
    PAD_DATA
    srli    x15, x11, 31                // 被除数的最高位移进余数
    slli    x13, x13, 1
    PAD_DATA
    or      x13, x13, x15
    slli    x11, x11, 1
    slli    x10, x10, 1
    PAD_DATA
    bltu    x13, x12, .Ldiv_next
    PAD_JUMP
    sub     x13, x13, x12
    ori     x10, x10, 1
.Ldiv_next:
    addi    x14, x14, -1
    PAD_DATA
    bne     x14, x0, .Ldiv_loop
    PAD_JUMP
    addi    x11, x13, 0
    jalr    x0, 0(x1)
    PAD_JUMP
