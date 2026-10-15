// add rd, rs1, rs2：rd <- rs1 + rs2，取低 32 位，不检测溢出。
//
// 失败码：
//   1  3 + 5 = 8
//   2  0x7fffffff + 1 = 0x80000000（最大正数加 1，有符号溢出）
//   3  0xffffffff + 1 = 0（无符号溢出，进位丢弃）
//   4  0x80000000 + 0x80000000 = 0
//   5  -3 + -5 = -8 = 0xfffffff8
//   6  0x12345678 + 0x0fedcba9 = 0x22222221（多位进位）
//   7  rs1 = x0：0 + 5 = 5
//   8  rs2 = x0：0xffffffff + 0 = 0xffffffff
//   9  rd = rs1 = rs2：0x40000001 + 0x40000001 = 0x80000002
//  10  add x0, ... 之后 x0 仍为 0
//  11  写 x0 之后 add x16, x0, x0 = 0
#include "test.h"

TEST_BEGIN
    LI      x1, 3
    LI      x2, 5
    LI      x3, 0x7fffffff, x20
    LI      x4, 1
    LI      x5, 0xffffffff
    LI      x6, 0x80000000
    LI      x7, -3
    LI      x8, -5
    LI      x9, 0x12345678
    LI      x10, 0x0fedcba9, x20
    LI      x15, 0x40000001
    PAD_DATA

    add     x11, x1, x2
    add     x12, x3, x4
    add     x13, x5, x4
    add     x14, x6, x6
    add     x17, x7, x8
    add     x18, x9, x10
    add     x19, x0, x2
    add     x21, x5, x0
    add     x15, x15, x15
    add     x0, x1, x2
    add     x16, x0, x0

    CHECK   x11, 8, 1
    CHECK   x12, 0x80000000, 2
    CHECK   x13, 0, 3
    CHECK   x14, 0, 4
    CHECK   x17, 0xfffffff8, 5
    CHECK   x18, 0x22222221, 6
    CHECK   x19, 5, 7
    CHECK   x21, 0xffffffff, 8
    CHECK   x15, 0x80000002, 9
    CHECK   x0, 0, 10
    CHECK   x16, 0, 11
TEST_END
