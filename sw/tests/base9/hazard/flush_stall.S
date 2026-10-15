// 冒险场景（第五节表）："冲刷和停顿同时出现"  跳转在 M 段，错误路径上的 load-use 在 ID/EX
//                      —— 冲刷优先
//
// 跳转指令 i 在 M 段时，i+1 在 EX、i+2 在 ID。nopad 变体里让 i+1 是 lw、
// i+2 用它的结果：同一周期既要冲刷又检测到 load-use。冲刷必须优先，
// PC 换成跳转目标，错误路径上的指令一条也不生效。
// 跳转目标处的 add x20, x20, x21 用来确认目标恰好执行一次。
//
// 数据：d[0] = 0x0d0d0d0d
//
// 失败码：
//   1  beq 成立 ; lw x1 ; add x2, x1, x1 ; ori x3   -> x1 不变
//   2                                               -> x2 不变
//   3                                               -> x3 不变
//   4  jal ; lw x5 ; add x6, x5, x0 ; ori x7        -> x5、x6、x7 不变
//   5  jal 的返回地址
//   6  目标处本身是一对 load-use：beq ; lw x10 ; add x11 ; ori x12 ;
//      目标：lw x8 ; add x9, x8, x8                 -> x9 = 0x1a1a1a1a
//   7  上一组错误路径上的 x10、x11、x12 不变
//   8  不成立的 beq 在 M 段时，正确路径上的 load-use 照常停顿：
//      beq（不成立）; lw x13 ; add x14, x13, x13    -> x14 = 0x1a1a1a1a
//   9  每个跳转目标恰好执行一次：x20 = 3
#include "test.h"

    .data
    .balign 4
d:
    .word   0x0d0d0d0d

TEST_BEGIN
    LI      x1, 0x101
    LI      x2, 0x202
    LI      x3, 0x303
    LI      x5, 0x505
    LI      x6, 0x606
    LI      x7, 0x707
    LI      x10, 0x110
    LI      x11, 0x111
    LI      x12, 0x112
    LI      x13, 0x113
    LI      x20, 0
    LI      x21, 1
    LA      x17, d
    // 计数器（nopad，MARK 1-2 之间）：三次跳转成立；错误路径上的 load-use 与冲刷同一拍，不计；目标处和不成立分支后面的 load-use 各停 1 拍
    // PERF 1-2: stalls=2 flushes=3
    PERF_MARK 1

    beq     x0, x0, .L1
    PAD_JUMP
    lw      x1, 0(x17)
    add     x2, x1, x1
    ori     x3, x0, 3
.L1:
    add     x20, x20, x21
    SEP

    jal     x4, .L2
.Lr2:
    PAD_JUMP
    lw      x5, 0(x17)
    add     x6, x5, x0
    ori     x7, x0, 7
.L2:
    add     x20, x20, x21
    SEP

    beq     x0, x0, .L3
    PAD_JUMP
    lw      x10, 0(x17)
    add     x11, x10, x10
    ori     x12, x0, 12
.L3:
    lw      x8, 0(x17)
    PAD_DATA
    add     x9, x8, x8
    add     x20, x20, x21
    SEP

    beq     x0, x21, .Lbad8
    PAD_JUMP
    lw      x13, 0(x17)
    PAD_DATA
    add     x14, x13, x13
    PERF_MARK 2

    CHECK   x1, 0x101, 1
    CHECK   x2, 0x202, 2
    CHECK   x3, 0x303, 3
    CHECK   x5, 0x505, 4
    CHECK   x6, 0x606, 4
    CHECK   x7, 0x707, 4
    CHECK   x4, .Lr2, 5
    CHECK   x9, 0x1a1a1a1a, 6
    CHECK   x10, 0x110, 7
    CHECK   x11, 0x111, 7
    CHECK   x12, 0x112, 7
    CHECK   x14, 0x1a1a1a1a, 8
    CHECK   x20, 3, 9
TEST_END

.Lbad8:
    TEST_FAIL 8
