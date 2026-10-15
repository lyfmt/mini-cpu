// 性能测试："只检查真正会被读的源寄存器"，rv32i 新增的指令（第五节 load-use 的第一处细化）。
//
// lw x5 后面紧跟的指令，rs1 或 rs2 字段位置上的数恰好是 5，但它并不读 x5：
// auipc 不读任何源寄存器；I 型指令只读 rs1，inst[24:20] 是立即数的低 5 位
// （移位指令是移位量）。这些都不应停顿。
//
//   1-2    auipc x20, 0x28        inst[19:15] = 5              停 0，冲刷 0
//   3-4    auipc x20, 0x500       inst[24:20] = 5              停 0，冲刷 0
//   5-6    addi  x20, x0, 5       inst[24:20] = imm[4:0] = 5   停 0，冲刷 0
//   7-8    andi  x20, x0, 5                                    停 0，冲刷 0
//   9-10   xori  x20, x0, 5                                    停 0，冲刷 0
//   11-12  slti  x20, x0, 5                                    停 0，冲刷 0
//   13-14  sltiu x20, x0, 5                                    停 0，冲刷 0
//   15-16  slli  x20, x9, 5       inst[24:20] = shamt = 5      停 0，冲刷 0
//   17-18  srli  x20, x9, 5                                    停 0，冲刷 0
//   19-20  srai  x20, x9, 5                                    停 0，冲刷 0
//   21-22  jalr  x0, 5(x10)       inst[24:20] = imm[4:0] = 5；x10 = 目标 - 5
//                                                              停 0，冲刷 1
//
// 失败码：1  jalr 跳到的不是目标
#include "test.h"

    .data
    .balign 4
d:
    .word   0x11

TEST_BEGIN
    LI      x9, 0x12345678, x7
    LA      x17, d
    LA      x10, .L21
    PAD_DATA
    addi    x10, x10, -5

    // PERF 1-2: stalls=0 flushes=0
    PERF_MARK 1
    lw      x5, 0(x17)
    auipc   x20, 0x28
    PERF_MARK 2

    // PERF 3-4: stalls=0 flushes=0
    PERF_MARK 3
    lw      x5, 0(x17)
    auipc   x20, 0x500
    PERF_MARK 4

    // PERF 5-6: stalls=0 flushes=0
    PERF_MARK 5
    lw      x5, 0(x17)
    addi    x20, x0, 5
    PERF_MARK 6

    // PERF 7-8: stalls=0 flushes=0
    PERF_MARK 7
    lw      x5, 0(x17)
    andi    x20, x0, 5
    PERF_MARK 8

    // PERF 9-10: stalls=0 flushes=0
    PERF_MARK 9
    lw      x5, 0(x17)
    xori    x20, x0, 5
    PERF_MARK 10

    // PERF 11-12: stalls=0 flushes=0
    PERF_MARK 11
    lw      x5, 0(x17)
    slti    x20, x0, 5
    PERF_MARK 12

    // PERF 13-14: stalls=0 flushes=0
    PERF_MARK 13
    lw      x5, 0(x17)
    sltiu   x20, x0, 5
    PERF_MARK 14

    // PERF 15-16: stalls=0 flushes=0
    PERF_MARK 15
    lw      x5, 0(x17)
    slli    x20, x9, 5
    PERF_MARK 16

    // PERF 17-18: stalls=0 flushes=0
    PERF_MARK 17
    lw      x5, 0(x17)
    srli    x20, x9, 5
    PERF_MARK 18

    // PERF 19-20: stalls=0 flushes=0
    PERF_MARK 19
    lw      x5, 0(x17)
    srai    x20, x9, 5
    PERF_MARK 20

    // PERF 21-22: stalls=0 flushes=1
    PERF_MARK 21
    lw      x5, 0(x17)
    jalr    x0, 5(x10)
    PAD_JUMP
    TEST_FAIL 1
.L21:
    PERF_MARK 22
TEST_END
