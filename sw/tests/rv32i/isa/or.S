// rv32i 单指令测试：or。期望值按 RISC-V 规范手工计算。
//
// 覆盖：交错位型、互补位型、最高位与最低位、全 0、x0 操作数、rd 与源相同、写 x0。
//
// 失败码：每个用例的最后一个参数，说明见行尾注释。
#include "test.h"

TEST_BEGIN
    TEST_RR or, 0xff00ff00, 0x0ff00ff0, 0xfff0fff0, 1    // 交错
    TEST_RR or, 0xaaaaaaaa, 0x55555555, 0xffffffff, 2    // 互补
    TEST_RR or, 0x80000000, 0x00000001, 0x80000001, 3    // 两端
    TEST_RR or, 0, 0, 0, 4                               // 全 0
    TEST_RR or, 0x12340000, 0x00005678, 0x12345678, 5    // 拼接

    // x0 操作数
    LI      x5, 0x87654321, x7
    PAD_DATA
    or      x10, x5, x0
    PAD_DATA
    CHECK   x10, 0x87654321, 6
    or      x10, x0, x0
    PAD_DATA
    CHECK   x10, 0, 7

    // rd = rs1
    LI      x6, 0x0000000f
    PAD_DATA
    or      x5, x5, x6
    PAD_DATA
    CHECK   x5, 0x8765432f, 8

    // 写 x0 无效
    or      x0, x5, x6
    PAD_DATA
    CHECK   x0, 0, 9
TEST_END
