// rv32i 单指令测试：bgeu（无符号大于等于）。期望值按 RISC-V 规范手工计算。
//
// 覆盖：无符号边界 0x80000000、0x7fffffff、0xffffffff、0；相等时跳；第 1、3 项
// 按有符号比较时结果相反；与 x0 比较；向前跳和向后跳（计数循环）。
//
// 失败码：每个用例的最后一个参数，说明见行尾注释。
#include "test.h"

TEST_BEGIN
    TEST_BR bgeu, 0x80000000, 0x7fffffff, 1, 1           // 无符号：0x80000000 >= 0x7fffffff
    TEST_BR bgeu, 0x7fffffff, 0x80000000, 0, 2
    TEST_BR bgeu, 0xffffffff, 0x00000000, 1, 3           // 0xffffffff >= 0
    TEST_BR bgeu, 0x00000000, 0xffffffff, 0, 4
    TEST_BR bgeu, 0, 0, 1, 5                             // 相等时跳
    TEST_BR bgeu, 0x80000000, 0x80000000, 1, 6
    TEST_BR bgeu, 0xffffffff, 0xfffffffe, 1, 7
    TEST_BR bgeu, 0, 1, 0, 8
    TEST_BR bgeu, 1, 0, 1, 9
    TEST_BR bgeu, 0x80000000, 0x80000001, 0, 10

    // 与 x0 比较：任何数 >= 0；0 >= 非 0 数不成立
    LI      x5, 0x80000000
    PAD_DATA
    bgeu    x5, x0, 1f
    PAD_JUMP
    TEST_FAIL 11
1:
    bgeu    x0, x5, .Lfail12
    PAD_JUMP

    // 向后跳：x5 从 0xc0000000 起每次加 0x10000000，bgeu x5, x6（x6 = 0xc0000000）：
    // 加完是 0xd0000000、0xe0000000、0xf0000000 时继续，回绕到 0 时停，循环 4 次
    LI      x5, 0xc0000000
    LI      x6, 0xc0000000
    LI      x7, 0x10000000
    LI      x11, 0
    PAD_DATA
.Lloop:
    add     x5, x5, x7
    addi    x11, x11, 1
    PAD_DATA
    bgeu    x5, x6, .Lloop
    PAD_JUMP
    CHECK   x11, 4, 13
    CHECK   x5, 0, 14
TEST_END

.Lfail12:
    TEST_FAIL 12
