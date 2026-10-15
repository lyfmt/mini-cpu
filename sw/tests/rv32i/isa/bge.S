// rv32i 单指令测试：bge（有符号大于等于）。期望值按 RISC-V 规范手工计算。
//
// 覆盖：有符号边界 0x80000000、0x7fffffff、-1、0；相等时跳；第 1、3 项按无符号
// 比较时结果相反；与 x0 比较；向前跳和向后跳（计数循环）。
//
// 失败码：每个用例的最后一个参数，说明见行尾注释。
#include "test.h"

TEST_BEGIN
    TEST_BR bge, 0x7fffffff, 0x80000000, 1, 1            // 最大正数 >= 最小负数
    TEST_BR bge, 0x80000000, 0x7fffffff, 0, 2
    TEST_BR bge, 0x00000000, 0xffffffff, 1, 3            // 0 >= -1
    TEST_BR bge, 0xffffffff, 0x00000000, 0, 4
    TEST_BR bge, 0, 0, 1, 5                              // 相等时跳
    TEST_BR bge, 0x80000000, 0x80000000, 1, 6
    TEST_BR bge, 0xffffffff, 0xfffffffe, 1, 7            // -1 >= -2
    TEST_BR bge, 0xfffffffe, 0xffffffff, 0, 8
    TEST_BR bge, 1, 0, 1, 9
    TEST_BR bge, 0, 1, 0, 10
    TEST_BR bge, 0xffffffff, 0x80000000, 1, 11

    // 与 x0 比较
    LI      x5, 0xfffffff0
    PAD_DATA
    bge     x0, x5, 1f                                   // 0 >= -16
    PAD_JUMP
    TEST_FAIL 12
1:
    bge     x5, x0, .Lfail13
    PAD_JUMP

    // 向后跳：x5 从 4 减到 -1，循环 5 次（x5 >= 0 时继续）
    LI      x5, 4
    LI      x11, 0
    PAD_DATA
.Lloop:
    addi    x5, x5, -1
    addi    x11, x11, 1
    PAD_DATA
    bge     x5, x0, .Lloop
    PAD_JUMP
    CHECK   x11, 5, 14
    CHECK   x5, 0xffffffff, 15
TEST_END

.Lfail13:
    TEST_FAIL 13
