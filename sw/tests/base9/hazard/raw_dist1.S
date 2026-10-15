// 冒险场景（第五节表）："相邻依赖"  add x1,.. ; sub x2,x1,..  —— EX/M 转发（10）
//
// base9 没有 sub，用 add/slt/sltu/ori/lw/sw 作为使用方。
// nopad 变体：每组的两条（或三条）指令紧挨着，组前后用 SEP（三条空指令）
// 与准备、检查代码隔开，所以冒险恰好只发生在组内。pad 变体在组内插 PAD_DATA。
// 被写的寄存器事先放了不同的旧值，转发缺失时一定得到错误结果。
//
// 失败码：
//   1  rs1 依赖：add x1 ; add x4, x1, x5          -> 112
//   2  rs2 依赖：ori x7 ; add x8, x5, x7          -> 0x169
//   3  lui 的结果：lui x9 ; slt x10, x9, x0       -> 1
//   4  两个源都依赖：slt x11 ; add x12, x11, x11  -> 2
//   5  结果为 0 也要转发：sltu x13 ; add x14, x5, x13 -> 100（旧值 0x55）
//   6  三条连续依赖：x15 = ((5 + 7) * 2) * 2      -> 48
//   7  store 地址依赖：add x18 ; sw x3, 0(x18)    -> buf[0] = 7
//   8  store 数据依赖：add x19 ; sw x19, 4(x17)   -> buf[1] = 12
//   9  load 地址依赖：add x20 ; lw x21, 8(x20)    -> 0x5eed5eed
#include "test.h"

    .data
    .balign 4
buf:
    .word   0xbbbbbbbb, 0xbbbbbbbb, 0x5eed5eed

TEST_BEGIN
    LI      x1, 0x11
    LI      x2, 5
    LI      x3, 7
    LI      x5, 100
    LI      x7, 0x77
    LI      x9, 0x99
    LI      x11, 0x111
    LI      x13, 0x55
    LI      x15, 0x15
    LI      x18, 0x18
    LI      x19, 0x19
    LI      x20, 0x20
    LA      x17, buf
    SEP

    add     x1, x2, x3
    PAD_DATA
    add     x4, x1, x5
    SEP
    ori     x7, x2, 0x100
    PAD_DATA
    add     x8, x5, x7
    SEP
    lui     x9, 0x80000
    PAD_DATA
    slt     x10, x9, x0
    SEP
    slt     x11, x2, x3
    PAD_DATA
    add     x12, x11, x11
    SEP
    sltu    x13, x3, x2
    PAD_DATA
    add     x14, x5, x13
    SEP
    add     x15, x2, x3
    PAD_DATA
    add     x15, x15, x15
    PAD_DATA
    add     x15, x15, x15
    SEP
    add     x18, x17, x0
    PAD_DATA
    sw      x3, 0(x18)
    SEP
    add     x19, x2, x3
    PAD_DATA
    sw      x19, 4(x17)
    SEP
    add     x20, x17, x0
    PAD_DATA
    lw      x21, 8(x20)
    SEP

    lw      x22, 0(x17)
    lw      x23, 4(x17)
    CHECK   x4, 112, 1
    CHECK   x8, 0x169, 2
    CHECK   x10, 1, 3
    CHECK   x12, 2, 4
    CHECK   x14, 100, 5
    CHECK   x15, 48, 6
    CHECK   x22, 7, 7
    CHECK   x23, 12, 8
    CHECK   x21, 0x5eed5eed, 9
TEST_END
