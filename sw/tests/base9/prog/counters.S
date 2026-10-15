// 程序测试：读硬件计数器、写 MARK。
//
// 读 CYCLE/INSTRET/STALLS/FLUSHES 的 load 在期望轨迹里是 X 行（值不比较）；
// MARK 让测试平台打印一行计数器快照，两次 MARK 之间是一个 10 次的循环。
// 计数器的值不能直接和常数比较，只检查它们在增长：用 sltu 比较前后两次读数，
// 结果（1）是确定的，照常对拍。
//
// 失败码：
//   1  第二次读的 CYCLE 大于第一次
//   2  第二次读的 INSTRET 大于第一次
//   3  循环执行了 10 次
#include "test.h"

TEST_BEGIN
    READ_COUNTER x1, IO_CYCLE
    READ_COUNTER x2, IO_INSTRET
    MARK_POINT 1

    LI      x5, 0
    LI      x6, 1
    LI      x7, 10
    PAD_DATA
.Lloop:
    add     x5, x5, x6
    PAD_DATA
    slt     x8, x5, x7
    PAD_DATA
    beq     x8, x6, .Lloop
    PAD_JUMP

    MARK_POINT 2
    READ_COUNTER x3, IO_CYCLE
    READ_COUNTER x4, IO_INSTRET
    READ_COUNTER x9, IO_STALLS
    READ_COUNTER x10, IO_FLUSHES
    PAD_DATA
    sltu    x11, x1, x3
    sltu    x12, x2, x4

    CHECK   x11, 1, 1
    CHECK   x12, 1, 2
    CHECK   x5, 10, 3
TEST_END
