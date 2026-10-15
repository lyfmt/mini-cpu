// 性能测试：jalr 的冲刷（第五节"控制冒险"、"停顿和冲刷同时发生"、"连续跳转"）。
//
//   1-2    jalr x1, 0(x10)                          冲刷 1
//   3-4    jalr 到下一条（目标 = pc + 4）           照样冲刷：冲刷 1
//   5-6    addi x10, x10, 8 ; jalr x0, -8(x10)      依赖刚算出的值走转发，不停：停 0，冲刷 1
//   7-8    jalr ; lw x1 ; add x2, x1, x1            错误路径上的 load-use 与冲刷同一拍，
//                                                   冲刷优先：停 0，冲刷 1
//   9-10   jal x1, f ; f: jalr x0, 0(x1)            调用和返回：冲刷 2
//   11-12  jal -> jalr -> jalr                      连续跳转：冲刷 3
//   13-14  jalr x10, 0(x10)                         rd = rs1：冲刷 1
//
// 数据：d[0] = 0x0d0d0d0d
// 失败码：1  跳转走错；2  返回地址；3  错误路径上的指令生效了
#include "test.h"

    .data
    .balign 4
d:
    .word   0x0d0d0d0d

TEST_BEGIN
    LI      x1, 0x101
    LI      x2, 0x202
    LA      x17, d

    // PERF 1-2: stalls=0 flushes=1
    LA      x10, .L1
    PERF_MARK 1
    jalr    x1, 0(x10)
.Lr1:
    PAD_JUMP
    TEST_FAIL 1
.L1:
    PERF_MARK 2
    CHECK   x1, .Lr1, 2

    // PERF 3-4: stalls=0 flushes=1
    LA      x10, .L3
    PERF_MARK 3
    jalr    x0, 0(x10)
    PAD_JUMP
.L3:
    PERF_MARK 4

    // PERF 5-6: stalls=0 flushes=1
    LA      x10, .L5
    PERF_MARK 5
    addi    x10, x10, 8
    PAD_DATA
    jalr    x0, -8(x10)
    PAD_JUMP
    TEST_FAIL 1
.L5:
    PERF_MARK 6

    // PERF 7-8: stalls=0 flushes=1
    LI      x1, 0x101
    LA      x10, .L7
    PERF_MARK 7
    jalr    x0, 0(x10)
    PAD_JUMP
    lw      x1, 0(x17)
    add     x2, x1, x1
.L7:
    PERF_MARK 8
    CHECK   x1, 0x101, 3
    CHECK   x2, 0x202, 3

    // PERF 9-10: stalls=0 flushes=2
    PERF_MARK 9
    jal     x1, f
.Lr9:
    PAD_JUMP
    PERF_MARK 10
    CHECK   x1, .Lr9, 2

    // PERF 11-12: stalls=0 flushes=3
    LA      x10, .L11b
    LA      x11, .L11c
    PERF_MARK 11
    jal     x0, .L11a
    PAD_JUMP
    TEST_FAIL 1
.L11a:
    jalr    x0, 0(x10)
    PAD_JUMP
    TEST_FAIL 1
.L11b:
    jalr    x0, 0(x11)
    PAD_JUMP
    TEST_FAIL 1
.L11c:
    PERF_MARK 12

    // PERF 13-14: stalls=0 flushes=1
    LA      x10, .L13
    PERF_MARK 13
    jalr    x10, 0(x10)
.Lr13:
    PAD_JUMP
    TEST_FAIL 1
.L13:
    PERF_MARK 14
    CHECK   x10, .Lr13, 2
TEST_END

f:
    PAD_DATA
    jalr    x0, 0(x1)
    PAD_JUMP
