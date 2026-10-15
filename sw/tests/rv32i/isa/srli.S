// rv32i 单指令测试：srli。期望值按 RISC-V 规范手工计算。
//
// 覆盖：移 0 位和 31 位、负数高位补 0（与 srai.S 对同一组负数对照）、
// rd = rs1、写 x0。srli 与 srai 靠指令第 30 位区分。
//
// 失败码：每个用例的最后一个参数，说明见行尾注释。
#include "test.h"

TEST_BEGIN
    TEST_RI srli, 0x80000000, 0, 0x80000000, 1           // 移 0 位
    TEST_RI srli, 0x80000000, 31, 0x00000001, 2          // 移 31 位
    TEST_RI srli, 0xffffffff, 31, 0x00000001, 3
    TEST_RI srli, 0x87654321, 1, 0x43b2a190, 4           // （srai 得 0xc3b2a190）
    TEST_RI srli, 0x87654321, 8, 0x00876543, 5           // （srai 得 0xff876543）
    TEST_RI srli, 0x12345678, 4, 0x01234567, 6
    TEST_RI srli, 0xffffffff, 16, 0x0000ffff, 7          // （srai 得 0xffffffff）

    // rd = rs1
    LI      x5, 0xabcdef00, x7
    PAD_DATA
    srli    x5, x5, 8
    PAD_DATA
    CHECK   x5, 0x00abcdef, 8

    // 写 x0 无效
    srli    x0, x5, 1
    PAD_DATA
    CHECK   x0, 0, 9
TEST_END
