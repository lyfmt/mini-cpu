// 冒险场景（第五节表）："跳转成立"  beq 成立、jal、jalr  —— 冲刷 3 条
// 错误路径上的 3 条指令都换成 qmul：它们必须被冲刷成气泡，不写回寄存器，
// 也不能被转发给跳转目标处的指令。
//
// nopad 变体里每个跳转后面紧跟 3 条 qmul（用 SEP 和前后代码隔开）：
//   1  beq x0, x0, L1 ; qmul x1 ; qmul x2 ; qmul x3
//      L1: add x20, x1, x2           目标处立刻读错误路径要写的 x1、x2
//   2  jal x4, L2 ; qmul x4 ; qmul x7 ; qmul x8
//      L2: add x21, x4, x0           错误路径上的 qmul 要写的正是 jal 的 rd
//   3  jalr x0, 0(x18) ; qmul x10 ; qmul x11 ; qmul x12
//      L3: add x22, x10, x11
// x5 = 1234、x6 = 2345，qmul 的结果都是 829；各目的寄存器事先装上别的值。
//
// 失败码：
//   1  x20 = 0x111 + 0x222 = 0x333（目标处读到的是 x1、x2 的旧值）
//   2  x1、x2、x3 不变
//   3  x21 = x4 = jal 的返回地址
//   4  x7、x8 不变
//   5  x22 = 0x1010 + 0x1111 = 0x2121
//   6  x10、x11、x12 不变
#include "test.h"
#include "qmul.h"

TEST_BEGIN
    LI      x5, 1234
    LI      x6, 2345, x15
    LI      x1, 0x111
    LI      x2, 0x222
    LI      x3, 0x333
    LI      x7, 0x777
    LI      x8, 0x888, x15
    LI      x10, 0x1010
    LI      x11, 0x1111
    LI      x12, 0x1212
    LA      x18, .L3
    SEP

    beq     x0, x0, .L1
    PAD_JUMP
    qmul    x1, x5, x6
    qmul    x2, x5, x6
    qmul    x3, x5, x6
.L1:
    add     x20, x1, x2
    SEP

    jal     x4, .L2
.Lr2:
    PAD_JUMP
    qmul    x4, x5, x6
    qmul    x7, x5, x6
    qmul    x8, x5, x6
.L2:
    PAD_DATA                        // pad 变体：jal 刚写了 x4，PAD_JUMP 被跳过了
    add     x21, x4, x0
    SEP

    jalr    x0, 0(x18)
    PAD_JUMP
    qmul    x10, x5, x6
    qmul    x11, x5, x6
    qmul    x12, x5, x6
.L3:
    add     x22, x10, x11
    SEP

    CHECK   x20, 0x333, 1
    CHECK   x1, 0x111, 2
    CHECK   x2, 0x222, 2
    CHECK   x3, 0x333, 2
    CHECK   x21, .Lr2, 3
    CHECK   x4, .Lr2, 3
    CHECK   x7, 0x777, 4
    CHECK   x8, 0x888, 4
    CHECK   x22, 0x2121, 5
    CHECK   x10, 0x1010, 6
    CHECK   x11, 0x1111, 6
    CHECK   x12, 0x1212, 6
TEST_END
