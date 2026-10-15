// 冒险场景（第五节表）："load 后紧跟使用"  `lw x1,..` ; `add x2,x1,..`
//                      —— 停顿一拍，再从 WB 转发
// 这里消费者换成 qmul。另加一组"load 后隔一条使用"（WB 转发，不停顿）作对照。
//
// nopad 变体里每组的指令紧挨着（用 SEP 和前后代码隔开）：
//   1  lw x1, 0(x17) ; qmul x2, x1, x5            load -> qmul rs1
//   2  lw x3, 4(x17) ; qmul x4, x5, x3            load -> qmul rs2
//   3  lw x6, 0(x17) ; qmul x7, x6, x6            load -> qmul 两个操作数
//   4  lw x8, 4(x17) ; 无关 ; qmul x9, x8, x5     load 后隔一条
//
// 数据：d[0] = 0x00abc4d2（低 12 位 0x4d2 = 1234），d[1] = 0xfff00929（低 12 位 0x929 = 2345）。
// 高位故意非零，qmul 只取低 12 位。x5 = 1234。期望值（q = 3329）：
//   1234·1234 = 1522756 = 457·3329 + 1403     -> 1403
//   1234·2345 = 2893730 = 869·3329 + 829      -> 829
//
// 失败码：
//   1  x2 = 1403
//   2  x4 = 829
//   3  x7 = 1403
//   4  x9 = 829
#include "test.h"
#include "qmul.h"

    .data
    .balign 4
d:
    .word   0x00abc4d2
    .word   0xfff00929

TEST_BEGIN
    LI      x5, 1234
    LI      x21, 0x21
    LI      x1, 0x111
    LI      x2, 0x222
    LI      x3, 0x333
    LI      x4, 0x444
    LI      x6, 0x666
    LI      x7, 0x777
    LI      x8, 0x888, x15
    LI      x9, 0x999, x15
    LA      x17, d
    SEP

    lw      x1, 0(x17)
    PAD_DATA
    qmul    x2, x1, x5
    SEP

    lw      x3, 4(x17)
    PAD_DATA
    qmul    x4, x5, x3
    SEP

    lw      x6, 0(x17)
    PAD_DATA
    qmul    x7, x6, x6
    SEP

    lw      x8, 4(x17)
    add     x20, x21, x21
    PAD_DATA
    qmul    x9, x8, x5
    SEP

    CHECK   x2, 1403, 1
    CHECK   x4, 829, 2
    CHECK   x7, 1403, 3
    CHECK   x9, 829, 4
TEST_END
