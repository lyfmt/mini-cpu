// 冒险场景（第五节表）："load 后隔一条使用"  lw x1,.. ; 无关 ; add x2,x1,..  —— WB 转发，不停顿
//
// "无关"指令：ori x24, x0, 0x24。
// 数据：d[0] = 0xfffffff0 (-16)，d[1] = 0x21，d[2] = 0x40000000，
//       d[3] = &target，target = { 0x600df00d, 0 }
//
// 失败码：
//   1  rs1：lw x1 ; 无关 ; add x2, x1, x3       -> 0xfffffff3
//   2  rs2：lw x4 ; 无关 ; add x5, x3, x4       -> 0x24
//   3  两个源：lw x6 ; 无关 ; add x7, x6, x6    -> 0x80000000
//   4  load 地址：lw x12 ; 无关 ; lw x13, 0(x12) -> 0x600df00d
//   5  store 数据：lw x8 ; 无关 ; sw x8, 0(x18)  -> out[0] = 0x21
//   6  store 地址：lw x9 ; 无关 ; sw x3, 4(x9)   -> target[1] = 3
//   7  分支操作数：lw x10 ; 无关 ; beq x10, x11(= -16) 应跳
#include "test.h"

    .data
    .balign 4
d:
    .word   0xfffffff0, 0x21, 0x40000000, target
target:
    .word   0x600df00d, 0
out:
    .word   0xeeeeeeee

TEST_BEGIN
    LI      x1, 0x11
    LI      x3, 3
    LI      x4, 0x44
    LI      x6, 0x66
    LI      x8, 0x88
    LI      x9, 0x99
    LI      x10, 0x10
    LI      x11, -16
    LI      x12, 0x12
    LA      x17, d
    LA      x18, out
    // 计数器（nopad，MARK 1-2 之间）：load 都隔一条才用，不停；第 7 组 beq 成立 1 次
    // PERF 1-2: stalls=0 flushes=1
    PERF_MARK 1

    lw      x1, 0(x17)
    ori     x24, x0, 0x24
    PAD_DATA
    add     x2, x1, x3
    SEP
    lw      x4, 4(x17)
    ori     x24, x0, 0x24
    PAD_DATA
    add     x5, x3, x4
    SEP
    lw      x6, 8(x17)
    ori     x24, x0, 0x24
    PAD_DATA
    add     x7, x6, x6
    SEP
    lw      x12, 12(x17)
    ori     x24, x0, 0x24
    PAD_DATA
    lw      x13, 0(x12)
    SEP
    lw      x8, 4(x17)
    ori     x24, x0, 0x24
    PAD_DATA
    sw      x8, 0(x18)
    SEP
    lw      x9, 12(x17)
    ori     x24, x0, 0x24
    PAD_DATA
    sw      x3, 4(x9)
    SEP
    lw      x10, 0(x17)
    ori     x24, x0, 0x24
    PAD_DATA
    beq     x10, x11, 1f
    PAD_JUMP
    TEST_FAIL 7
1:
    PERF_MARK 2

    lw      x14, 0(x18)
    lw      x15, 4(x9)
    CHECK   x2, 0xfffffff3, 1
    CHECK   x5, 0x24, 2
    CHECK   x7, 0x80000000, 3
    CHECK   x13, 0x600df00d, 4
    CHECK   x14, 0x21, 5
    CHECK   x15, 3, 6
TEST_END
