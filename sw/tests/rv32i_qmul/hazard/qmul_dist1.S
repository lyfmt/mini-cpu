// 冒险场景（第五节表）："相邻依赖"  `add x1,..` ; `sub x2,x1,..`  —— EX/M 转发（10）
// 这里生产者或消费者换成 qmul：qmul 的结果和 ALU 结果走同一条运算结果通路，
// 应当同样从 EX/M 转发。
//
// nopad 变体里每组的两条指令紧挨着（用 SEP 和前后代码隔开）：
//   1  qmul x1, x5, x6 ; add  x2, x1, x0      qmul -> rs1
//   2  qmul x3, x5, x6 ; sub  x4, x0, x3      qmul -> rs2
//   3  qmul x7, x5, x6 ; qmul x8, x7, x7      qmul -> qmul 两个操作数
//   4  add  x9, x5, x6 ; qmul x10, x9, x5     ALU -> qmul rs1
//   5  add  x11, x5, x6; qmul x12, x5, x11    ALU -> qmul rs2
//   6  qmul x13, x5, x6; beq  x13, x14, 目标  qmul -> 分支比较，必须跳
//
// 期望值（q = 3329，x5 = 1234，x6 = 2345）：
//   1234·2345 mod q = 829；829² = 687241 = 206·3329 + 1467
//   1234 + 2345 = 3579；3579·1234 = 4416486 = 1326·3329 + 2232
//
// 失败码：
//   1  x2 = 829
//   2  x4 = −829 = 0xfffffcc3
//   3  x8 = 1467
//   4  x10 = 2232
//   5  x12 = 2232
//   6  beq 没有跳（比较用了旧值）
#include "test.h"
#include "qmul.h"

TEST_BEGIN
    LI      x5, 1234
    LI      x6, 2345, x15
    LI      x14, 829
    LI      x1, 0x111
    LI      x2, 0x222
    LI      x3, 0x333
    LI      x4, 0x444
    LI      x7, 0x777
    LI      x8, 0x888, x15
    LI      x9, 0x999, x15
    LI      x10, 0x10
    LI      x11, 0x11
    LI      x12, 0x12
    LI      x13, 0x13
    SEP

    qmul    x1, x5, x6
    PAD_DATA
    add     x2, x1, x0
    SEP

    qmul    x3, x5, x6
    PAD_DATA
    sub     x4, x0, x3
    SEP

    qmul    x7, x5, x6
    PAD_DATA
    qmul    x8, x7, x7
    SEP

    add     x9, x5, x6
    PAD_DATA
    qmul    x10, x9, x5
    SEP

    add     x11, x5, x6
    PAD_DATA
    qmul    x12, x5, x11
    SEP

    qmul    x13, x5, x6
    PAD_DATA
    beq     x13, x14, .Lok6
    PAD_JUMP
    TEST_FAIL 6
.Lok6:
    SEP

    CHECK   x2, 829, 1
    CHECK   x4, 0xfffffcc3, 2
    CHECK   x8, 1467, 3
    CHECK   x10, 2232, 4
    CHECK   x12, 2232, 5
TEST_END
