// rv32i 单指令测试：srai。期望值按 RISC-V 规范手工计算。
//
// 覆盖：移 0 位和 31 位、负数高位补符号位（与 srli.S 对同一组负数对照）、
// 正数与 srli 相同、rd = rs1、写 x0。srai 靠指令第 30 位与 srli 区分；
// 最后一项直接用 .word 写出编码，确认第 30 位。
//
// 失败码：每个用例的最后一个参数，说明见行尾注释。
#include "test.h"

TEST_BEGIN
    TEST_RI srai, 0x80000000, 0, 0x80000000, 1           // 移 0 位
    TEST_RI srai, 0x80000000, 31, 0xffffffff, 2          // 移 31 位
    TEST_RI srai, 0x7fffffff, 31, 0x00000000, 3
    TEST_RI srai, 0x87654321, 1, 0xc3b2a190, 4           // （srli 得 0x43b2a190）
    TEST_RI srai, 0x87654321, 8, 0xff876543, 5           // （srli 得 0x00876543）
    TEST_RI srai, 0x12345678, 4, 0x01234567, 6           // 正数
    TEST_RI srai, 0xffffffff, 16, 0xffffffff, 7          // （srli 得 0x0000ffff）

    // rd = rs1
    LI      x5, 0xabcdef00, x7
    PAD_DATA
    srai    x5, x5, 8
    PAD_DATA
    CHECK   x5, 0xffabcdef, 8

    // 写 x0 无效
    srai    x0, x5, 1
    PAD_DATA
    CHECK   x0, 0, 9

    // srai x10, x5, 4 的编码：funct7 = 0100000（第 30 位为 1），shamt = 4，
    // rs1 = 5，funct3 = 101，rd = 10，opcode = 0010011
    // = 0100000 00100 00101 101 01010 0010011 = 0x4042d513
    .word   0x4042d513
    PAD_DATA
    CHECK   x10, 0xfffabcde, 10
TEST_END
