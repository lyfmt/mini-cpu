// rv32i 单指令测试：slli。期望值按 RISC-V 规范手工计算。
//
// 覆盖：移 0 位和 31 位、移出最高位、rd = rs1、写 x0。
//
// 失败码：每个用例的最后一个参数，说明见行尾注释。
#include "test.h"

TEST_BEGIN
    TEST_RI slli, 1, 0, 1, 1                             // 移 0 位
    TEST_RI slli, 1, 31, 0x80000000, 2                   // 移 31 位
    TEST_RI slli, 0xffffffff, 31, 0x80000000, 3
    TEST_RI slli, 0x12345678, 4, 0x23456780, 4
    TEST_RI slli, 0x80000001, 1, 0x00000002, 5           // 最高位移出
    TEST_RI slli, 0x00000003, 30, 0xc0000000, 6
    TEST_RI slli, 0x0000ffff, 16, 0xffff0000, 7

    // rd = rs1
    LI      x5, 0x00abcdef, x7
    PAD_DATA
    slli    x5, x5, 8
    PAD_DATA
    CHECK   x5, 0xabcdef00, 8

    // 写 x0 无效
    slli    x0, x5, 1
    PAD_DATA
    CHECK   x0, 0, 9
TEST_END
