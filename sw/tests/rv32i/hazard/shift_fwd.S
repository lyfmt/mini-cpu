// 冒险场景：移位量来自转发（第五节表"相邻依赖""隔一条依赖""load 后紧跟使用"
// 里，消费者是寄存器移位、依赖在移位量 rs2 上；以及被移位的数和移位量分别
// 来自不同的转发源）。
//
// 移位量寄存器事先装上 0（旧值），转发缺失时结果是没移位的数。
// nopad 变体里每组紧挨着，前后用 SEP 隔开：
//   1  addi x1, x0, 4 ; sll x2, x3, x1              距离 1
//   2  addi x1, x0, 8 ; ori x9 ; srl x2, x4, x1     距离 2
//   3  lw x1 ; sra x2, x4, x1                       load-use：停顿后从 WB 转发
//   4  addi x1, x0, 33 ; sll x2, x3, x1             转发来的移位量也只取低 5 位
//   5  lui x5, 0x80000 ; addi x1, x0, 31 ; sra x2, x5, x1
//                                                  被移位的数来自 WB、移位量来自 EX/M
//   6  addi x6, x0, 3 ; slli x2, x6, 3              立即数移位，被移位的数转发
//   7  lw x7 ; srai x2, x7, 4                       立即数移位，被移位的数来自 load
//
// 数据：d = { 12, 0x80000000 }
//
// 失败码：
//   1  x2 = 0x00000123 << 4 = 0x00001230
//   2  x2 = 0x87654321 >> 8 = 0x00876543
//   3  x2 = 0x87654321 >>a 12 = 0xfff87654
//   4  x2 = 0x00000123 << 1 = 0x00000246
//   5  x2 = 0x80000000 >>a 31 = 0xffffffff
//   6  x2 = 3 << 3 = 24
//   7  x2 = 0x80000000 >>a 4 = 0xf8000000
#include "test.h"

    .data
    .balign 4
d:
    .word   12, 0x80000000

TEST_BEGIN
    LA      x17, d
    LI      x3, 0x123
    LI      x4, 0x87654321
    LI      x1, 0
    LI      x5, 0x12
    LI      x6, 0x5
    LI      x7, 0x100
    SEP

    // 1
    addi    x1, x0, 4
    PAD_DATA
    sll     x2, x3, x1
    SEP
    CHECK   x2, 0x00001230, 1
    LI      x1, 0
    SEP

    // 2
    addi    x1, x0, 8
    ori     x9, x0, 9
    PAD_DATA
    srl     x2, x4, x1
    SEP
    CHECK   x2, 0x00876543, 2
    LI      x1, 0
    SEP

    // 3
    lw      x1, 0(x17)
    PAD_DATA
    sra     x2, x4, x1
    SEP
    CHECK   x2, 0xfff87654, 3
    LI      x1, 0
    SEP

    // 4
    addi    x1, x0, 33
    PAD_DATA
    sll     x2, x3, x1
    SEP
    CHECK   x2, 0x00000246, 4
    LI      x1, 0
    SEP

    // 5
    lui     x5, 0x80000
    addi    x1, x0, 31
    PAD_DATA
    sra     x2, x5, x1
    SEP
    CHECK   x2, 0xffffffff, 5
    SEP

    // 6
    addi    x6, x0, 3
    PAD_DATA
    slli    x2, x6, 3
    SEP
    CHECK   x2, 24, 6
    SEP

    // 7
    lw      x7, 4(x17)
    PAD_DATA
    srai    x2, x7, 4
    SEP
    CHECK   x2, 0xf8000000, 7
TEST_END
