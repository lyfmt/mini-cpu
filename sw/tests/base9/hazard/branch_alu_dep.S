// 冒险场景（第五节表）："分支依赖刚算出的值"  add x1,.. ; beq x1,x2,L  —— EX 段比较使用转发后的值
//
// 每组分支都安排成：用新值比较的结果与用旧值比较的结果相反，
// 所以转发缺失时一定走错方向。
//
// 失败码：
//   1  rs1：add x1 (12) ; beq x1, x4(=12)            应跳（旧值 0x11）
//   2  rs2：add x5 (12) ; beq x6(=12), x5            应跳（旧值 0x55）
//   3  不应跳：ori x7 (1) ; beq x7, x8(=9)           旧值 x7 = 9 时会跳
//   4  隔一条：add x9 (12) ; 无关 ; beq x9, x4       应跳（WB 转发）
//   5  slt x10 (1) ; beq x10, x11(=1)                应跳
//   6  两个源分别来自 WB 和 EX/M：add x12 ; add x13 ; beq x12, x13 应跳
//   7  lui x14 ; beq x14, x15(=0x80000000)           应跳
#include "test.h"

TEST_BEGIN
    LI      x1, 0x11
    LI      x2, 5
    LI      x3, 7
    LI      x4, 12
    LI      x5, 0x55
    LI      x6, 12
    LI      x7, 9
    LI      x8, 9
    LI      x9, 0x99
    LI      x10, 0x10
    LI      x11, 1
    LI      x12, 1
    LI      x13, 2
    LI      x14, 0x14
    LI      x15, 0x80000000
    SEP

    add     x1, x2, x3
    PAD_DATA
    beq     x1, x4, 1f
    PAD_JUMP
    TEST_FAIL 1
1:
    SEP
    add     x5, x2, x3
    PAD_DATA
    beq     x6, x5, 1f
    PAD_JUMP
    TEST_FAIL 2
1:
    SEP
    ori     x7, x0, 1
    PAD_DATA
    beq     x7, x8, .Lfail3
    PAD_JUMP
    SEP
    add     x9, x2, x3
    ori     x24, x0, 0x24
    PAD_DATA
    beq     x9, x4, 1f
    PAD_JUMP
    TEST_FAIL 4
1:
    SEP
    slt     x10, x2, x3
    PAD_DATA
    beq     x10, x11, 1f
    PAD_JUMP
    TEST_FAIL 5
1:
    SEP
    add     x12, x2, x3
    add     x13, x3, x2
    PAD_DATA
    beq     x12, x13, 1f
    PAD_JUMP
    TEST_FAIL 6
1:
    SEP
    lui     x14, 0x80000
    PAD_DATA
    beq     x14, x15, 1f
    PAD_JUMP
    TEST_FAIL 7
1:
    SEP
TEST_END

.Lfail3:
    TEST_FAIL 3
