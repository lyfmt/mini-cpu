// rv32i 单指令测试：bltu（无符号小于）。期望值按 RISC-V 规范手工计算。
//
// 覆盖：无符号边界 0x80000000、0x7fffffff、0xffffffff、0；相等不跳；第 1、3 项
// 按有符号比较时结果相反；与 x0 比较；向前跳和向后跳（计数循环）。
//
// 失败码：每个用例的最后一个参数，说明见行尾注释。
#include "test.h"

TEST_BEGIN
    TEST_BR bltu, 0x7fffffff, 0x80000000, 1, 1           // 无符号：0x7fffffff < 0x80000000
    TEST_BR bltu, 0x80000000, 0x7fffffff, 0, 2
    TEST_BR bltu, 0x00000000, 0xffffffff, 1, 3           // 0 < 0xffffffff
    TEST_BR bltu, 0xffffffff, 0x00000000, 0, 4
    TEST_BR bltu, 0, 0, 0, 5                             // 相等不跳
    TEST_BR bltu, 0xffffffff, 0xffffffff, 0, 6
    TEST_BR bltu, 0xfffffffe, 0xffffffff, 1, 7
    TEST_BR bltu, 0, 1, 1, 8
    TEST_BR bltu, 1, 0, 0, 9
    TEST_BR bltu, 0x80000000, 0x80000001, 1, 10

    // 与 x0 比较：任何数都不小于 0；0 小于任何非 0 数
    LI      x5, 0x80000000
    PAD_DATA
    bltu    x5, x0, .Lfail11
    PAD_JUMP
    bltu    x0, x5, 1f
    PAD_JUMP
    TEST_FAIL 12
1:

    // 向后跳：x5 从 0 起每次加 0x20000000，加完是 0x20000000、0x40000000、
    // 0x60000000 时继续，到 0x80000000 停，循环 4 次
    LI      x5, 0
    LI      x6, 0x80000000
    LI      x7, 0x20000000
    LI      x11, 0
    PAD_DATA
.Lloop:
    add     x5, x5, x7
    addi    x11, x11, 1
    PAD_DATA
    bltu    x5, x6, .Lloop
    PAD_JUMP
    CHECK   x11, 4, 13
TEST_END

.Lfail11:
    TEST_FAIL 11
