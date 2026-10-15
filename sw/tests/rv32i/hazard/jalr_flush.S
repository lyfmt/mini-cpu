// 冒险场景（第五节表）："跳转成立"（jalr）—— 冲刷 3 条；
// 以及 jalr 参与的"连续跳转"、"冲刷和停顿同时出现"。
//
// jalr 在 M 段重定向时，后面三条已在 IF、ID、EX，必须全部作废。
// nopad 变体里这三条紧跟在 jalr 后面（pad 变体里排在三条空指令之后）：
//   1  jalr x0 ; ori x1 ; sw x5 ; jal x0, .Lbad1           写寄存器、写存储器、跳转
//   2  jalr x4 ; lw x6 ; add x7, x6, x6 ; addi x4          jalr 在 M 段时 lw 在 EX、
//      目标处：add x21, x4, x0                             add 在 ID：冲刷和 load-use
//                                                          停顿同时出现，冲刷优先；
//                                                          第三条写的正是 jalr 的 rd
//   3  jalr x0, 0(x19) -> .Lt3: jalr x0, 0(x20) -> .Lt3b   连续跳转
//   4  jalr x0, 0(x22)，目标是紧跟的下一条                  下一条被冲刷后重新取指，
//                                                          恰好执行一次
//
// 失败码：
//   1  x1 仍为 0（错误路径上的 ori 被冲刷）
//   2  buf[0] 仍为 0xb0b0b0b0（错误路径上的 sw 被冲刷）
//   3  x4 = 第 2 组 jalr 的返回地址，x21 = x4（目标处立刻读到的是 jalr 写的值）
//   4  x6、x7 不变
//   5  第 3 组两次跳转都到位：x23 = 0x33
//   6  第 4 组目标指令恰好执行一次：x24 = 1
//   其他：.Lbad1（错误路径上的 jal 生效）、没有跳（落到紧跟的 TEST_FAIL 10x）
#include "test.h"

    .data
    .balign 4
buf:
    .word   0xb0b0b0b0

TEST_BEGIN
    LA      x17, .Lt1
    LA      x18, buf
    LA      x19, .Lt3
    LA      x20, .Lt3b
    LA      x16, .Lt2
    LA      x22, .Lnext
    LI      x1, 0
    LI      x4, 0
    LI      x5, 0x5555
    LI      x6, 0x666
    LI      x7, 0x777
    LI      x21, 0
    LI      x23, 0
    LI      x24, 0
    LI      x25, 1
    // 计数器（nopad，MARK 1-2 之间）：五次 jalr；错误路径上的 load-use 与冲刷同一拍，不计
    // PERF 1-2: stalls=0 flushes=5
    PERF_MARK 1

    // 1
    jalr    x0, 0(x17)
    PAD_JUMP
    ori     x1, x0, 0x11
    sw      x5, 0(x18)
    jal     x0, .Lbad1
    TEST_FAIL 101
.Lt1:
    SEP

    // 2
.Lj2:
    jalr    x4, 0(x16)
    PAD_JUMP
    lw      x6, 0(x18)
    add     x7, x6, x6
    addi    x4, x0, 0x44
    TEST_FAIL 102
.Lt2:
    PAD_DATA
    add     x21, x4, x0
    SEP

    // 3
    jalr    x0, 0(x19)
    PAD_JUMP
    TEST_FAIL 103
.Lt3:
    jalr    x0, 0(x20)
    PAD_JUMP
    TEST_FAIL 104
.Lt3b:
    ori     x23, x0, 0x33
    SEP

    // 4
    jalr    x0, 0(x22)
    PAD_JUMP
.Lnext:
    add     x24, x24, x25
    PERF_MARK 2

    lw      x10, 0(x18)
    PAD_DATA
    CHECK   x1, 0, 1
    CHECK   x10, 0xb0b0b0b0, 2
    CHECK   x4, .Lj2 + 4, 3
    CHECK   x21, .Lj2 + 4, 3
    CHECK   x6, 0x666, 4
    CHECK   x7, 0x777, 4
    CHECK   x23, 0x33, 5
    CHECK   x24, 1, 6
TEST_END

.Lbad1:
    TEST_FAIL 105
