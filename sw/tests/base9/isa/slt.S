// slt rd, rs1, rs2：rd <- (rs1 < rs2，按有符号数) ? 1 : 0
//
// 失败码：
//   1  1 < 2 -> 1
//   2  2 < 1 -> 0
//   3  5 < 5 -> 0（相等）
//   4  -1 < 1 -> 1（无符号比较会得 0）
//   5  1 < -1 -> 0（无符号比较会得 1）
//   6  0x80000000 < 0x7fffffff -> 1（最小负数 < 最大正数）
//   7  0x7fffffff < 0x80000000 -> 0
//   8  -2 < -1 -> 1
//   9  -1 < -2 -> 0
//  10  rs2 = x0：0x80000000 < 0 -> 1
//  11  rs1 = x0：0 < -1 -> 0
//  12  rd = rs1：x1 = (x1 < x2)，1 < 2 -> 1
//  13  slt x0, ... 之后 x0 仍为 0
#include "test.h"

TEST_BEGIN
    LI      x1, 1
    LI      x2, 2
    LI      x3, 5
    LI      x4, -1
    LI      x5, 0x80000000
    LI      x6, 0x7fffffff, x20
    LI      x7, -2
    LI      x25, 1
    PAD_DATA

    slt     x10, x1, x2
    slt     x11, x2, x1
    slt     x12, x3, x3
    slt     x13, x4, x1
    slt     x14, x1, x4
    slt     x15, x5, x6
    slt     x16, x6, x5
    slt     x17, x7, x4
    slt     x18, x4, x7
    slt     x19, x5, x0
    slt     x21, x0, x4
    slt     x25, x25, x2
    slt     x0, x1, x2

    CHECK   x10, 1, 1
    CHECK   x11, 0, 2
    CHECK   x12, 0, 3
    CHECK   x13, 1, 4
    CHECK   x14, 0, 5
    CHECK   x15, 1, 6
    CHECK   x16, 0, 7
    CHECK   x17, 1, 8
    CHECK   x18, 0, 9
    CHECK   x19, 1, 10
    CHECK   x21, 0, 11
    CHECK   x25, 1, 12
    CHECK   x0, 0, 13
TEST_END
