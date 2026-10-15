// ModelSim 演示"定制指令"：qmul 后紧跟一条使用其结果的指令。
//
//   qmul x5, x1, x2 ; add x6, x5, x3
// qmul 在 EX 段一拍算出 (1234 * 2345) mod 3329 = 829（ex_qmul_y，经结果选择器进
// m_aluout）；下一拍 add 在 EX，BusAFw = 10，从 EX/M 拿到 829。
//
// 失败码：
//   1  x5 = 829
//   2  x6 = 829 + 1000 = 1829
#include "test.h"
#include "qmul.h"

TEST_BEGIN
    LI      x1, 1234
    LI      x2, 2345, x7
    LI      x3, 1000
    LI      x5, 0x555
    // PERF 1-2: stalls=0 flushes=0
    PERF_MARK 1

    qmul    x5, x1, x2
    PAD_DATA
    add     x6, x5, x3
    PERF_MARK 2

    CHECK   x5, 829, 1
    CHECK   x6, 1829, 2
TEST_END
