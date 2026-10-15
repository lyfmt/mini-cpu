// rv32i 单指令测试：bne。期望值按 RISC-V 规范手工计算。
//
// 覆盖：相等（不跳）与不等（跳），只差最高位或最低位；同一寄存器比较；
// 与 x0 比较；向前跳（TEST_BR）和向后跳（计数循环）。
//
// 失败码：每个用例的最后一个参数，说明见行尾注释。
#include "test.h"

TEST_BEGIN
    TEST_BR bne, 0, 0, 0, 1                              // 相等，不跳
    TEST_BR bne, 1, 0, 1, 2
    TEST_BR bne, 0x80000000, 0x80000000, 0, 3
    TEST_BR bne, 0x80000000, 0x00000000, 1, 4            // 只差最高位
    TEST_BR bne, 0xffffffff, 0x7fffffff, 1, 5            // 只差最高位
    TEST_BR bne, 0x12345679, 0x12345678, 1, 6            // 只差最低位
    TEST_BR bne, 0xffffffff, 0xffffffff, 0, 7

    // 同一寄存器：永远相等
    LI      x5, 0x7777
    PAD_DATA
    bne     x5, x5, .Lfail8
    PAD_JUMP

    // 与 x0 比较
    bne     x5, x0, 1f
    PAD_JUMP
    TEST_FAIL 9
1:
    bne     x0, x0, .Lfail10
    PAD_JUMP

    // 向后跳：x5 从 0 数到 5，循环体执行 5 次
    LI      x5, 0
    LI      x6, 5
    LI      x11, 0
    PAD_DATA
.Lloop:
    addi    x5, x5, 1
    addi    x11, x11, 3
    PAD_DATA
    bne     x5, x6, .Lloop
    PAD_JUMP
    CHECK   x11, 15, 11
TEST_END

.Lfail8:
    TEST_FAIL 8
.Lfail10:
    TEST_FAIL 10
