// rv32i 单指令测试：blt（有符号小于）。期望值按 RISC-V 规范手工计算。
//
// 覆盖：有符号边界 0x80000000、0x7fffffff、-1、0；相等不跳；最小负数小于 -1；
// 第 1、3 项按无符号比较时结果相反；与 x0 比较；向前跳和向后跳（计数循环）。
//
// 失败码：每个用例的最后一个参数，说明见行尾注释。
#include "test.h"

TEST_BEGIN
    TEST_BR blt, 0x80000000, 0x7fffffff, 1, 1            // 最小负数 < 最大正数
    TEST_BR blt, 0x7fffffff, 0x80000000, 0, 2
    TEST_BR blt, 0xffffffff, 0x00000000, 1, 3            // -1 < 0
    TEST_BR blt, 0x00000000, 0xffffffff, 0, 4
    TEST_BR blt, 0, 0, 0, 5                              // 相等不跳
    TEST_BR blt, 0x80000000, 0x80000000, 0, 6
    TEST_BR blt, 0x80000000, 0xffffffff, 1, 7            // 最小负数 < -1
    TEST_BR blt, 0xfffffffe, 0xffffffff, 1, 8            // -2 < -1
    TEST_BR blt, 0, 1, 1, 9
    TEST_BR blt, 1, 0, 0, 10
    TEST_BR blt, 0xffffffff, 0x7fffffff, 1, 11

    // 与 x0 比较：x0 < 5
    LI      x5, 5
    PAD_DATA
    blt     x0, x5, 1f
    PAD_JUMP
    TEST_FAIL 12
1:
    blt     x5, x0, .Lfail13
    PAD_JUMP

    // 向后跳：x5 从 -3 数到 2，循环 5 次
    LI      x5, 0xfffffffd
    LI      x6, 2
    LI      x11, 0
    PAD_DATA
.Lloop:
    addi    x5, x5, 1
    addi    x11, x11, 1
    PAD_DATA
    blt     x5, x6, .Lloop
    PAD_JUMP
    CHECK   x11, 5, 14
TEST_END

.Lfail13:
    TEST_FAIL 13
