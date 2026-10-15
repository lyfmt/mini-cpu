// 冒险场景：lui、auipc 的结果被转发（第五节表"相邻依赖""隔一条依赖"
// "运算后隔一条 store""分支依赖刚算出的值"里，生产者换成 lui / auipc）。
//
// lui、auipc 不读寄存器，结果同样经 ALU 进 EX/M，必须照常转发。
// 被写的寄存器事先装上别的值。nopad 变体里每组紧挨着，前后用 SEP 隔开：
//   1  lui x1 ; add x2, x1, x3                      距离 1
//   2  lui x1 ; ori x9 ; or x2, x1, x3              距离 2
//   3  lui x1 ; sw x1, 0(x17)                       store 数据，距离 1
//   4  lui x1 ; ori x9 ; sw x1, 4(x17)              store 数据，距离 2
//   5  lui x1 ; bne x1, x4, .Lbad5                  分支
//   6  auipc x1 ; addi x2, x1, 0                    距离 1
//   7  auipc x1 ; ori x9 ; sub x2, x1, x5           距离 2
//   8  auipc x1, %pcrel_hi(buf) ; lw x2, %pcrel_lo(x1)   load 的地址来自 auipc
//   9  auipc x1, %pcrel_hi(buf) ; sw x3, %pcrel_lo(x1)   store 的地址来自 auipc
//  10  lui x1, 0x11111 ; lui x1, 0x22222 ; add x2, x1, x0   连续写，M 段优先
//  11  lui x0 ; add x2, x0, x0                      写 x0 后读 x0
//
// 数据：buf = { 0, 0, 0x600df00d, 0 }
//
// 失败码：
//   1  x2 = 0xabcde000 + 0x123 = 0xabcde123
//   2  x2 = 0x80000000 | 0x123 = 0x80000123
//   3  buf[0] = 0x12345000
//   4  buf[1] = 0xfedcb000
//   5  走到了 .Lbad5（x1 = 0x13579000 = x4，不应跳）
//   6  x2 = .La6
//   7  x2 = .La7 + 0x1000 - 0x10 （auipc x1, 1；x5 = 0x10）
//   8  x2 = 0x600df00d
//   9  buf[3] = 0x123
//  10  x2 = 0x22222000
//  11  x2 = 0
#include "test.h"

    .data
    .balign 4
buf:
    .word   0, 0, 0x600df00d, 0

TEST_BEGIN
    LA      x17, buf
    LI      x1, 0x77
    LI      x2, 0x77
    LI      x3, 0x123
    LI      x4, 0x13579000
    LI      x5, 0x10
    // 计数器（nopad，MARK 1-2 之间）：第 5 组 bne 不成立；中间 6 个 CHECK 各停 1 拍、成立 1 次
    // PERF 1-2: stalls=6 flushes=6
    PERF_MARK 1

    // 1
    lui     x1, 0xabcde
    PAD_DATA
    add     x2, x1, x3
    SEP
    CHECK   x2, 0xabcde123, 1
    LI      x1, 0x77
    SEP

    // 2
    lui     x1, 0x80000
    ori     x9, x0, 9
    PAD_DATA
    or      x2, x1, x3
    SEP
    CHECK   x2, 0x80000123, 2
    LI      x1, 0x77
    SEP

    // 3
    lui     x1, 0x12345
    PAD_DATA
    sw      x1, 0(x17)
    SEP
    LI      x1, 0x77
    SEP

    // 4
    lui     x1, 0xfedcb
    ori     x9, x0, 9
    PAD_DATA
    sw      x1, 4(x17)
    SEP
    LI      x1, 0x77
    SEP

    // 5
    lui     x1, 0x13579
    PAD_DATA
    bne     x1, x4, .Lbad5
    PAD_JUMP
    SEP

    // 6
.La6:
    auipc   x1, 0
    PAD_DATA
    addi    x2, x1, 0
    SEP
    CHECK   x2, .La6, 6
    SEP

    // 7
.La7:
    auipc   x1, 1
    ori     x9, x0, 9
    PAD_DATA
    sub     x2, x1, x5
    SEP
    CHECK   x2, .La7 + 0x1000 - 0x10, 7
    SEP

    // 8
.La8:
    auipc   x1, %pcrel_hi(buf + 8)
    PAD_DATA
    lw      x2, %pcrel_lo(.La8)(x1)
    SEP
    CHECK   x2, 0x600df00d, 8
    SEP

    // 9
.La9:
    auipc   x1, %pcrel_hi(buf + 12)
    PAD_DATA
    sw      x3, %pcrel_lo(.La9)(x1)
    SEP

    // 10
    lui     x1, 0x11111
    lui     x1, 0x22222
    PAD_DATA
    add     x2, x1, x0
    SEP
    CHECK   x2, 0x22222000, 10
    SEP

    // 11
    lui     x0, 0x54321
    PAD_DATA
    add     x2, x0, x0
    PERF_MARK 2
    CHECK   x2, 0, 11

    lw      x10, 0(x17)
    lw      x11, 4(x17)
    lw      x12, 12(x17)
    PAD_DATA
    CHECK   x10, 0x12345000, 3
    CHECK   x11, 0xfedcb000, 4
    CHECK   x12, 0x123, 9
TEST_END

.Lbad5:
    TEST_FAIL 5
