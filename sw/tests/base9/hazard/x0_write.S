// 冒险场景（第五节表）："写 x0 后读 x0"  addi x0,x1,5 ; add x2,x0,x0  —— 转发条件排除 x0
//
// x0 永远读出 0。前面的指令"写"了 x0，后面的指令在任何距离上都不能拿到那个值。
// base9 没有 addi，用 ori x0, x1, 5。
//
// 失败码：
//   1  ori x0, x1, 5 ; add x2, x0, x0             -> 0（EX/M 转发不能匹配 x0）
//   2  add x0, x1, x1 ; 无关 ; add x3, x0, x1     -> 0x10（WB 转发不能匹配 x0）
//   3  lui x0 ; add x4, x5, x0（rs2）             -> 9
//   4  lw x0 ; add x6, x0, x0（load 写 x0，紧跟使用）-> 0
//   5  ori x0, x1, 7 ; sw x0, 0(x17)              -> buf[0] = 0（store 数据）
//   6  lw x0 ; sw x0, 4(x17)                      -> buf[1] = 0（DiSrc 不能匹配 x0）
//   7  ori x0, x1, 7 ; beq x0, x8(=0)             应跳（分支操作数）
//   8  ori x0, x1, 7 ; 无关 ; 无关 ; add x7, x0, x0 -> 0（寄存器堆旁路不能匹配 x0）
//   9  最后 x0 仍为 0
#include "test.h"

    .data
    .balign 4
buf:
    .word   0xffffffff, 0xffffffff, 0x12345678

TEST_BEGIN
    LI      x1, 0x10
    LI      x2, 0x22
    LI      x3, 0x33
    LI      x4, 0x44
    LI      x5, 9
    LI      x6, 0x66
    LI      x7, 0x77
    LI      x8, 0
    LA      x17, buf
    // 计数器（nopad，MARK 1-2 之间）：目标为 x0 的 load 后面读 x0 不停；第 7 组 beq 成立 1 次
    // PERF 1-2: stalls=0 flushes=1
    PERF_MARK 1

    ori     x0, x1, 5
    PAD_DATA
    add     x2, x0, x0
    SEP
    add     x0, x1, x1
    ori     x24, x0, 0x24
    PAD_DATA
    add     x3, x0, x1
    SEP
    lui     x0, 0x12345
    PAD_DATA
    add     x4, x5, x0
    SEP
    lw      x0, 8(x17)
    PAD_DATA
    add     x6, x0, x0
    SEP
    ori     x0, x1, 7
    PAD_DATA
    sw      x0, 0(x17)
    SEP
    lw      x0, 8(x17)
    PAD_DATA
    sw      x0, 4(x17)
    SEP
    ori     x0, x1, 7
    PAD_DATA
    beq     x0, x8, 1f
    PAD_JUMP
    TEST_FAIL 7
1:
    SEP
    ori     x0, x1, 7
    ori     x24, x0, 0x24
    ori     x25, x0, 0x25
    add     x7, x0, x0
    PERF_MARK 2

    lw      x10, 0(x17)
    lw      x11, 4(x17)
    CHECK   x2, 0, 1
    CHECK   x3, 0x10, 2
    CHECK   x4, 9, 3
    CHECK   x6, 0, 4
    CHECK   x10, 0, 5
    CHECK   x11, 0, 6
    CHECK   x7, 0, 8
    CHECK   x0, 0, 9
TEST_END
