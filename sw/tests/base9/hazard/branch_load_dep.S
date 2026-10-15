// 冒险场景（第五节表）："分支依赖 load"  lw x1,.. ; beq x1,x2,L  —— 停顿一拍
//
// 数据：d = { 0x1234, 0xfffffffe, 7 }
//
// 失败码：
//   1  rs1：lw x1 ; beq x1, x2(=0x1234)           应跳（旧值 0x11）
//   2  rs2：lw x3 ; beq x4(=0xfffffffe), x3       应跳（旧值 0x33）
//   3  不应跳：lw x5 (7) ; beq x5, x6(=42)        旧值 x5 = 42 时会跳
//   4  不应跳：lw x11 (0x1234) ; beq x11, x0      旧值 x11 = 0 时会跳
//   5  隔一条（不停顿，WB 转发）：lw x9 ; 无关 ; beq x9, x10(=7) 应跳
//   6  跳转目标处的指令恰好执行一次：x20 = 2
#include "test.h"

    .data
    .balign 4
d:
    .word   0x1234, 0xfffffffe, 7

TEST_BEGIN
    LI      x1, 0x11
    LI      x2, 0x1234
    LI      x3, 0x33
    LI      x4, 0xfffffffe
    LI      x5, 42
    LI      x6, 42
    LI      x9, 0x99
    LI      x10, 7
    LI      x11, 0
    LI      x20, 0
    LI      x21, 1
    LA      x17, d
    SEP

    lw      x1, 0(x17)
    PAD_DATA
    beq     x1, x2, 1f
    PAD_JUMP
    TEST_FAIL 1
1:
    add     x20, x20, x21
    SEP
    lw      x3, 4(x17)
    PAD_DATA
    beq     x4, x3, 1f
    PAD_JUMP
    TEST_FAIL 2
1:
    add     x20, x20, x21
    SEP
    lw      x5, 8(x17)
    PAD_DATA
    beq     x5, x6, .Lfail3
    PAD_JUMP
    SEP
    lw      x11, 0(x17)
    PAD_DATA
    beq     x11, x0, .Lfail4
    PAD_JUMP
    SEP
    lw      x9, 8(x17)
    ori     x24, x0, 0x24
    PAD_DATA
    beq     x9, x10, 1f
    PAD_JUMP
    TEST_FAIL 5
1:
    SEP

    CHECK   x20, 2, 6
TEST_END

.Lfail3:
    TEST_FAIL 3
.Lfail4:
    TEST_FAIL 4
