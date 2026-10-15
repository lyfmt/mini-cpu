// ModelSim 演示"load-use"：lw 后紧跟使用它的 add。
//
//   lw x5, 0(x4) ; add x6, x5, x1
// add 在 ID、lw 在 EX 时 stall = 1：PC 和 IF/ID 保持一拍，ID/EX 写入气泡；
// 下一拍 lw 到 WB，add 在 EX 由 WB 转发（BusAFw = 01）拿到读出的值。
//
// 失败码：
//   1  x6 = mem + x1 = 0x12345679
#include "test.h"

    .data
    .balign 4
src:
    .word   0x12345678

TEST_BEGIN
    LI      x1, 1
    LI      x5, 0x555
    LA      x4, src
    // PERF 1-2: stalls=1 flushes=0
    PERF_MARK 1

    lw      x5, 0(x4)
    PAD_DATA
    add     x6, x5, x1
    PERF_MARK 2

    CHECK   x6, 0x12345679, 1
TEST_END
