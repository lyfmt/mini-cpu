// 性能测试：分支和跳转的冲刷次数（第五节"控制冒险：跳转与冲刷"），以及分支依赖 load
// 的停顿。FLUSHES 数的是跳转成立的次数，每次成立冲刷 3 条。
//
//   1-2    beq 不成立                     停 0，冲刷 0
//   3-4    beq 成立（向前）               停 0，冲刷 1
//   5-6    lw x1 ; beq x1, x2（不成立）   停 1，冲刷 0
//   7-8    lw x1 ; beq x3, x1（成立，依赖在 rs2）
//                                         停 1，冲刷 1
//   9-10   lw x1 ; 无关 ; beq x1, x3（成立）
//                                         隔一条：停 0，冲刷 1
//   11-12  jal x1, L                      停 0，冲刷 1
//   13-14  jal x0 到下一条                目标就是 pc+4，照样冲刷：停 0，冲刷 1
//   15-16  jal -> jal -> beq 成立         连续跳转各冲刷一次：停 0，冲刷 3
//   17-18  3 次的循环，向后 beq 成立 2 次 停 0，冲刷 2
//
// 数据：d[0] = 0x5
// 失败码：1..4  不该成立的分支成立了；5  jal 的返回地址；6  循环次数
#include "test.h"

    .data
    .balign 4
d:
    .word   0x5

TEST_BEGIN
    LI      x2, 7
    LI      x3, 5
    LI      x5, 0
    LI      x6, 1
    LI      x7, 3
    LA      x17, d

    // PERF 1-2: stalls=0 flushes=0
    PERF_MARK 1
    beq     x2, x3, .Lbad1
    PAD_JUMP
    PERF_MARK 2

    // PERF 3-4: stalls=0 flushes=1
    PERF_MARK 3
    beq     x3, x3, .L3
    PAD_JUMP
    TEST_FAIL 2
.L3:
    PERF_MARK 4

    // PERF 5-6: stalls=1 flushes=0
    PERF_MARK 5
    lw      x1, 0(x17)
    PAD_DATA
    beq     x1, x2, .Lbad3
    PAD_JUMP
    PERF_MARK 6

    // PERF 7-8: stalls=1 flushes=1
    PERF_MARK 7
    lw      x1, 0(x17)
    PAD_DATA
    beq     x3, x1, .L7
    PAD_JUMP
    TEST_FAIL 4
.L7:
    PERF_MARK 8

    // PERF 9-10: stalls=0 flushes=1
    PERF_MARK 9
    lw      x1, 0(x17)
    add     x4, x2, x2
    PAD_DATA
    beq     x1, x3, .L9
    PAD_JUMP
    TEST_FAIL 4
.L9:
    PERF_MARK 10

    // PERF 11-12: stalls=0 flushes=1
    PERF_MARK 11
    jal     x1, .L11
.Lr11:
    PAD_JUMP
    TEST_FAIL 5
.L11:
    PERF_MARK 12
    CHECK   x1, .Lr11, 5

    // PERF 13-14: stalls=0 flushes=1
    PERF_MARK 13
    jal     x0, .L13
    PAD_JUMP
.L13:
    PERF_MARK 14

    // PERF 15-16: stalls=0 flushes=3
    PERF_MARK 15
    jal     x0, .L15a
    PAD_JUMP
    TEST_FAIL 2
.L15a:
    jal     x0, .L15b
    PAD_JUMP
    TEST_FAIL 2
.L15b:
    beq     x0, x0, .L15c
    PAD_JUMP
    TEST_FAIL 2
.L15c:
    PERF_MARK 16

    // PERF 17-18: stalls=0 flushes=2
    PERF_MARK 17
.Lloop:
    add     x5, x5, x6
    PAD_DATA
    slt     x8, x5, x7
    PAD_DATA
    beq     x8, x6, .Lloop
    PAD_JUMP
    PERF_MARK 18
    CHECK   x5, 3, 6
TEST_END

.Lbad1:
    TEST_FAIL 1
.Lbad3:
    TEST_FAIL 3
