// rv32i 单指令测试：addi。期望值按 RISC-V 规范手工计算。
//
// 覆盖：立即数边界 2047、-2048、-1；结果溢出（最大正数加 1、最小负数减 1）；
// 进位穿过第 11 位；负立即数做减法；rs1 = x0（相当于 li）；rd = rs1；写 x0。
//
// 失败码：每个用例的最后一个参数，说明见行尾注释。
#include "test.h"

TEST_BEGIN
    TEST_RI addi, 0, 0, 0, 1
    TEST_RI addi, 1, 1, 2, 2
    TEST_RI addi, 3, 7, 10, 3
    TEST_RI addi, 0, -1, 0xffffffff, 4                   // 立即数符号扩展
    TEST_RI addi, 0, 2047, 0x000007ff, 5                 // 最大立即数
    TEST_RI addi, 0, -2048, 0xfffff800, 6                // 最小立即数
    TEST_RI addi, 0x7fffffff, 1, 0x80000000, 7           // 溢出
    TEST_RI addi, 0x80000000, -1, 0x7fffffff, 8          // 溢出
    TEST_RI addi, 0xffffffff, 1, 0, 9                    // 进位溢出到第 32 位
    TEST_RI addi, 0x12345678, -1656, 0x12345000, 10      // -0x678
    TEST_RI addi, 0x000007ff, 1, 0x00000800, 11          // 进位到第 11 位
    TEST_RI addi, 0x00001000, -2048, 0x00000800, 12
    TEST_RI addi, 0x7ffff800, 2047, 0x7fffffff, 13

    // rs1 = x0
    addi    x10, x0, 1234
    PAD_DATA
    CHECK   x10, 1234, 14

    // rd = rs1
    LI      x5, 0x10000
    PAD_DATA
    addi    x5, x5, -1
    PAD_DATA
    CHECK   x5, 0x0000ffff, 15

    // 写 x0 无效
    addi    x0, x5, 5
    PAD_DATA
    CHECK   x0, 0, 16
TEST_END
