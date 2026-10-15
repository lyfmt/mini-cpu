// ModelSim 演示"store 数据"：
//   1  lw x5, 0(x4) ; sw x5, 8(x4)             不停顿；sw 在 M 段时 lw 在 WB，DiSrc = 1，
//                                              存储器写入的是 WB 写回值（m_DataIn）
//   2  add x6, x1, x2 ; NOP0 ; sw x6, 12(x4)   sw 在 EX 时 add 在 WB，BusBFw = 01，转发后的
//                                              新值存进 EX/M（m_busB），M 段 DiSrc = 0
// x5、x6 事先装上旧值，修正缺失时写进存储器的是旧值。
//
// 失败码：
//   1  dst[0] = 0x13579bdf（DiSrc）
//   2  dst[1] = 0x300（EX 段转发后的 store 数据）
#include "test.h"

    .data
    .balign 4
buf:
    .word   0x13579bdf, 0, 0xdddddddd, 0xdddddddd

TEST_BEGIN
    LI      x1, 0x100
    LI      x2, 0x200
    LI      x5, 0x555
    LI      x6, 0x666
    LA      x4, buf
    // PERF 1-2: stalls=0 flushes=0
    PERF_MARK 1

    lw      x5, 0(x4)
    PAD_DATA
    sw      x5, 8(x4)
    SEP
    add     x6, x1, x2
    NOP0
    PAD_DATA
    sw      x6, 12(x4)
    PERF_MARK 2

    lw      x10, 8(x4)
    lw      x11, 12(x4)
    CHECK   x10, 0x13579bdf, 1
    CHECK   x11, 0x300, 2
TEST_END
