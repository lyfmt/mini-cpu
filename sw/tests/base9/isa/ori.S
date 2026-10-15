// ori rd, rs1, imm：rd <- rs1 | 符号扩展(imm12)
//
// 立即数是符号扩展的：imm 第 11 位为 1 时，结果的高 20 位全为 1（与 MIPS 不同）。
//
// 失败码：
//   1  0 | 0x7ff = 0x000007ff（最大正立即数，不扩展出 1）
//   2  0 | -1 = 0xffffffff
//   3  0 | -2048 = 0xfffff800（最小负立即数）
//   4  0x12345000 | 0x0ff = 0x123450ff
//   5  0x12345000 | -2048 = 0xfffff800（负立即数把高位全部置 1）
//   6  0x0000f0f0 | 0x70f = 0x0000f7ff
//   7  0x80000001 | 0 = 0x80000001（立即数为 0，相当于复制）
//   8  rd = rs1：0xaaaaa000 | 0x555 = 0xaaaaa555
//   9  0x12345678 | -1 = 0xffffffff
//  10  0x00000010 | -16 (0xff0) = 0xfffffff0
//  11  ori x0, ... 之后 x0 仍为 0
#include "test.h"

TEST_BEGIN
    LI      x1, 0x12345000
    LI      x2, 0x0000f0f0
    LI      x3, 0x80000001
    LI      x4, 0xaaaaa000
    LI      x5, 0x12345678
    LI      x6, 0x10
    PAD_DATA

    ori     x10, x0, 0x7ff
    ori     x11, x0, -1
    ori     x12, x0, -2048
    ori     x13, x1, 0x0ff
    ori     x14, x1, -2048
    ori     x15, x2, 0x70f
    ori     x16, x3, 0
    ori     x4, x4, 0x555
    ori     x17, x5, -1
    ori     x18, x6, -16
    ori     x0, x5, 0x123

    CHECK   x10, 0x000007ff, 1
    CHECK   x11, 0xffffffff, 2
    CHECK   x12, 0xfffff800, 3
    CHECK   x13, 0x123450ff, 4
    CHECK   x14, 0xfffff800, 5
    CHECK   x15, 0x0000f7ff, 6
    CHECK   x16, 0x80000001, 7
    CHECK   x4, 0xaaaaa555, 8
    CHECK   x17, 0xffffffff, 9
    CHECK   x18, 0xfffffff0, 10
    CHECK   x0, 0, 11
TEST_END
