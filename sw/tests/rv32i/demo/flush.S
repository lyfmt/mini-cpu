// ModelSim 演示"冲刷"：beq 成立、jal、jalr 各一次。
//
// 每条跳转在 M 段时 flush = 1，PC 换成目标，IF/ID、ID/EX、EX/M 下一拍都是气泡。
// 每条跳转后面紧跟的错误路径指令写 x20 / x21 / x22 / 存储器，必须被冲刷掉。
//   1  beq x1, x1, .Lt1    错误路径：ori x20 ; sw x1, 0(x4)
//   2  jal x11, .Lt2       错误路径：ori x21
//   3  jalr x12, 0(x9)     错误路径：ori x22（x9 = .Lt3）
//
// 失败码：
//   1  x20 = 0（beq 的错误路径被冲刷）
//   2  buf[0] 不变
//   3  x21 = 0
//   4  x22 = 0
//   5  x11 = jal 的返回地址
//   6  x12 = jalr 的返回地址
//   其他：没有跳（落到紧跟的 TEST_FAIL 10x）
#include "test.h"

    .data
    .balign 4
buf:
    .word   0xb0b0b0b0

TEST_BEGIN
    LI      x1, 0x11
    LI      x20, 0
    LI      x21, 0
    LI      x22, 0
    LI      x11, 0
    LI      x12, 0
    LA      x4, buf
    LA      x9, .Lt3
    // PERF 1-2: stalls=0 flushes=3
    PERF_MARK 1

    beq     x1, x1, .Lt1
    PAD_JUMP
    ori     x20, x0, 1
    sw      x1, 0(x4)
    TEST_FAIL 101
.Lt1:
    jal     x11, .Lt2
.Lret2:
    PAD_JUMP
    ori     x21, x0, 1
    TEST_FAIL 102
.Lt2:
    jalr    x12, 0(x9)
.Lret3:
    PAD_JUMP
    ori     x22, x0, 1
    TEST_FAIL 103
.Lt3:
    PERF_MARK 2

    lw      x10, 0(x4)
    CHECK   x20, 0, 1
    CHECK   x10, 0xb0b0b0b0, 2
    CHECK   x21, 0, 3
    CHECK   x22, 0, 4
    CHECK   x11, .Lret2, 5
    CHECK   x12, .Lret3, 6
TEST_END
