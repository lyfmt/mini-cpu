// rv32i 单指令测试：sll。期望值按 RISC-V 规范手工计算。
//
// 覆盖：移 0 位和 31 位；移位量只取 rs2 的低 5 位（32 当 0、33 当 1、
// -1 当 31、0xffffffe0 当 0）；移出最高位；rs2 = x0；rd = rs1。
//
// 失败码：每个用例的最后一个参数，说明见行尾注释。
#include "test.h"

TEST_BEGIN
    TEST_RR sll, 1, 0, 1, 1                              // 移 0 位
    TEST_RR sll, 1, 31, 0x80000000, 2                    // 移 31 位
    TEST_RR sll, 0x12345678, 4, 0x23456780, 3
    TEST_RR sll, 0xffffffff, 31, 0x80000000, 4
    TEST_RR sll, 0x80000001, 1, 0x00000002, 5            // 最高位移出
    TEST_RR sll, 0x12345678, 32, 0x12345678, 6           // 32 只取低 5 位 = 0
    TEST_RR sll, 0x12345678, 33, 0x2468acf0, 7           // 33 -> 1
    TEST_RR sll, 0x00000003, 0xffffffff, 0x80000000, 8   // -1 -> 31
    TEST_RR sll, 0xdeadbeef, 0xffffffe0, 0xdeadbeef, 9   // 低 5 位为 0
    TEST_RR sll, 0x00000001, 0x0000001f, 0x80000000, 10
    TEST_RR sll, 0x0000000f, 0x00000104, 0x000000f0, 11  // 0x104 -> 4

    // rs2 = x0：不移位
    LI      x5, 0x0badf00d, x7
    PAD_DATA
    sll     x10, x5, x0
    PAD_DATA
    CHECK   x10, 0x0badf00d, 12

    // rd = rs1
    LI      x6, 8
    PAD_DATA
    sll     x5, x5, x6
    PAD_DATA
    CHECK   x5, 0xadf00d00, 13
TEST_END
