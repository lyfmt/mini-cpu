// 冒险场景（第五节表）："load 后紧跟 store，依赖在地址"  lw x1,.. ; sw x2,0(x1)  —— 停顿一拍
//
// store 的地址在 EX 段就要算，load 的数据那时还没出来，必须停顿。
// 存地址的寄存器事先指向 decoy，停顿缺失时会写到 decoy 上。
//
// 数据：ptrs = { &buf, &buf[2] }，buf 初值全 0，decoy 初值 0xdeadbeef ×4
//
// 失败码：
//   1  lw x1 ; sw x2, 0(x1)       -> buf[0] = 0x2468ace0
//   2  lw x3 ; sw x3, 0(x3)       -> buf[2] = &buf[2]（地址和数据都依赖 load）
//   3  lw x4 ; sw x2, 12(x4)      -> buf[3] = 0x2468ace0（带偏移）
//   4  decoy[0] 没被写
//   5  decoy[2] 没被写
//   6  decoy[3] 没被写
#include "test.h"

    .data
    .balign 4
ptrs:
    .word   buf, buf + 8
buf:
    .word   0, 0, 0, 0
decoy:
    .word   0xdeadbeef, 0xdeadbeef, 0xdeadbeef, 0xdeadbeef

TEST_BEGIN
    LI      x2, 0x2468ace0, x20
    LA      x1, decoy
    LA      x3, decoy + 8
    LA      x4, decoy
    LA      x17, ptrs
    LA      x18, buf
    LA      x19, decoy
    // 计数器（nopad，MARK 1-2 之间）：三组 load 后紧跟 store 的地址，各停 1 拍
    // PERF 1-2: stalls=3 flushes=0
    PERF_MARK 1

    lw      x1, 0(x17)
    PAD_DATA
    sw      x2, 0(x1)
    SEP
    lw      x3, 4(x17)
    PAD_DATA
    sw      x3, 0(x3)
    SEP
    lw      x4, 0(x17)
    PAD_DATA
    sw      x2, 12(x4)
    PERF_MARK 2

    lw      x10, 0(x18)
    lw      x11, 8(x18)
    lw      x12, 12(x18)
    lw      x13, 0(x19)
    lw      x14, 8(x19)
    lw      x15, 12(x19)
    CHECK   x10, 0x2468ace0, 1
    CHECK   x11, buf + 8, 2
    CHECK   x12, 0x2468ace0, 3
    CHECK   x13, 0xdeadbeef, 4
    CHECK   x14, 0xdeadbeef, 5
    CHECK   x15, 0xdeadbeef, 6
TEST_END
