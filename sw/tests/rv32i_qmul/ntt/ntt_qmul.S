// NTT 评估程序，qmul 版（设计文档第七节"怎么证明它有用"）。
//
// NTT 主体在 sw/ntt/ntt_body.S，两个版本共用；这里只定义 MODMUL：
// 一条定制指令 qmul。另一个版本见 sw/tests/rv32i/ntt/ntt_sw.S。
//
// 失败码：k + 1（1..256），第一处与期望输出不等的是第 k 个系数。
#include "test.h"
#include "qmul.h"

.macro MODMUL rd, rs1, rs2
    qmul    \rd, \rs1, \rs2
.endm

#include "../../../ntt/ntt_body.S"
