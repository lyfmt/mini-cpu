/*
 * 定制指令 qmul（设计文档第七节）
 *
 *   qmul rd, rs1, rs2    rd <- (rs1[11:0] * rs2[11:0]) mod 3329，操作数按无符号数
 *
 * 编码：R 型，opcode 0001011（custom-0），funct3 000，funct7 0000000。
 * 汇编器不认识 qmul，用 .insn 直接写出编码。只能用在 rv32i_qmul 的测试里。
 */
#ifndef MINICPU_QMUL_H
#define MINICPU_QMUL_H

.macro qmul rd, rs1, rs2
    .insn r 0x0b, 0, 0, \rd, \rs1, \rs2
.endm

#endif
