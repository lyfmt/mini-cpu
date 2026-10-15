// rv32i 单指令测试：srl。期望值按 RISC-V 规范手工计算。
//
// 覆盖：移 0 位和 31 位；高位补 0（与 sra.S 对同一组负数的结果对照）；
// 移位量只取 rs2 的低 5 位（32、33、-1）；rs2 = x0；rd = rs1 = rs2。
//
// 失败码：每个用例的最后一个参数，说明见行尾注释。
#include "test.h"

TEST_BEGIN
    TEST_RR srl, 0x80000000, 0, 0x80000000, 1            // 移 0 位
    TEST_RR srl, 0x80000000, 31, 0x00000001, 2           // 移 31 位
    TEST_RR srl, 0xffffffff, 31, 0x00000001, 3
    TEST_RR srl, 0x80000000, 1, 0x40000000, 4            // 负数高位补 0（sra 得 0xc0000000）
    TEST_RR srl, 0x87654321, 1, 0x43b2a190, 5            // （sra 得 0xc3b2a190）
    TEST_RR srl, 0x87654321, 8, 0x00876543, 6            // （sra 得 0xff876543）
    TEST_RR srl, 0xf0000000, 4, 0x0f000000, 7            // （sra 得 0xff000000）
    TEST_RR srl, 0x12345678, 4, 0x01234567, 8            // 正数
    TEST_RR srl, 0x12345678, 32, 0x12345678, 9           // 32 -> 0
    TEST_RR srl, 0x12345678, 33, 0x091a2b3c, 10          // 33 -> 1
    TEST_RR srl, 0x80000000, 0xffffffff, 0x00000001, 11  // -1 -> 31

    // rs2 = x0
    LI      x5, 0x80000000
    PAD_DATA
    srl     x10, x5, x0
    PAD_DATA
    CHECK   x10, 0x80000000, 12

    // rd = rs1 = rs2：0x00000024 右移 4（低 5 位 = 4）
    LI      x5, 0x24
    PAD_DATA
    srl     x5, x5, x5
    PAD_DATA
    CHECK   x5, 0x00000002, 13
TEST_END
