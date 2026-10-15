// 冒险场景（第五节表）："跳转后紧跟 store"  jal L ; sw ..  —— sw 被冲刷，不写存储器
//
// 跳转在 M 段确认时，紧跟的 sw 还在 EX，尚未写存储器，冲刷掉即可。
// 能进入 M 段的指令一定在正确路径上。
//
// 数据：buf 初值 0xc0c0c0c0 ×5
//
// 失败码：
//   1  jal x0 ; sw x5, 0(x17)           -> buf[0] 不变（表中这一行）
//   2  beq 成立 ; sw x5, 4(x17)         -> buf[1] 不变
//   3  jal x6 ; sw x6, 8(x17)           -> buf[2] 不变（要存的正是刚算出的返回地址）
//   4  jal x0 ; ori ; sw x5, 12(x17)    -> buf[3] 不变（store 在错误路径第 2 条）
//   5  jal x0 ; ori ; ori ; sw x5, 16(x17) -> buf[4] 不变（store 在错误路径第 3 条）
//   6  对照：不成立的 beq ; sw x5, 16(x17) -> buf[4] = 0x5555，确实写了
//   7  jal x6 的返回地址
#include "test.h"

    .data
    .balign 4
buf:
    .word   0xc0c0c0c0, 0xc0c0c0c0, 0xc0c0c0c0, 0xc0c0c0c0, 0xc0c0c0c0

TEST_BEGIN
    LI      x5, 0x5555
    LI      x21, 1
    LA      x17, buf
    SEP

    jal     x0, 1f
    PAD_JUMP
    sw      x5, 0(x17)
1:
    SEP
    beq     x0, x0, 1f
    PAD_JUMP
    sw      x5, 4(x17)
1:
    SEP
    jal     x6, 1f
.Lr3:
    PAD_JUMP
    sw      x6, 8(x17)
1:
    SEP
    jal     x0, 1f
    PAD_JUMP
    ori     x7, x0, 7
    sw      x5, 12(x17)
1:
    SEP
    jal     x0, 1f
    PAD_JUMP
    ori     x7, x0, 7
    ori     x8, x0, 8
    sw      x5, 16(x17)
1:
    SEP

    lw      x10, 0(x17)
    lw      x11, 4(x17)
    lw      x12, 8(x17)
    lw      x13, 12(x17)
    lw      x14, 16(x17)
    CHECK   x10, 0xc0c0c0c0, 1
    CHECK   x11, 0xc0c0c0c0, 2
    CHECK   x12, 0xc0c0c0c0, 3
    CHECK   x13, 0xc0c0c0c0, 4
    CHECK   x14, 0xc0c0c0c0, 5
    CHECK   x6, .Lr3, 7

    beq     x0, x21, .Lbad6
    PAD_JUMP
    sw      x5, 16(x17)
    SEP
    lw      x15, 16(x17)
    CHECK   x15, 0x5555, 6
TEST_END

.Lbad6:
    TEST_FAIL 6
