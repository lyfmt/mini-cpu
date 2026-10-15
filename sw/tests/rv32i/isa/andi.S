// rv32i 单指令测试：andi。期望值按 RISC-V 规范手工计算。
//
// 覆盖：立即数先符号扩展再与：-1 保留全部位，-2048（0xfffff800）清低 11 位，
// 2047 只留低 11 位；最高位；立即数 0；rd = rs1；写 x0。
//
// 失败码：每个用例的最后一个参数，说明见行尾注释。
#include "test.h"

TEST_BEGIN
    TEST_RI andi, 0xff00ff00, 0x7ff, 0x00000700, 1
    TEST_RI andi, 0x12345678, -1, 0x12345678, 2          // 0xffffffff
    TEST_RI andi, 0x12345678, -2048, 0x12345000, 3       // 0xfffff800
    TEST_RI andi, 0x12345fff, -2048, 0x12345800, 4
    TEST_RI andi, 0xffffffff, 0, 0, 5
    TEST_RI andi, 0xffffffff, 0x7f, 0x0000007f, 6
    TEST_RI andi, 0x80000000, -1, 0x80000000, 7          // 高位来自符号扩展
    TEST_RI andi, 0x80000000, 2047, 0, 8
    TEST_RI andi, 0xfffffff7, -16, 0xfffffff0, 9         // 0xfffffff0

    // rd = rs1
    LI      x5, 0xabcdef12, x7
    PAD_DATA
    andi    x5, x5, 0x0ff
    PAD_DATA
    CHECK   x5, 0x00000012, 10

    // 写 x0 无效
    andi    x0, x5, -1
    PAD_DATA
    CHECK   x0, 0, 11
TEST_END
