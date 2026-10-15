// 冒险场景（第五节表）：qmul 的结果紧接着被 store
//   "相邻依赖"（store 数据 rs2 在 EX 段经 EX/M 转发，再随指令存进 EX/M）
//   "运算后隔一条 store"  `add x1,..` ; 无关 ; `sw x1,..`
//                        —— 转发后的 busB 存进 EX/M（课程图的缺口）
//   另加一组 load -> qmul -> store 连在一起：qmul 先因 load-use 停一拍，
//   结果再紧接着被 store。
//
// nopad 变体里每组的指令紧挨着（用 SEP 和前后代码隔开）：
//   1  qmul x1, x5, x6 ; sw x1, 0(x17)
//   2  qmul x2, x5, x6 ; 无关 ; sw x2, 4(x17)
//   3  lw x3, 12(x17) ; qmul x4, x3, x5 ; sw x4, 8(x17)
//
// 数据：d[0..2] 事先是 0xdeadbeef（以免旧值碰巧等于期望值），d[3] = 0x7777f4d2
// （低 12 位 0x4d2 = 1234）。x5 = 1234，x6 = 2345。期望值（q = 3329）：
//   1234·2345 mod q = 829；1234·1234 mod q = 1403
//
// 失败码：
//   1  d[0] = 829
//   2  d[1] = 829
//   3  d[2] = 1403
#include "test.h"
#include "qmul.h"

    .data
    .balign 4
d:
    .word   0xdeadbeef
    .word   0xdeadbeef
    .word   0xdeadbeef
    .word   0x7777f4d2

TEST_BEGIN
    LI      x5, 1234
    LI      x6, 2345, x15
    LI      x21, 0x21
    LI      x1, 0x111
    LI      x2, 0x222
    LI      x3, 0x333
    LI      x4, 0x444
    LA      x17, d
    SEP

    qmul    x1, x5, x6
    PAD_DATA
    sw      x1, 0(x17)
    SEP

    qmul    x2, x5, x6
    add     x20, x21, x21
    PAD_DATA
    sw      x2, 4(x17)
    SEP

    lw      x3, 12(x17)
    PAD_DATA
    qmul    x4, x3, x5
    PAD_DATA
    sw      x4, 8(x17)
    SEP

    lw      x10, 0(x17)
    lw      x11, 4(x17)
    lw      x12, 8(x17)
    CHECK   x10, 829, 1
    CHECK   x11, 829, 2
    CHECK   x12, 1403, 3
TEST_END
