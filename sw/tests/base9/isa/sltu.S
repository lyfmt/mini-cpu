// sltu rd, rs1, rs2：rd <- (rs1 < rs2，按无符号数) ? 1 : 0
//
// 失败码：
//   1  1 < 2 -> 1
//   2  2 < 1 -> 0
//   3  7 < 7 -> 0（相等）
//   4  0xffffffff < 1 -> 0（有符号比较会得 1）
//   5  1 < 0xffffffff -> 1（有符号比较会得 0）
//   6  0x80000000 < 0x7fffffff -> 0
//   7  0x7fffffff < 0x80000000 -> 1
//   8  0xfffffffe < 0xffffffff -> 1
//   9  rs1 = x0：0 < 5 -> 1（即"不等于 0"）
//  10  rs1 = rs2 = x0：0 < 0 -> 0
//  11  rs2 = x0：0xffffffff < 0 -> 0（任何数都不小于 0）
//  12  rd = rs2：x6 = (1 < x6)，x6 = 0xffffffff -> 1
//  13  sltu x0, ... 之后 x0 仍为 0
#include "test.h"

TEST_BEGIN
    LI      x1, 1
    LI      x2, 2
    LI      x3, 7
    LI      x4, 0xffffffff
    LI      x5, 0x80000000
    LI      x6, 0x7fffffff, x20
    LI      x7, 0xfffffffe
    LI      x8, 5
    LI      x26, 0xffffffff
    PAD_DATA

    sltu    x10, x1, x2
    sltu    x11, x2, x1
    sltu    x12, x3, x3
    sltu    x13, x4, x1
    sltu    x14, x1, x4
    sltu    x15, x5, x6
    sltu    x16, x6, x5
    sltu    x17, x7, x4
    sltu    x18, x0, x8
    sltu    x19, x0, x0
    sltu    x21, x4, x0
    sltu    x26, x1, x26
    sltu    x0, x1, x2

    CHECK   x10, 1, 1
    CHECK   x11, 0, 2
    CHECK   x12, 0, 3
    CHECK   x13, 0, 4
    CHECK   x14, 1, 5
    CHECK   x15, 0, 6
    CHECK   x16, 1, 7
    CHECK   x17, 1, 8
    CHECK   x18, 1, 9
    CHECK   x19, 0, 10
    CHECK   x21, 0, 11
    CHECK   x26, 1, 12
    CHECK   x0, 0, 13
TEST_END
