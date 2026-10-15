// 冒险场景（第五节表）："运算后隔一条 store"  add x1,.. ; 无关 ; sw x1,..
//                      —— 转发后的 busB 存进 EX/M（课程数据通路图的缺口）
//
// sw 在 EX 段时，add 在 WB，BusBFw = 01；sw 到 M 段时 add 已离开流水线，
// M/WB 里是那条无关指令，DiSrc 匹配不上。只有把转发后的 busB 存进 EX/M，
// 写进存储器的才是新值。"无关"指令：ori x9, x0, 0x99。
//
// 失败码：
//   1  add x1 ; 无关 ; sw x1, 0(x4)            -> buf[0] = 12（表中这一行）
//   2  lui x5 ; 无关 ; sw x5, 4(x4)            -> buf[1] = 0xabcde000
//   3  sltu x6 ; 无关 ; sw x6, 8(x4)           -> buf[2] = 1
//   4  相邻：add x7 ; sw x7, 12(x4)            -> buf[3] = 14（EX/M 转发）
//   5  隔两条：add x8 ; 无关 ; 无关 ; sw x8, 16(x4) -> buf[4] = 10（寄存器堆旁路）
//   6  中间是一条 store：add x11 ; sw x0, 24(x4) ; sw x11, 20(x4) -> buf[5] = 12
//   7  上一组中间那条 store：buf[6] = 0
#include "test.h"

    .data
    .balign 4
buf:
    .word   0xeeeeeeee, 0xeeeeeeee, 0xeeeeeeee, 0xeeeeeeee
    .word   0xeeeeeeee, 0xeeeeeeee, 0xeeeeeeee

TEST_BEGIN
    LI      x1, 0x1111
    LI      x2, 5
    LI      x3, 7
    LI      x5, 0x5555
    LI      x6, 0x6666
    LI      x7, 0x7777
    LI      x8, 0x8484
    LI      x11, 0x1111
    LA      x4, buf
    // 计数器（nopad，MARK 1-2 之间）：没有 load，也没有跳转
    // PERF 1-2: stalls=0 flushes=0
    PERF_MARK 1

    add     x1, x2, x3
    ori     x9, x0, 0x99
    PAD_DATA
    sw      x1, 0(x4)
    SEP
    lui     x5, 0xabcde
    ori     x9, x0, 0x99
    PAD_DATA
    sw      x5, 4(x4)
    SEP
    sltu    x6, x2, x3
    ori     x9, x0, 0x99
    PAD_DATA
    sw      x6, 8(x4)
    SEP
    add     x7, x3, x3
    PAD_DATA
    sw      x7, 12(x4)
    SEP
    add     x8, x2, x2
    ori     x9, x0, 0x99
    ori     x10, x0, 0x10
    sw      x8, 16(x4)
    SEP
    add     x11, x2, x3
    sw      x0, 24(x4)
    PAD_DATA
    sw      x11, 20(x4)
    PERF_MARK 2

    lw      x12, 0(x4)
    lw      x13, 4(x4)
    lw      x14, 8(x4)
    lw      x15, 12(x4)
    lw      x16, 16(x4)
    lw      x17, 20(x4)
    lw      x18, 24(x4)
    CHECK   x12, 12, 1
    CHECK   x13, 0xabcde000, 2
    CHECK   x14, 1, 3
    CHECK   x15, 14, 4
    CHECK   x16, 10, 5
    CHECK   x17, 12, 6
    CHECK   x18, 0, 7
TEST_END
