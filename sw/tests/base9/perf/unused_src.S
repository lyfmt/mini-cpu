// 性能测试："只检查真正会被读的源寄存器"（第五节 load-use 的第一处细化）。
//
// load 后面紧跟的指令，rs1 或 rs2 字段位置上的数恰好等于 load 的目标寄存器，
// 但这条指令并不读它（字段其实是立即数的一部分），所以不应停顿。
//
//   1-2    lw x5 ; lui x20, 0x28          lui 的 inst[19:15] = 5            停 0
//   3-4    lw x5 ; lui x20, 0x500         lui 的 inst[24:20] = 5            停 0
//   5-6    lw x5 ; ori x20, x0, 5         I 型的 inst[24:20] 是 imm[4:0] = 5 停 0
//   7-8    lw x8 ; lw x20, 8(x17)         lw 的 inst[24:20] 是 imm[4:0] = 8  停 0
//   9-10   lw x4 ; jal x0, +36            jal 的 inst[24:20] = {imm[4:1], imm[11]} = 4
//                                         停 0，冲刷 1
//   11-12  jal x0, A ; B: jal x0, C ; A: lw x31 ; jal x0, B（向后）; C:
//                                         向后 jal 的 inst[19:15] = imm[19:15] = 31
//                                         停 0，冲刷 3
//
// 数据：d[0] = 0x11，d[1] = 0x22，d[2] = 0x33
// 失败码：1  lw x20, 8(x17) 读到 d[2]
#include "test.h"

    .data
    .balign 4
d:
    .word   0x11, 0x22, 0x33

TEST_BEGIN
    LA      x17, d

    // PERF 1-2: stalls=0 flushes=0
    PERF_MARK 1
    lw      x5, 0(x17)
    lui     x20, 0x28
    PERF_MARK 2

    // PERF 3-4: stalls=0 flushes=0
    PERF_MARK 3
    lw      x5, 0(x17)
    lui     x20, 0x500
    PERF_MARK 4

    // PERF 5-6: stalls=0 flushes=0
    PERF_MARK 5
    lw      x5, 0(x17)
    ori     x20, x0, 5
    PERF_MARK 6

    // PERF 7-8: stalls=0 flushes=0
    PERF_MARK 7
    lw      x8, 0(x17)
    lw      x20, 8(x17)
    PERF_MARK 8
    PAD_DATA
    CHECK   x20, 0x33, 1

    // PERF 9-10: stalls=0 flushes=1
    PERF_MARK 9
    lw      x4, 4(x17)
.Ljal1:
    jal     x0, .Ljal1_target
    PAD_JUMP
    .rept 8
    ori     x21, x0, 0x7ff      // 不执行：前 3 条在错误路径上被冲刷，其余被跳过
    .endr
#ifndef PAD
    .org    .Ljal1 + 36         // jal 的偏移必须是 36，inst[24:20] 才等于 4（多了会报错）
#endif
.Ljal1_target:
    PERF_MARK 10

    // PERF 11-12: stalls=0 flushes=3
    PERF_MARK 11
    jal     x0, .Ljal2_a
    PAD_JUMP
.Ljal2_b:
    jal     x0, .Ljal2_c
    SEP
.Ljal2_a:
    lw      x31, 0(x17)
    jal     x0, .Ljal2_b        // 向后跳：inst[19:15] = 31
    PAD_JUMP
.Ljal2_c:
    PERF_MARK 12
TEST_END
