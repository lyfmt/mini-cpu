// rv32i 单指令测试：xori。期望值按 RISC-V 规范手工计算。
//
// 覆盖：立即数符号扩展：xori -1 即按位取反，-2048 翻转高 21 位；2047；
// 立即数 0；rd = rs1；写 x0。
//
// 失败码：每个用例的最后一个参数，说明见行尾注释。
#include "test.h"

TEST_BEGIN
    TEST_RI xori, 0x00ff00ff, 0x0f0, 0x00ff000f, 1
    TEST_RI xori, 0x12345678, -1, 0xedcba987, 2          // 取反
    TEST_RI xori, 0x00000000, -2048, 0xfffff800, 3
    TEST_RI xori, 0xffffffff, 2047, 0xfffff800, 4
    TEST_RI xori, 0xfffff800, -2048, 0x00000000, 5
    TEST_RI xori, 0x80000000, 1, 0x80000001, 6
    TEST_RI xori, 0x12345678, 0, 0x12345678, 7
    TEST_RI xori, 0x7fffffff, -1, 0x80000000, 8

    // rd = rs1
    LI      x5, 0x0000555
    PAD_DATA
    xori    x5, x5, 0x7ff
    PAD_DATA
    CHECK   x5, 0x000002aa, 9

    // 写 x0 无效
    xori    x0, x5, -1
    PAD_DATA
    CHECK   x0, 0, 10
TEST_END
