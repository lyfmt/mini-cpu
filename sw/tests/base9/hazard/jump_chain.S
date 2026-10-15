// 冒险场景（第五节表）："连续跳转"  跳转目标处又是一条跳转  —— 每次各自冲刷
//
// 前一条跳转在 M 段重定向后，目标处的跳转从头走一遍流水线，到 M 段再重定向。
// 每条跳转后面紧跟的三条（nopad 变体）是错误路径上的标记指令，
// 写 x10、x11、x12，它们必须始终保持 0。
//
// 失败码：
//   1  jal 链：jal x1 -> jal x2 -> jal x3，x1 是第一条的返回地址
//   2                                       x2 是第二条的返回地址
//   3                                       x3 是第三条的返回地址
//   4  beq 链，先向前、再向后、再向前：beq -> beq（向后）-> jal x5，x5 的返回地址
//   5  跳转目标是一条不成立的 beq，后面紧跟成立的 jal：beq 不应跳
//   6  路径计数：每段链的终点恰好执行一次，x20 = 3
//   7  错误路径标记 x10 为 0
//   8  错误路径标记 x11 为 0
//   9  错误路径标记 x12 为 0
#include "test.h"

#define MARKERS ori x10, x0, 1; ori x11, x0, 1; ori x12, x0, 1

TEST_BEGIN
    LI      x10, 0
    LI      x11, 0
    LI      x12, 0
    LI      x20, 0
    LI      x21, 1
    // 计数器（nopad，MARK 1-2 之间）：jal 链 3 次、beq/beq/jal 3 次、jal 和 jal 2 次（中间的 beq 不成立）
    // PERF 1-2: stalls=0 flushes=8
    PERF_MARK 1

    // jal 链
    jal     x1, .La
.Lr1:
    PAD_JUMP
    MARKERS
.La:
    jal     x2, .Lb
.Lr2:
    PAD_JUMP
    MARKERS
.Lb:
    jal     x3, .Lc
.Lr3:
    PAD_JUMP
    MARKERS
.Lc:
    add     x20, x20, x21
    SEP

    // beq 链：向前、向后、向前
    beq     x0, x0, .Ld
    PAD_JUMP
    MARKERS
.Le:
    jal     x5, .Lf
.Lr5:
    PAD_JUMP
    MARKERS
.Ld:
    beq     x0, x0, .Le
    PAD_JUMP
    MARKERS
.Lf:
    add     x20, x20, x21
    SEP

    // 目标是不成立的 beq，紧跟成立的 jal
    jal     x0, .Lg
    PAD_JUMP
    MARKERS
.Lg:
    beq     x0, x21, .Lbad5
    PAD_JUMP
    jal     x0, .Lh
    PAD_JUMP
    MARKERS
.Lh:
    add     x20, x20, x21
    PERF_MARK 2

    CHECK   x1, .Lr1, 1
    CHECK   x2, .Lr2, 2
    CHECK   x3, .Lr3, 3
    CHECK   x5, .Lr5, 4
    CHECK   x20, 3, 6
    CHECK   x10, 0, 7
    CHECK   x11, 0, 8
    CHECK   x12, 0, 9
TEST_END

.Lbad5:
    TEST_FAIL 5
