// 冒险场景（第五节表）："同一寄存器连续写"  add x1,.. ; addi x1,.. ; 使用 x1  —— M 段优先
//
// M 段和 WB 段的指令写同一个寄存器时，必须用离得近的 M 段那条的值。
// base9 没有 addi，第二次写用 ori 或 lui。
//
// 失败码：
//   1  rs1：add x1 (12) ; ori x1 (0x77) ; add x4, x1, x0   -> 0x77
//   2  rs2：lui x5 ; ori x5 (3) ; add x6, x2, x5           -> 8
//   3  连写三次：ori x7 1 ; ori x7 2 ; ori x7 3 ; add x8, x7, x7 -> 6
//   4  WB 段是 load：lw x9 ; ori x9 (5) ; add x10, x9, x0  -> 5
//   5  M 段是 load（要停顿）：ori x11 (5) ; lw x11 ; add x12, x11, x0 -> 0xaaaa5555
//   6  store 数据：ori x13 1 ; ori x13 2 ; sw x13, 4(x17)  -> buf[1] = 2
//   7  分支操作数：ori x14 1 ; ori x14 2 ; beq x14, x15(=2) 应跳
#include "test.h"

    .data
    .balign 4
buf:
    .word   0xaaaa5555, 0xbbbbbbbb

TEST_BEGIN
    LI      x1, 0x11
    LI      x2, 5
    LI      x3, 7
    LI      x5, 0x55
    LI      x7, 0x77
    LI      x9, 0x99
    LI      x11, 0x111
    LI      x13, 0x13
    LI      x14, 0x14
    LI      x15, 2
    LA      x17, buf
    // 计数器（nopad，MARK 1-2 之间）：第 5 组 lw x11 ; add x12, x11 停 1 拍（第 4 组 ori 不读 x9）；第 7 组 beq 成立 1 次
    // PERF 1-2: stalls=1 flushes=1
    PERF_MARK 1

    add     x1, x2, x3
    ori     x1, x0, 0x77
    PAD_DATA
    add     x4, x1, x0
    SEP
    lui     x5, 0x12345
    ori     x5, x0, 3
    PAD_DATA
    add     x6, x2, x5
    SEP
    ori     x7, x0, 1
    ori     x7, x0, 2
    ori     x7, x0, 3
    PAD_DATA
    add     x8, x7, x7
    SEP
    lw      x9, 0(x17)
    ori     x9, x0, 5
    PAD_DATA
    add     x10, x9, x0
    SEP
    ori     x11, x0, 5
    lw      x11, 0(x17)
    PAD_DATA
    add     x12, x11, x0
    SEP
    ori     x13, x0, 1
    ori     x13, x0, 2
    PAD_DATA
    sw      x13, 4(x17)
    SEP
    ori     x14, x0, 1
    ori     x14, x0, 2
    PAD_DATA
    beq     x14, x15, 1f
    PAD_JUMP
    TEST_FAIL 7
1:
    PERF_MARK 2

    lw      x16, 4(x17)
    CHECK   x4, 0x77, 1
    CHECK   x6, 8, 2
    CHECK   x8, 6, 3
    CHECK   x10, 5, 4
    CHECK   x12, 0xaaaa5555, 5
    CHECK   x16, 2, 6
TEST_END
