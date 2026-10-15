// 冒险场景（第五节表）："隔一条依赖"  add x1,.. ; 无关 ; or x2,x1,..  —— WB 转发（01）
//
// "无关"指令写的是别的寄存器：ori x24, x0, 0x24。
// 每组前后用 SEP 隔开（见 raw_dist1.S 的说明）。
//
// 失败码：
//   1  rs1 依赖：add x1 ; 无关 ; add x4, x1, x5        -> 112
//   2  rs2 依赖：ori x7 ; 无关 ; add x8, x5, x7        -> 0x169
//   3  lui 的结果：lui x9 ; 无关 ; slt x10, x9, x0     -> 1
//   4  两个源都依赖：slt x11 ; 无关 ; add x12, x11, x11 -> 2
//   5  结果为 0：sltu x13 ; 无关 ; add x14, x5, x13     -> 100（旧值 0x55）
//   6  store 地址依赖：add x18 ; 无关 ; sw x3, 0(x18)  -> buf[0] = 7
//   7  load 地址依赖：add x20 ; 无关 ; lw x21, 8(x20)  -> 0x5eed5eed
//   8  A 端来自 WB、B 端来自 EX/M：add x25 ; add x26 ; add x27, x25, x26 -> 12 + 200
//   9  A 端来自 EX/M、B 端来自 WB：add x6 ; add x16 ; add x19, x16, x6  -> 14 + 10
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
    LI      x6, 0x66
    LI      x7, 0x77
    LI      x9, 0x99
    LI      x11, 0x111
    LI      x13, 0x55
    LI      x16, 0x16
    LI      x18, 0x18
    LI      x20, 0x20
    LI      x25, 0x25
    LI      x26, 0x26
    LA      x17, buf
    // 计数器（nopad，MARK 1-2 之间）：没有 load-use，也没有跳转
    // PERF 1-2: stalls=0 flushes=0
    PERF_MARK 1

    add     x1, x2, x3
    ori     x24, x0, 0x24
    PAD_DATA
    add     x4, x1, x5
    SEP
    ori     x7, x2, 0x100
    ori     x24, x0, 0x24
    PAD_DATA
    add     x8, x5, x7
    SEP
    lui     x9, 0x80000
    ori     x24, x0, 0x24
    PAD_DATA
    slt     x10, x9, x0
    SEP
    slt     x11, x2, x3
    ori     x24, x0, 0x24
    PAD_DATA
    add     x12, x11, x11
    SEP
    sltu    x13, x3, x2
    ori     x24, x0, 0x24
    PAD_DATA
    add     x14, x5, x13
    SEP
    add     x18, x17, x0
    ori     x24, x0, 0x24
    PAD_DATA
    sw      x3, 0(x18)
    SEP
    add     x20, x17, x0
    ori     x24, x0, 0x24
    PAD_DATA
    lw      x21, 8(x20)
    SEP
    add     x25, x2, x3
    add     x26, x5, x5
    PAD_DATA
    add     x27, x25, x26
    SEP
    add     x6, x2, x2
    add     x16, x3, x3
    PAD_DATA
    add     x19, x16, x6
    PERF_MARK 2

    lw      x22, 0(x17)
    CHECK   x4, 112, 1
    CHECK   x8, 0x169, 2
    CHECK   x10, 1, 3
    CHECK   x12, 2, 4
    CHECK   x14, 100, 5
    CHECK   x22, 7, 6
    CHECK   x21, 0x5eed5eed, 7
    CHECK   x27, 212, 8
    CHECK   x19, 24, 9
TEST_END
