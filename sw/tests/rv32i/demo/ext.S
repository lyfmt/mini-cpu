// ModelSim 演示"扩展指令"：移位、bne/blt/bge、auipc、jalr。
//
//   sll/srl/sra/srai   x1 = 0x80000010，移位量 x2 = 4（srai 为 31）
//   bne x3, x4         -5 != 3，成立
//   blt x3, x4         -5 < 3（有符号），成立
//   bge x3, x4         -5 >= 3 不成立，顺序往下
//   auipc x10, 1       x10 = 本条 PC + 0x1000
//   jalr x11, 4(x9)    x9 = .Ljr - 4，跳到 .Ljr，x11 = 返回地址
// 每条成立的分支和 jalr 后面紧跟一条错误路径上的 TEST_FAIL（被冲刷）。
//
// 失败码：
//   1  sll  x5 = 0x00000100
//   2  srl  x6 = 0x08000001
//   3  sra  x7 = 0xf8000001
//   4  srai x8 = 0xffffffff
//   5  auipc x10 = .Lauipc + 0x1000
//   6  jalr x11 = 返回地址 .Ljr_ret
//   其他：分支方向错（10x）
#include "test.h"

TEST_BEGIN
    LI      x1, 0x80000010
    LI      x2, 4
    LI      x3, -5
    LI      x4, 3
    LI      x10, 0
    LI      x11, 0
    LA      x9, .Ljr - 4
    // PERF 1-2: stalls=0 flushes=3
    PERF_MARK 1

    sll     x5, x1, x2
    srl     x6, x1, x2
    sra     x7, x1, x2
    srai    x8, x1, 31
    bne     x3, x4, .Lb1
    PAD_JUMP
    TEST_FAIL 101
.Lb1:
    blt     x3, x4, .Lb2
    PAD_JUMP
    TEST_FAIL 102
.Lb2:
    bge     x3, x4, .Lbad
    PAD_JUMP
.Lauipc:
    auipc   x10, 1
    jalr    x11, 4(x9)
.Ljr_ret:
    PAD_JUMP
    TEST_FAIL 104
.Ljr:
    PERF_MARK 2

    CHECK   x5, 0x00000100, 1
    CHECK   x6, 0x08000001, 2
    CHECK   x7, 0xf8000001, 3
    CHECK   x8, 0xffffffff, 4
    CHECK   x10, .Lauipc + 0x1000, 5
    CHECK   x11, .Ljr_ret, 6
    jal     x0, .Ldone
    PAD_JUMP
.Lbad:
    TEST_FAIL 103
.Ldone:
TEST_END
