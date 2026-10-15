// 冒险场景（第五节表）："jalr 依赖 load"  lw x1,.. ; jalr x0,0(x1)  —— 停顿一拍
//
// jalr 在 EX 段用 rs1 算目标地址，紧挨着的 load 那时还在 M 段，数据没出来，
// 必须停顿一拍，再从 WB 转发。被 load 的寄存器事先装上一个"坏目标"的地址，
// 停顿缺失时 jalr 会用旧值跳到 .LbadN，以失败码 N 结束。
//
// nopad 变体里每组的 lw 和 jalr 紧挨着，前后用 SEP 隔开：
//   1  lw x1 ; jalr x0, 0(x1)
//   2  lw x2 ; jalr x3, -8(x2)          带负偏移、写返回地址
//   3  lw x4 ; jalr x4, 0(x4)           rd = rs1
//   4  lw x5 ; ori x9 ; jalr x0, 0(x5)  隔一条（WB 转发，不停顿），作对照
//
// 数据：ptrs = { .Lt1, .Lt2 + 8, .Lt3, .Lt4 }
//
// 失败码：
//   1..4  跳到了旧值指向的 .LbadN（或没有跳，落到紧跟的 TEST_FAIL）
//   5     第 2 组的返回地址 x3
//   6     第 3 组的返回地址 x4
#include "test.h"

    .data
    .balign 4
ptrs:
    .word   .Lt1, .Lt2 + 8, .Lt3, .Lt4

TEST_BEGIN
    LA      x17, ptrs
    LA      x1, .Lbad1
    LA      x2, .Lbad2 + 8
    LA      x4, .Lbad3
    LA      x5, .Lbad4
    LI      x3, 0
    // 计数器（nopad，MARK 1-2 之间）：前三组 jalr 紧跟 load 各停 1 拍，第 4 组隔一条不停；四次 jalr
    // PERF 1-2: stalls=3 flushes=4
    PERF_MARK 1

    lw      x1, 0(x17)
    PAD_DATA
    jalr    x0, 0(x1)
    PAD_JUMP
    TEST_FAIL 1
.Lt1:
    SEP

    lw      x2, 4(x17)
    PAD_DATA
.Lj2:
    jalr    x3, -8(x2)
    PAD_JUMP
    TEST_FAIL 2
.Lt2:
    SEP

    lw      x4, 8(x17)
    PAD_DATA
.Lj3:
    jalr    x4, 0(x4)
    PAD_JUMP
    TEST_FAIL 3
.Lt3:
    SEP

    lw      x5, 12(x17)
    ori     x9, x0, 9
    PAD_DATA
    jalr    x0, 0(x5)
    PAD_JUMP
    TEST_FAIL 4
.Lt4:
    PERF_MARK 2

    CHECK   x3, .Lj2 + 4, 5
    CHECK   x4, .Lj3 + 4, 6
TEST_END

.Lbad1:
    TEST_FAIL 1
.Lbad2:
    TEST_FAIL 2
.Lbad3:
    TEST_FAIL 3
.Lbad4:
    TEST_FAIL 4
