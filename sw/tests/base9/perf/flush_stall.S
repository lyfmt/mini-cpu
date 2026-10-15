// 性能测试：冲刷和停顿同一拍（第五节"停顿和冲刷同时发生"）。
//
// 跳转 i 在 M 段时，i+1 在 EX、i+2 在 ID。i+1 是 load、i+2 读它的结果时，
// 同一拍既要冲刷又检测到 load-use：冲刷优先，这次停顿不发生，也不计入 STALLS；
// 冲刷照常计入 FLUSHES。
//
//   1-2    beq 成立 ; lw x1 ; add x2, x1, x1    （后两条在错误路径上）  停 0，冲刷 1
//   3-4    jal ; lw x1 ; add x2, x1, x1                                 停 0，冲刷 1
//   5-6    beq 成立 ; lw x1 ; sw x3, 0(x1)      （store 地址依赖）     停 0，冲刷 1
//   7-8    beq 成立 ; lw x1 ; beq x1, x1        （分支依赖）           停 0，冲刷 1
//   9-10   beq 成立 ; 无关 ; lw x1 ; add x2, x1, x1
//                                    load-use 在 i+2、i+3，跳转在 M 段时
//                                    EX 段不是 load，也就没有停顿          停 0，冲刷 1
//   11-12  beq 不成立 ; lw x1 ; add x2, x1, x1   不成立就没有冲刷，
//                                    正确路径上的 load-use 照常停顿        停 1，冲刷 0
//
// 数据：d[0] = 0x0d0d0d0d，d[1] = &d[2]
// 失败码：1  错误路径上的指令生效了（x1、x2）；2  第 11-12 段的 x2
#include "test.h"

    .data
    .balign 4
d:
    .word   0x0d0d0d0d, d + 8, 0

TEST_BEGIN
    LI      x1, 0x101
    LI      x2, 0x202
    LI      x3, 0x303
    LI      x4, 1
    LA      x17, d

    // PERF 1-2: stalls=0 flushes=1
    PERF_MARK 1
    beq     x0, x0, .L1
    PAD_JUMP
    lw      x1, 0(x17)
    add     x2, x1, x1
.L1:
    PERF_MARK 2

    // PERF 3-4: stalls=0 flushes=1
    PERF_MARK 3
    jal     x0, .L3
    PAD_JUMP
    lw      x1, 0(x17)
    add     x2, x1, x1
.L3:
    PERF_MARK 4

    // PERF 5-6: stalls=0 flushes=1
    PERF_MARK 5
    beq     x0, x0, .L5
    PAD_JUMP
    lw      x1, 4(x17)
    sw      x3, 0(x1)
.L5:
    PERF_MARK 6

    // PERF 7-8: stalls=0 flushes=1
    PERF_MARK 7
    beq     x0, x0, .L7
    PAD_JUMP
    lw      x1, 0(x17)
    beq     x1, x1, .L7
.L7:
    PERF_MARK 8

    // PERF 9-10: stalls=0 flushes=1
    PERF_MARK 9
    beq     x0, x0, .L9
    PAD_JUMP
    add     x2, x0, x0
    lw      x1, 0(x17)
    add     x2, x1, x1
.L9:
    PERF_MARK 10

    CHECK   x1, 0x101, 1
    CHECK   x2, 0x202, 1

    // PERF 11-12: stalls=1 flushes=0
    PERF_MARK 11
    beq     x0, x4, .Lbad
    PAD_JUMP
    lw      x1, 0(x17)
    PAD_DATA
    add     x2, x1, x1
    PERF_MARK 12
    CHECK   x2, 0x1a1a1a1a, 2
TEST_END

.Lbad:
    TEST_FAIL 2
