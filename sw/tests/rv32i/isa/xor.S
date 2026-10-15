// rv32i 单指令测试：xor。期望值按 RISC-V 规范手工计算。
//
// 覆盖：交错位型、互补位型、自己异或自己、翻转最高位、x0 操作数、写 x0。
//
// 失败码：每个用例的最后一个参数，说明见行尾注释。
#include "test.h"

TEST_BEGIN
    TEST_RR xor, 0xff00ff00, 0x0ff00ff0, 0xf0f0f0f0, 1   // 交错
    TEST_RR xor, 0xaaaaaaaa, 0x55555555, 0xffffffff, 2   // 互补
    TEST_RR xor, 0xffffffff, 0x80000000, 0x7fffffff, 3   // 翻转最高位
    TEST_RR xor, 0x12345678, 0xffffffff, 0xedcba987, 4   // 按位取反
    TEST_RR xor, 0x0000ffff, 0x00ff00ff, 0x00ffff00, 5

    // rd = rs1 = rs2：结果为 0
    LI      x5, 0x13579bdf, x7
    PAD_DATA
    xor     x5, x5, x5
    PAD_DATA
    CHECK   x5, 0, 6

    // x0 操作数
    LI      x6, 0x2468ace0, x7
    PAD_DATA
    xor     x10, x6, x0
    PAD_DATA
    CHECK   x10, 0x2468ace0, 7

    // 写 x0 无效
    xor     x0, x6, x6
    PAD_DATA
    CHECK   x0, 0, 8
TEST_END
