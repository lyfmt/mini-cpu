// 冒险场景（第五节表）："跳转成立"  beq 成立、jal（jalr 在 rv32i 阶段）  —— 冲刷 3 条
//
// 跳转在 M 段确认时，后面三条已在 IF、ID、EX。nopad 变体里这三条紧跟在跳转
// 后面，是错误路径上的指令：写寄存器、写存储器、跳转、读存储器，都必须被冲刷掉。
// pad 变体里它们排在三条空指令之后，跳转直接越过它们。
//
// 失败码：
//   1  beq 成立后错误路径 1：ori x1 不应执行（x1 仍为 0）
//   2  beq 成立后错误路径 2：sw 不应执行（buf[0] 仍为 0xb0b0b0b0）
//   3  beq 成立后错误路径 3：jal 不应跳（走到 .Lbad3）
//   4  jal 的返回地址
//   5  jal 成立后错误路径 1：ori x2 不应执行
//   6  jal 成立后错误路径 2：beq 不应跳（走到 .Lbad6）
//   7  jal 成立后错误路径 3：add x3 不应执行
//   8  跳到紧跟的下一条：目标指令被冲刷后重新取指，恰好执行一次，x20 = 1
//   9  不成立的 beq 不冲刷：后面三条 ori 都执行（x6、x7、x8 都被写）
#include "test.h"

    .data
    .balign 4
buf:
    .word   0xb0b0b0b0

TEST_BEGIN
    LI      x1, 0
    LI      x2, 0
    LI      x3, 0
    LI      x5, 0x5555
    LI      x6, 0
    LI      x7, 0
    LI      x8, 0
    LI      x20, 0
    LI      x21, 1
    LA      x17, buf
    // 计数器（nopad，MARK 1-2 之间）：beq、jal、跳到下一条的 beq 各 1 次，最后的 beq 不成立
    // PERF 1-2: stalls=0 flushes=3
    PERF_MARK 1

    // beq 成立
    beq     x0, x0, .La
    PAD_JUMP
    ori     x1, x0, 0x11
    sw      x5, 0(x17)
    jal     x0, .Lbad3
.La:
    SEP

    // jal
    jal     x4, .Lb
.Lrb:
    PAD_JUMP
    ori     x2, x0, 0x22
    beq     x0, x0, .Lbad6
    add     x3, x5, x5
.Lb:
    SEP

    // 跳到紧跟的下一条
    beq     x0, x0, 1f
    PAD_JUMP
1:
    add     x20, x20, x21
    SEP

    // 不成立的 beq
    beq     x0, x21, .Lbad9
    PAD_JUMP
    ori     x6, x0, 0x700
    ori     x7, x0, 0x0f0
    ori     x8, x0, 0x00f
    PERF_MARK 2

    lw      x10, 0(x17)
    CHECK   x1, 0, 1
    CHECK   x10, 0xb0b0b0b0, 2
    CHECK   x4, .Lrb, 4
    CHECK   x2, 0, 5
    CHECK   x3, 0, 7
    CHECK   x20, 1, 8
    CHECK   x6, 0x700, 9
    CHECK   x7, 0x0f0, 9
    CHECK   x8, 0x00f, 9
TEST_END

.Lbad3:
    TEST_FAIL 3
.Lbad6:
    TEST_FAIL 6
.Lbad9:
    TEST_FAIL 9
