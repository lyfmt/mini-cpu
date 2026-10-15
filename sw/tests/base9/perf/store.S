// 性能测试：load 后紧跟 store（第五节 load-use 的第二处细化）。
//
// store 的数据（rs2）到 M 段才用，由 DiSrc 补上，不停顿；store 的地址（rs1）
// 在 EX 段就要用，依赖 load 时照样停一拍。
//
//   1-2    lw x1 ; sw x1, 16(x17)         依赖在数据：停 0
//   3-4    lw x2 ; sw x3, 0(x2)           依赖在地址：停 1
//   5-6    lw x4 ; sw x4, 4(x4)           数据和地址都依赖：停 1
//   7-8    add x5 ; sw x5, 20(x17)        运算后紧跟 store：转发，停 0
//
// 数据：d[0] = 0x0badcafe，d[3] = &d[6]
// 失败码：1..4  各段写进存储器的值
#include "test.h"

    .data
    .balign 4
d:
    .word   0x0badcafe, 0, 0, d + 24, 0, 0, 0, 0

TEST_BEGIN
    LI      x3, 0x333
    LA      x17, d

    // PERF 1-2: stalls=0 flushes=0
    PERF_MARK 1
    lw      x1, 0(x17)
    PAD_DATA
    sw      x1, 16(x17)
    PERF_MARK 2

    // PERF 3-4: stalls=1 flushes=0
    PERF_MARK 3
    lw      x2, 12(x17)
    PAD_DATA
    sw      x3, 0(x2)
    PERF_MARK 4

    // PERF 5-6: stalls=1 flushes=0
    PERF_MARK 5
    lw      x4, 12(x17)
    PAD_DATA
    sw      x4, 4(x4)
    PERF_MARK 6

    // PERF 7-8: stalls=0 flushes=0
    PERF_MARK 7
    add     x5, x3, x3
    PAD_DATA
    sw      x5, 20(x17)
    PERF_MARK 8

    lw      x6, 16(x17)
    lw      x7, 24(x17)
    lw      x8, 28(x17)
    lw      x9, 20(x17)
    PAD_DATA
    CHECK   x6, 0x0badcafe, 1
    CHECK   x7, 0x333, 2
    CHECK   x8, d + 24, 3
    CHECK   x9, 0x666, 4
TEST_END
