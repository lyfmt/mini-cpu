// 冒险场景（第五节表）："隔两条依赖"  add x1,.. ; 无关 ; 无关 ; 使用 x1  —— 寄存器堆旁路
//
// 使用方在 ID 段读寄存器的同一周期，写方正在 WB 写回。
// "无关"指令：ori x24, x0, 0x24 ; ori x25, x0, 0x25。阶段 1 的 pad 变体
// 也恰好是这个距离（两条之间隔两条），所以两个变体都不需要额外填充。
//
// 失败码：
//   1  rs1：add x1 ; 无关 ; 无关 ; add x4, x1, x5       -> 112
//   2  rs2：ori x7 ; 无关 ; 无关 ; add x8, x5, x7       -> 0x169
//   3  两个源：slt x11 ; 无关 ; 无关 ; add x12, x11, x11 -> 2
//   4  结果为 0：sltu x13 ; 无关 ; 无关 ; add x14, x5, x13 -> 100（旧值 0x55）
//   5  store 数据：add x19 ; 无关 ; 无关 ; sw x19, 4(x17) -> buf[1] = 12
//   6  store 地址：add x18 ; 无关 ; 无关 ; sw x3, 0(x18)  -> buf[0] = 7
//   7  load 地址：add x20 ; 无关 ; 无关 ; lw x21, 8(x20)  -> 0x5eed5eed
//   8  分支操作数：add x26 ; 无关 ; 无关 ; beq x26, x27    应跳
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
    LI      x11, 0x111
    LI      x13, 0x55
    LI      x18, 0x18
    LI      x19, 0x19
    LI      x20, 0x20
    LI      x26, 0x26
    LI      x27, 12
    LA      x17, buf
    SEP

    add     x1, x2, x3
    ori     x24, x0, 0x24
    ori     x25, x0, 0x25
    add     x4, x1, x5
    SEP
    ori     x7, x2, 0x100
    ori     x24, x0, 0x24
    ori     x25, x0, 0x25
    add     x8, x5, x7
    SEP
    slt     x11, x2, x3
    ori     x24, x0, 0x24
    ori     x25, x0, 0x25
    add     x12, x11, x11
    SEP
    sltu    x13, x3, x2
    ori     x24, x0, 0x24
    ori     x25, x0, 0x25
    add     x14, x5, x13
    SEP
    add     x19, x2, x3
    ori     x24, x0, 0x24
    ori     x25, x0, 0x25
    sw      x19, 4(x17)
    SEP
    add     x18, x17, x0
    ori     x24, x0, 0x24
    ori     x25, x0, 0x25
    sw      x3, 0(x18)
    SEP
    add     x20, x17, x0
    ori     x24, x0, 0x24
    ori     x25, x0, 0x25
    lw      x21, 8(x20)
    SEP
    add     x26, x2, x3
    ori     x24, x0, 0x24
    ori     x25, x0, 0x25
    beq     x26, x27, 1f
    PAD_JUMP
    TEST_FAIL 8
1:
    SEP

    lw      x22, 0(x17)
    lw      x23, 4(x17)
    CHECK   x4, 112, 1
    CHECK   x8, 0x169, 2
    CHECK   x12, 2, 3
    CHECK   x14, 100, 4
    CHECK   x23, 12, 5
    CHECK   x22, 7, 6
    CHECK   x21, 0x5eed5eed, 7
TEST_END
