// rv32i 单指令测试：and。期望值按 RISC-V 规范手工计算。
//
// 覆盖：交错位型、全 1、互补位型、最高位与最低位、x0 操作数、rd 与源相同、写 x0。
//
// 失败码：每个用例的最后一个参数，说明见行尾注释。
#include "test.h"

TEST_BEGIN
    TEST_RR and, 0xff00ff00, 0x0ff00ff0, 0x0f000f00, 1   // 交错
    TEST_RR and, 0xffffffff, 0x12345678, 0x12345678, 2   // 全 1
    TEST_RR and, 0x80000001, 0x7fffffff, 0x00000001, 3   // 最高位去掉
    TEST_RR and, 0xaaaaaaaa, 0x55555555, 0, 4            // 互补
    TEST_RR and, 0xaaaaaaaa, 0xaaaaaaaa, 0xaaaaaaaa, 5   // 相同
    TEST_RR and, 0x80000000, 0x80000000, 0x80000000, 6   // 只有最高位

    // x0 操作数
    LI      x5, 0xffffffff
    PAD_DATA
    and     x10, x5, x0
    PAD_DATA
    CHECK   x10, 0, 7
    and     x10, x0, x5
    PAD_DATA
    CHECK   x10, 0, 8

    // rd = rs1 = rs2
    LI      x5, 0x5a0f, x7
    PAD_DATA
    and     x5, x5, x5
    PAD_DATA
    CHECK   x5, 0x5a0f, 9

    // 写 x0 无效
    and     x0, x5, x5
    PAD_DATA
    CHECK   x0, 0, 10
TEST_END
