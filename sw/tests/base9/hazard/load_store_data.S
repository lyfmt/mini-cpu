// 冒险场景（第五节表）："load 后紧跟 store，依赖在数据"  lw x1,.. ; sw x1,0(x2)  —— DiSrc，不停顿
//
// store 要写的数据在 M 段才用到，那时 load 已在 WB，由 DiSrc 在 M 段补上。
// 被 load 的寄存器事先放了旧值，DiSrc 缺失时写进去的是旧值。
//
// 失败码：
//   1  lw x1 ; sw x1, 0(x18)                    -> dst[0] = 0x13579bdf
//   2  lw x2 ; sw x2, 4(x18)                    -> dst[1] = 0x80000000
//   3  lw x3 ; sw x3, 8(x18) ; sw x3, 12(x18)   -> dst[2] = 0xfedcba98
//   4  上一组的第二条 store 隔一条（EX 段 WB 转发）-> dst[3] = 0xfedcba98
//   5  lw x5 ; sw x5, 16(x18) ; lw x6, 16(x18)  紧接着读回 -> 0x13579bdf
#include "test.h"

    .data
    .balign 4
src:
    .word   0x13579bdf, 0x80000000, 0xfedcba98
dst:
    .word   0xdddddddd, 0xdddddddd, 0xdddddddd, 0xdddddddd, 0xdddddddd

TEST_BEGIN
    LI      x1, 0x111
    LI      x2, 0x222
    LI      x3, 0x333
    LI      x5, 0x555
    LA      x17, src
    LA      x18, dst
    // 计数器（nopad，MARK 1-2 之间）：load 后紧跟 store 的数据，不停
    // PERF 1-2: stalls=0 flushes=0
    PERF_MARK 1

    lw      x1, 0(x17)
    PAD_DATA
    sw      x1, 0(x18)
    SEP
    lw      x2, 4(x17)
    PAD_DATA
    sw      x2, 4(x18)
    SEP
    lw      x3, 8(x17)
    PAD_DATA
    sw      x3, 8(x18)
    sw      x3, 12(x18)
    SEP
    lw      x5, 0(x17)
    PAD_DATA
    sw      x5, 16(x18)
    lw      x6, 16(x18)
    PERF_MARK 2

    lw      x10, 0(x18)
    lw      x11, 4(x18)
    lw      x12, 8(x18)
    lw      x13, 12(x18)
    CHECK   x10, 0x13579bdf, 1
    CHECK   x11, 0x80000000, 2
    CHECK   x12, 0xfedcba98, 3
    CHECK   x13, 0xfedcba98, 4
    CHECK   x6, 0x13579bdf, 5
TEST_END
