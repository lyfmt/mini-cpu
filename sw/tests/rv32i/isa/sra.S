// rv32i 单指令测试：sra。期望值按 RISC-V 规范手工计算。
//
// 覆盖：移 0 位和 31 位；负数高位补符号位（与 srl.S 对同一组负数的结果对照）；
// 正数与 srl 相同；移位量只取 rs2 的低 5 位（32、33、-1）；rs2 = x0；rd = rs1。
// sra 与 srl 的 funct3 相同，靠指令第 30 位区分。
//
// 失败码：每个用例的最后一个参数，说明见行尾注释。
#include "test.h"

TEST_BEGIN
    TEST_RR sra, 0x80000000, 0, 0x80000000, 1            // 移 0 位
    TEST_RR sra, 0x80000000, 31, 0xffffffff, 2           // 移 31 位
    TEST_RR sra, 0x7fffffff, 31, 0x00000000, 3
    TEST_RR sra, 0x80000000, 1, 0xc0000000, 4            // （srl 得 0x40000000）
    TEST_RR sra, 0x87654321, 1, 0xc3b2a190, 5            // （srl 得 0x43b2a190）
    TEST_RR sra, 0x87654321, 8, 0xff876543, 6            // （srl 得 0x00876543）
    TEST_RR sra, 0xf0000000, 4, 0xff000000, 7            // （srl 得 0x0f000000）
    TEST_RR sra, 0x12345678, 4, 0x01234567, 8            // 正数与 srl 相同
    TEST_RR sra, 0x7fffffff, 1, 0x3fffffff, 9
    TEST_RR sra, 0x87654321, 32, 0x87654321, 10          // 32 -> 0
    TEST_RR sra, 0x87654321, 33, 0xc3b2a190, 11          // 33 -> 1
    TEST_RR sra, 0x87654321, 0xffffffff, 0xffffffff, 12  // -1 -> 31
    TEST_RR sra, 0xffffffff, 17, 0xffffffff, 13          // -1 怎么移都是 -1

    // rs2 = x0
    LI      x5, 0x80000000
    PAD_DATA
    sra     x10, x5, x0
    PAD_DATA
    CHECK   x10, 0x80000000, 14

    // rd = rs1
    LI      x6, 28
    PAD_DATA
    sra     x5, x5, x6
    PAD_DATA
    CHECK   x5, 0xfffffff8, 15
TEST_END
