// 冒险场景（第五节表）："分支依赖刚算出的值"、"分支依赖 load"，
// 用 rv32i 的五种新分支，比较单元使用转发之后的操作数。
//
// 每组都安排成：用新值比较的结果与用旧值比较的结果相反，所以转发缺失、
// 转发错了级或 load-use 没停顿时一定走错方向。"应跳"的组后面紧跟 TEST_FAIL，
// "不应跳"的组跳到 .LbadN。nopad 变体里每组紧挨着，前后用 SEP 隔开：
//   1  addi x1, x0, 5 ; bne x1, x2(=5), .Lbad1          距离 1：新值 5 不跳（旧值 7 会跳）
//   2  addi x2, x0, -1 ; ori x9 ; blt x2, x0, L         距离 2：-1 < 0 跳（旧值 1 不跳）
//   3  lw x3(=0x80000000) ; bge x3, x0, .Lbad3          load-use：不跳（旧值 5 会跳）
//   4  lui x4, 0x80000 ; addi x5, x0, 1 ; bltu x5, x4, L
//                                                      两个操作数分别来自 WB 和 EX/M：跳
//                                                      （旧值 x4 = 0 或 x5 = -1 都不跳）
//   5  addi x6, x0, -1 ; ori x9 ; ori x9 ; bgeu x6, x7(=0x80000000), L
//                                                      距离 3（寄存器堆旁路）：跳（旧值 0 不跳）
//   6  lw x8(=3) ; ori x9 ; bne x8, x10(=3), .Lbad6    load 隔一条（WB 转发）：不跳（旧值 0 会跳）
//   7  addi x11, x0, -5 ; addi x11, x0, 5 ; blt x11, x0, .Lbad7
//                                                      同一寄存器连续写，M 段优先：不跳
//   8  lw x12(=0xffffffff) ; bgeu x13(=1), x12, .Lbad8  rs2 依赖 load：不跳（旧值 0 会跳）
//   9  addi x14, x0, 0x7ff ; blt x15(=0x800), x14, .Lbad9
//                                                      rs2 依赖 ALU：0x800 < 0x7ff 不成立
//                                                      （旧值 0x900 会跳）
//
// 失败码：1..9 对应各组走错了方向
#include "test.h"

    .data
    .balign 4
d:
    .word   0x80000000, 3, 0xffffffff

TEST_BEGIN
    LA      x17, d
    LI      x1, 7
    LI      x2, 1
    PAD_DATA
    SEP

    // 1：不应跳（x2 此时是 1，先改成 5）
    LI      x2, 5
    SEP
    addi    x1, x0, 5
    PAD_DATA
    bne     x1, x2, .Lbad1
    PAD_JUMP
    SEP

    // 2：应跳
    LI      x2, 1
    SEP
    addi    x2, x0, -1
    ori     x9, x0, 9
    PAD_DATA
    blt     x2, x0, .Lok2
    PAD_JUMP
    TEST_FAIL 2
.Lok2:
    SEP

    // 3：不应跳
    LI      x3, 5
    SEP
    lw      x3, 0(x17)
    PAD_DATA
    bge     x3, x0, .Lbad3
    PAD_JUMP
    SEP

    // 4：应跳
    LI      x4, 0
    LI      x5, 0xffffffff
    SEP
    lui     x4, 0x80000
    addi    x5, x0, 1
    PAD_DATA
    bltu    x5, x4, .Lok4
    PAD_JUMP
    TEST_FAIL 4
.Lok4:
    SEP

    // 5：应跳
    LI      x6, 0
    LI      x7, 0x80000000
    SEP
    addi    x6, x0, -1
    ori     x9, x0, 9
    ori     x9, x0, 10
    bgeu    x6, x7, .Lok5
    PAD_JUMP
    TEST_FAIL 5
.Lok5:
    SEP

    // 6：不应跳
    LI      x8, 0
    LI      x10, 3
    SEP
    lw      x8, 4(x17)
    ori     x9, x0, 9
    PAD_DATA
    bne     x8, x10, .Lbad6
    PAD_JUMP
    SEP

    // 7：不应跳
    LI      x11, 0
    SEP
    addi    x11, x0, -5
    addi    x11, x0, 5
    PAD_DATA
    blt     x11, x0, .Lbad7
    PAD_JUMP
    SEP

    // 8：不应跳
    LI      x12, 0
    LI      x13, 1
    SEP
    lw      x12, 8(x17)
    PAD_DATA
    bgeu    x13, x12, .Lbad8
    PAD_JUMP
    SEP

    // 9：不应跳
    LI      x14, 0x900, x16
    LI      x15, 0x800, x16
    SEP
    addi    x14, x0, 0x7ff
    PAD_DATA
    blt     x15, x14, .Lbad9
    PAD_JUMP
    SEP
TEST_END

.Lbad1:
    TEST_FAIL 1
.Lbad3:
    TEST_FAIL 3
.Lbad6:
    TEST_FAIL 6
.Lbad7:
    TEST_FAIL 7
.Lbad8:
    TEST_FAIL 8
.Lbad9:
    TEST_FAIL 9
