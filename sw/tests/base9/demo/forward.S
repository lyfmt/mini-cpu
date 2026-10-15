// ModelSim 演示"转发"：相邻依赖走 EX/M 转发（10），隔一条依赖走 WB 转发（01）。
//
//   1  add x5, x1, x2 ; add x6, x5, x3          第二条在 EX 时 BusAFw = 10（A<-M）
//   2  add x7, x1, x2 ; NOP0 ; add x8, x3, x7   add x8 在 EX 时 BusBFw = 01（B<-WB）
// 被写的寄存器事先装上别的值，没有转发时 ALU 拿到的是旧值，检查会失败。
//
// 失败码：
//   1  x5 = 0x30
//   2  x6 = x5 + x3 = 0x330
//   3  x8 = x3 + x7 = 0x330
#include "test.h"

TEST_BEGIN
    LI      x1, 0x10
    LI      x2, 0x20
    LI      x3, 0x300
    LI      x5, 0x555
    LI      x7, 0x777
    // PERF 1-2: stalls=0 flushes=0
    PERF_MARK 1

    add     x5, x1, x2
    PAD_DATA
    add     x6, x5, x3
    SEP
    add     x7, x1, x2
    NOP0
    PAD_DATA
    add     x8, x3, x7
    PERF_MARK 2

    CHECK   x5, 0x30, 1
    CHECK   x6, 0x330, 2
    CHECK   x8, 0x330, 3
TEST_END
