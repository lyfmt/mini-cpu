// ModelSim 演示"基础流水线"：9 条基础指令，靠空指令隔开依赖，没有转发、没有停顿。
//
// 演示段（MARK 1 与 MARK 2 之间）的 9 条指令只读准备阶段装好的寄存器，彼此独立，
// 只有 beq 读 lw 的结果，中间隔两条空指令（距离 3，经寄存器堆同周期旁路）。
// 波形里看：五个阶段同时各有一条有效指令，WB 段每拍退休一条；beq 不跳，不冲刷；
// 最后的 jal 跳到紧跟的下一条，冲刷一次。
//
// 失败码：
//   1  lui  x10 = 0x12345000
//   2  ori  x11 = x1 | 0x0f0 = 0x0ff
//   3  add  x12 = x1 + x2 = 0x10f
//   4  slt  x13 = (-1 < 0x0f 有符号) = 1
//   5  sltu x14 = (0xffffffff < 0x0f 无符号) = 0
//   6  sw   dst[0] = x2 = 0x100
//   7  lw   x15 = dst[1] = 0x2468ace0
//   8  jal  x16 = 返回地址 .Lpipe_link
//   9  beq 错误地跳转
#include "test.h"

    .data
    .balign 4
dst:
    .word   0xdddddddd, 0x2468ace0

TEST_BEGIN
    LI      x1, 0x0f
    LI      x2, 0x100
    LI      x3, 0xffffffff
    LA      x4, dst
    LI      x10, 0x5a5
    LI      x11, 0x5a5
    LI      x12, 0x5a5
    LI      x13, 0x5a5
    LI      x14, 0x5a5
    LI      x15, 0x5a5
    LI      x16, 0x5a5
    // PERF 1-2: stalls=0 flushes=1
    PERF_MARK 1

    lui     x10, 0x12345
    ori     x11, x1, 0x0f0
    add     x12, x1, x2
    slt     x13, x3, x1
    sltu    x14, x3, x1
    sw      x2, 0(x4)
    lw      x15, 4(x4)
    NOP0
    NOP0
    beq     x15, x0, .Lpipe_bad
    PAD_JUMP
    jal     x16, .Lpipe_ret
.Lpipe_link:
    PAD_JUMP
.Lpipe_ret:
    PERF_MARK 2

    lw      x20, 0(x4)
    CHECK   x10, 0x12345000, 1
    CHECK   x11, 0x0ff, 2
    CHECK   x12, 0x10f, 3
    CHECK   x13, 1, 4
    CHECK   x14, 0, 5
    CHECK   x20, 0x100, 6
    CHECK   x15, 0x2468ace0, 7
    CHECK   x16, .Lpipe_link, 8
    jal     x0, .Lpipe_done
    PAD_JUMP
.Lpipe_bad:
    TEST_FAIL 9
.Lpipe_done:
TEST_END
