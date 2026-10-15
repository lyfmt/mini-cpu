// 性能测试：rv32i 新增分支指令的冲刷次数（第五节"控制冒险"）。
//
// 分支不成立没有任何代价；成立时冲刷 3 条，FLUSHES 加 1。所有段都不停顿。
// x1 = -1、x2 = 1：有符号比较和无符号比较的结果相反。
//
//   1-2    bne   x1, x1   不成立   冲刷 0
//   3-4    bne   x1, x2   成立     冲刷 1
//   5-6    blt   x2, x1   不成立   冲刷 0
//   7-8    blt   x1, x2   成立     冲刷 1
//   9-10   bge   x1, x2   不成立   冲刷 0
//   11-12  bge   x2, x1   成立     冲刷 1
//   13-14  bltu  x1, x2   不成立   冲刷 0
//   15-16  bltu  x2, x1   成立     冲刷 1
//   17-18  bgeu  x2, x1   不成立   冲刷 0
//   19-20  bgeu  x1, x2   成立     冲刷 1
//   21-22  3 次的循环：addi x5, x5, -1 ; bne x5, x0 向后，成立 2 次   冲刷 2
//
// 失败码：1..5  对应的分支走错；6  循环次数
#include "test.h"

TEST_BEGIN
    LI      x1, -1
    LI      x2, 1
    LI      x5, 3
    LI      x6, 0

    // PERF 1-2: stalls=0 flushes=0
    PERF_MARK 1
    bne     x1, x1, .Lbad1
    PAD_JUMP
    PERF_MARK 2

    // PERF 3-4: stalls=0 flushes=1
    PERF_MARK 3
    bne     x1, x2, .L3
    PAD_JUMP
    TEST_FAIL 1
.L3:
    PERF_MARK 4

    // PERF 5-6: stalls=0 flushes=0
    PERF_MARK 5
    blt     x2, x1, .Lbad2
    PAD_JUMP
    PERF_MARK 6

    // PERF 7-8: stalls=0 flushes=1
    PERF_MARK 7
    blt     x1, x2, .L7
    PAD_JUMP
    TEST_FAIL 2
.L7:
    PERF_MARK 8

    // PERF 9-10: stalls=0 flushes=0
    PERF_MARK 9
    bge     x1, x2, .Lbad3
    PAD_JUMP
    PERF_MARK 10

    // PERF 11-12: stalls=0 flushes=1
    PERF_MARK 11
    bge     x2, x1, .L11
    PAD_JUMP
    TEST_FAIL 3
.L11:
    PERF_MARK 12

    // PERF 13-14: stalls=0 flushes=0
    PERF_MARK 13
    bltu    x1, x2, .Lbad4
    PAD_JUMP
    PERF_MARK 14

    // PERF 15-16: stalls=0 flushes=1
    PERF_MARK 15
    bltu    x2, x1, .L15
    PAD_JUMP
    TEST_FAIL 4
.L15:
    PERF_MARK 16

    // PERF 17-18: stalls=0 flushes=0
    PERF_MARK 17
    bgeu    x2, x1, .Lbad5
    PAD_JUMP
    PERF_MARK 18

    // PERF 19-20: stalls=0 flushes=1
    PERF_MARK 19
    bgeu    x1, x2, .L19
    PAD_JUMP
    TEST_FAIL 5
.L19:
    PERF_MARK 20

    // PERF 21-22: stalls=0 flushes=2
    PERF_MARK 21
.Lloop:
    addi    x5, x5, -1
    addi    x6, x6, 1
    PAD_DATA
    bne     x5, x0, .Lloop
    PAD_JUMP
    PERF_MARK 22
    CHECK   x6, 3, 6
TEST_END

.Lbad1:
    TEST_FAIL 1
.Lbad2:
    TEST_FAIL 2
.Lbad3:
    TEST_FAIL 3
.Lbad4:
    TEST_FAIL 4
.Lbad5:
    TEST_FAIL 5
