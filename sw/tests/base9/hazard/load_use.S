// 冒险场景（第五节表）："load 后紧跟使用"  lw x1,.. ; add x2,x1,..  —— 停顿一拍，再从 WB 转发
//
// 每组后面紧跟一条 add x22, x22, x23（x23 = 1）作计数：停顿时它停在 IF，
// 必须恰好执行一次。九组之后 x22 应为 9。
//
// 数据：d[0] = 0xfffffff0 (-16)，d[1] = 0x21，d[2] = 0x40000000，
//       d[3] = &target，target = 0x600df00d
//
// 失败码：
//   1  rs1：lw x1 ; add x2, x1, x3           -> -16 + 3 = 0xfffffff3
//   2  rs2：lw x4 ; add x5, x3, x4           -> 0x24
//   3  两个源：lw x6 ; add x7, x6, x6        -> 0x80000000
//   4  I 型：lw x8 ; ori x9, x8, 0x700       -> 0x721
//   5  有符号比较：lw x10 ; slt x11, x10, x3 -> 1
//   6  load 地址依赖 load：lw x12 ; lw x13, 0(x12) -> 0x600df00d
//   7  连续两次 load-use：lw x14 ; lw x15, 0(x14) ; add x16, x15, x15 -> 0xc01be01a
//   8  sltu 的 rs2：lw x18 ; sltu x19, x3, x18 -> 1
//   9  lw x1 ; lui x20, 0x8：lui 的 rs1 字段碰巧是 1，但 lui 不读寄存器 -> 0x8000
//  10  上一组 load 的值：x1 = 0x21
//  11  计数：每组之后的那条指令恰好执行一次，x22 = 9
#include "test.h"

    .data
    .balign 4
d:
    .word   0xfffffff0, 0x21, 0x40000000, target
target:
    .word   0x600df00d

TEST_BEGIN
    LI      x1, 0x11
    LI      x3, 3
    LI      x4, 0x44
    LI      x6, 0x66
    LI      x8, 0x88
    LI      x10, 0x10
    LI      x12, 0x12
    LI      x14, 0x14
    LI      x15, 0x15
    LI      x18, 0x18
    LI      x22, 0
    LI      x23, 1
    LA      x17, d
    // 计数器（nopad，MARK 1-2 之间）：第 1～8 组各停 1 拍，第 7 组是连续两次再多 1 拍；第 9 组 lui 不读寄存器
    // PERF 1-2: stalls=9 flushes=0
    PERF_MARK 1

    lw      x1, 0(x17)
    PAD_DATA
    add     x2, x1, x3
    add     x22, x22, x23
    SEP
    lw      x4, 4(x17)
    PAD_DATA
    add     x5, x3, x4
    add     x22, x22, x23
    SEP
    lw      x6, 8(x17)
    PAD_DATA
    add     x7, x6, x6
    add     x22, x22, x23
    SEP
    lw      x8, 4(x17)
    PAD_DATA
    ori     x9, x8, 0x700
    add     x22, x22, x23
    SEP
    lw      x10, 0(x17)
    PAD_DATA
    slt     x11, x10, x3
    add     x22, x22, x23
    SEP
    lw      x12, 12(x17)
    PAD_DATA
    lw      x13, 0(x12)
    add     x22, x22, x23
    SEP
    lw      x14, 12(x17)
    PAD_DATA
    lw      x15, 0(x14)
    PAD_DATA
    add     x16, x15, x15
    add     x22, x22, x23
    SEP
    lw      x18, 4(x17)
    PAD_DATA
    sltu    x19, x3, x18
    add     x22, x22, x23
    SEP
    lw      x1, 4(x17)
    lui     x20, 0x8            // 编码里 inst[19:15] = 1
    add     x22, x22, x23
    PERF_MARK 2

    CHECK   x2, 0xfffffff3, 1
    CHECK   x5, 0x24, 2
    CHECK   x7, 0x80000000, 3
    CHECK   x9, 0x721, 4
    CHECK   x11, 1, 5
    CHECK   x13, 0x600df00d, 6
    CHECK   x16, 0xc01be01a, 7
    CHECK   x19, 1, 8
    CHECK   x20, 0x8000, 9
    CHECK   x1, 0x21, 10
    CHECK   x22, 9, 11
TEST_END
