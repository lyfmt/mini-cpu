// rv32i 单指令测试：sub。期望值按 RISC-V 规范手工计算。
//
// 覆盖：正负结果、有符号溢出（两个方向）、借位传递、相等相减、
// x0 作被减数（取负）、rd 与源寄存器相同、写 x0。sub 与 add 的 funct3 相同，
// 靠指令第 30 位区分：第 1 项如果被当成 add 会得到 8。
//
// 失败码：每个用例的最后一个参数，说明见行尾注释。
#include "test.h"

TEST_BEGIN
    TEST_RR sub, 5, 3, 2, 1                              // 5 - 3
    TEST_RR sub, 3, 5, 0xfffffffe, 2                     // 3 - 5 = -2
    TEST_RR sub, 0x80000000, 1, 0x7fffffff, 3            // 最小负数减 1，溢出
    TEST_RR sub, 0x7fffffff, 0xffffffff, 0x80000000, 4   // 最大正数减 -1，溢出
    TEST_RR sub, 0, 0x80000000, 0x80000000, 5            // 0 减最小负数
    TEST_RR sub, 0, 1, 0xffffffff, 6                     // 0 - 1
    TEST_RR sub, 0x12345678, 0x12345678, 0, 7            // 相等
    TEST_RR sub, 0xffffffff, 0x7fffffff, 0x80000000, 8   // -1 减最大正数
    TEST_RR sub, 0x00010000, 1, 0x0000ffff, 9            // 借位穿过 16 位
    TEST_RR sub, 0x00000000, 0xffffffff, 1, 10           // 0 - (-1)

    // rd = rs1
    LI      x5, 100
    LI      x6, 1
    PAD_DATA
    sub     x5, x5, x6
    PAD_DATA
    CHECK   x5, 99, 11

    // rd = rs1 = rs2
    LI      x5, 0x4321, x7
    PAD_DATA
    sub     x5, x5, x5
    PAD_DATA
    CHECK   x5, 0, 12

    // x0 作被减数：取负
    LI      x5, 7
    PAD_DATA
    sub     x10, x0, x5
    PAD_DATA
    CHECK   x10, 0xfffffff9, 13

    // x0 作减数
    sub     x10, x5, x0
    PAD_DATA
    CHECK   x10, 7, 14

    // 写 x0 无效
    sub     x0, x0, x5
    PAD_DATA
    CHECK   x0, 0, 15
TEST_END
