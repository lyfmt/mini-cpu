// 性能测试：rv32i 新增指令真正读 load 结果时的停顿（第五节 load-use）。
//
//   1-2    lw x5 ; sub x20, x9, x5          R 型的 rs2              停 1，冲刷 0
//   3-4    lw x5 ; sll x20, x9, x5          移位量来自 rs2          停 1，冲刷 0
//   5-6    lw x5 ; srai x20, x5, 3          I 型的 rs1              停 1，冲刷 0
//   7-8    lw x11 ; jalr x0, 0(x11)         jalr 依赖 load          停 1，冲刷 1
//   9-10   lw x5 ; bne x5, x0（成立）       分支依赖 load           停 1，冲刷 1
//   11-12  lw x5 ; bltu x9, x5（不成立）    分支的 rs2 依赖 load    停 1，冲刷 0
//   13-14  lw x11 ; jalr x11, 0(x11)        rd = rs1，依赖 load     停 1，冲刷 1
//
// 数据：d[0] = 5，d[1] = .L7（代码地址），d[2] = .L13
// 失败码：1..4  跳转、分支走错；5  sll 的结果
#include "test.h"

    .data
    .balign 4
d:
    .word   5, .L7, .L13

TEST_BEGIN
    LI      x9, 0x12345678, x7
    LA      x17, d

    // PERF 1-2: stalls=1 flushes=0
    PERF_MARK 1
    lw      x5, 0(x17)
    PAD_DATA
    sub     x20, x9, x5
    PERF_MARK 2

    // PERF 3-4: stalls=1 flushes=0
    PERF_MARK 3
    lw      x5, 0(x17)
    PAD_DATA
    sll     x20, x9, x5
    PERF_MARK 4
    CHECK   x20, 0x468acf00, 5

    // PERF 5-6: stalls=1 flushes=0
    PERF_MARK 5
    lw      x5, 0(x17)
    PAD_DATA
    srai    x20, x5, 3
    PERF_MARK 6

    // PERF 7-8: stalls=1 flushes=1
    PERF_MARK 7
    lw      x11, 4(x17)
    PAD_DATA
    jalr    x0, 0(x11)
    PAD_JUMP
    TEST_FAIL 1
.L7:
    PERF_MARK 8

    // PERF 9-10: stalls=1 flushes=1
    PERF_MARK 9
    lw      x5, 0(x17)
    PAD_DATA
    bne     x5, x0, .L9
    PAD_JUMP
    TEST_FAIL 2
.L9:
    PERF_MARK 10

    // PERF 11-12: stalls=1 flushes=0
    PERF_MARK 11
    lw      x5, 0(x17)
    PAD_DATA
    bltu    x9, x5, .Lbad3
    PAD_JUMP
    PERF_MARK 12

    // PERF 13-14: stalls=1 flushes=1
    PERF_MARK 13
    lw      x11, 8(x17)
    PAD_DATA
    jalr    x11, 0(x11)
.Lr13:
    PAD_JUMP
    TEST_FAIL 4
.L13:
    PERF_MARK 14
    CHECK   x11, .Lr13, 4
TEST_END

.Lbad3:
    TEST_FAIL 3
