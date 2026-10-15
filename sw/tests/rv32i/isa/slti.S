// rv32i 单指令测试：slti。期望值按 RISC-V 规范手工计算。
//
// 覆盖：立即数符号扩展后按有符号数比较：负立即数、立即数边界 -2048 和 2047、
// 相等（不成立）、最小负数和最大正数、-1 与 1（sltiu 结果相反）；rd = rs1；写 x0。
//
// 失败码：每个用例的最后一个参数，说明见行尾注释。
#include "test.h"

TEST_BEGIN
    TEST_RI slti, 0, 0, 0, 1                             // 相等
    TEST_RI slti, 0, 1, 1, 2
    TEST_RI slti, 0xffffffff, 0, 1, 3                    // -1 < 0
    TEST_RI slti, 0, -1, 0, 4                            // 0 < -1 不成立
    TEST_RI slti, 0x80000000, -2048, 1, 5                // 最小负数
    TEST_RI slti, 0x7fffffff, 2047, 0, 6                 // 最大正数
    TEST_RI slti, 0xfffff7ff, -2048, 1, 7                // -2049 < -2048
    TEST_RI slti, 0xfffff800, -2048, 0, 8                // 相等
    TEST_RI slti, 2046, 2047, 1, 9
    TEST_RI slti, 2047, 2047, 0, 10
    TEST_RI slti, 0xffffffff, 1, 1, 11                   // -1 < 1（sltiu 不成立）
    TEST_RI slti, 0x00000800, -1, 0, 12                  // 2048 < -1 不成立
    TEST_RI slti, 0xfffffffe, -1, 1, 13                  // -2 < -1

    // rd = rs1
    LI      x5, 0xfffffff0
    PAD_DATA
    slti    x5, x5, -15
    PAD_DATA
    CHECK   x5, 1, 14

    // 写 x0 无效
    slti    x0, x5, 2
    PAD_DATA
    CHECK   x0, 0, 15
TEST_END
