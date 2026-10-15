// 性能测试：load-use 停顿的次数（第五节"load-use：转发也解决不了的情况"）。
//
// 每段场景用一对 MARK 括起来，// PERF 行是这段里硬件 STALLS、FLUSHES 计数器的
// 增量（只在 nopad 变体检查，计数规则见 README）。没有跳转，FLUSHES 都是 0。
//
//   1-2    lw x1 ; add x2, x1, x3         紧跟使用 rs1：停 1 拍
//   3-4    lw x4 ; add x5, x3, x4         紧跟使用 rs2：停 1 拍
//   5-6    lw x6 ; add x7, x6, x6         两个源都用：仍只停 1 拍
//   7-8    lw x8 ; 无关 ; add x10, x8, x3 隔一条使用：WB 转发，不停
//   9-10   lw x0 ; add x11, x0, x0        load 的目标是 x0：读 x0 的指令不停
//   11-12  lw x12 ; lw x13, 0(x12)        load 的地址依赖 load：停 1 拍
//   13-14  lw x14 ; lw x15, 0(x14) ; add x16, x15, x15
//                                         连续两次 load-use：停 2 拍
//   15-16  lw x18 ; slt x19, x3, x18      比较指令的 rs2：停 1 拍
//
// 数据：d[0] = 0xfffffff0，d[1] = 0x21，d[2] = 0x40000000，d[3] = &target
// 失败码：1  上面各段算出的值（x16 = 0xc01be01a）
#include "test.h"

    .data
    .balign 4
d:
    .word   0xfffffff0, 0x21, 0x40000000, target
target:
    .word   0x600df00d

TEST_BEGIN
    LI      x3, 3
    LA      x17, d

    // PERF 1-2: stalls=1 flushes=0
    PERF_MARK 1
    lw      x1, 0(x17)
    PAD_DATA
    add     x2, x1, x3
    PERF_MARK 2

    // PERF 3-4: stalls=1 flushes=0
    PERF_MARK 3
    lw      x4, 4(x17)
    PAD_DATA
    add     x5, x3, x4
    PERF_MARK 4

    // PERF 5-6: stalls=1 flushes=0
    PERF_MARK 5
    lw      x6, 8(x17)
    PAD_DATA
    add     x7, x6, x6
    PERF_MARK 6

    // PERF 7-8: stalls=0 flushes=0
    PERF_MARK 7
    lw      x8, 4(x17)
    add     x9, x3, x3
    PAD_DATA
    add     x10, x8, x3
    PERF_MARK 8

    // PERF 9-10: stalls=0 flushes=0
    PERF_MARK 9
    lw      x0, 4(x17)
    add     x11, x0, x0
    PERF_MARK 10

    // PERF 11-12: stalls=1 flushes=0
    PERF_MARK 11
    lw      x12, 12(x17)
    PAD_DATA
    lw      x13, 0(x12)
    PERF_MARK 12

    // PERF 13-14: stalls=2 flushes=0
    PERF_MARK 13
    lw      x14, 12(x17)
    PAD_DATA
    lw      x15, 0(x14)
    PAD_DATA
    add     x16, x15, x15
    PERF_MARK 14

    // PERF 15-16: stalls=1 flushes=0
    PERF_MARK 15
    lw      x18, 4(x17)
    PAD_DATA
    slt     x19, x3, x18
    PERF_MARK 16

    CHECK   x16, 0xc01be01a, 1
TEST_END
