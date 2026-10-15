// 冒险场景：jalr 依赖刚算出的值  addi x1,.. ; jalr x0,0(x1)  —— 转发进目标加法器
// （第五节表"分支依赖刚算出的值"对 jalr 的推广：jalr 的基地址取转发之后的 rs1）
//
// 被写的寄存器事先装上"坏目标"的地址，转发缺失时 jalr 用旧值跳到 .LbadN。
//
// nopad 变体里每组紧挨着，前后用 SEP 隔开：
//   1  addi x1, x2, 16 ; jalr x0, 0(x1)             距离 1：EX/M 转发
//   2  addi x3, x4, 0 ; ori x9 ; jalr x0, 0(x3)      距离 2：WB 转发
//   3  add x5, x6, x0 ; ori x9 ; ori x9 ; jalr x0, 0(x5)   距离 3：寄存器堆旁路
//   4  auipc x7 ; jalr x8, %pcrel_lo(x7)            auipc 结果转发给 jalr
//   5  add x10, x12, x0 ; add x10, x11, x0 ; jalr x0, -8(x10)   同一寄存器连续写，M 段优先
//
// 第 4 组 x7 的旧值是 .Lbad4 减去 jalr 的偏移（%pcrel_lo，即 .Lt4 - .La4），
// 第 5 组 WB 段那条写的是 .Lbad5 + 8：用错了值都会落到 .LbadN。
//
// 失败码：
//   1..5  跳到了旧值指向的 .LbadN（或没有跳，落到紧跟的 TEST_FAIL）
//   6     第 4 组的返回地址 x8
#include "test.h"

TEST_BEGIN
    LA      x1, .Lbad1
    LA      x2, .Lt1 - 16
    LA      x3, .Lbad2
    LA      x4, .Lt2
    LA      x5, .Lbad3
    LA      x6, .Lt3
    LA      x7, .Lbad4 - (.Lt4 - .La4)
    LA      x10, .Lbad5 + 8
    LA      x11, .Lt5 + 8
    LA      x12, .Lbad5 + 8
    LI      x8, 0
    SEP

    addi    x1, x2, 16
    PAD_DATA
    jalr    x0, 0(x1)
    PAD_JUMP
    TEST_FAIL 1
.Lt1:
    SEP

    addi    x3, x4, 0
    ori     x9, x0, 9
    PAD_DATA
    jalr    x0, 0(x3)
    PAD_JUMP
    TEST_FAIL 2
.Lt2:
    SEP

    add     x5, x6, x0
    ori     x9, x0, 9
    ori     x9, x0, 10
    jalr    x0, 0(x5)
    PAD_JUMP
    TEST_FAIL 3
.Lt3:
    SEP

.La4:
    auipc   x7, %pcrel_hi(.Lt4)
    PAD_DATA
.Lj4:
    jalr    x8, %pcrel_lo(.La4)(x7)
    PAD_JUMP
    TEST_FAIL 4
.Lt4:
    SEP

    // jalr 在 EX 时，WB 段那条写 .Lbad5 + 8，M 段那条写 .Lt5 + 8，必须用 M 段的
    add     x10, x12, x0
    add     x10, x11, x0
    PAD_DATA
    jalr    x0, -8(x10)
    PAD_JUMP
    TEST_FAIL 5
.Lt5:
    SEP

    CHECK   x8, .Lj4 + 4, 6
TEST_END

.Lbad1:
    TEST_FAIL 1
.Lbad2:
    TEST_FAIL 2
.Lbad3:
    TEST_FAIL 3
.Lbad4:
    TEST_FAIL 4
.Lbad5:
    TEST_FAIL 5
