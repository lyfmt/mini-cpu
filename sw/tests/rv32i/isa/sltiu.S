// rv32i 单指令测试：sltiu。期望值按 RISC-V 规范手工计算。
//
// 覆盖：立即数先符号扩展成 32 位，再按无符号数比较。负立即数因此是很大的
// 无符号数：-1 即 0xffffffff，-2048 即 0xfffff800。第 4、6、14 项在立即数
// 不做符号扩展（当成 0xfff、0x800）时结果相反。另有 sltiu rd, rs, 1
// （等于 0 判断）、最高位、立即数边界；rd = rs1；写 x0。
//
// 失败码：每个用例的最后一个参数，说明见行尾注释。
#include "test.h"

TEST_BEGIN
    TEST_RI sltiu, 0, 0, 0, 1                            // 相等
    TEST_RI sltiu, 0, 1, 1, 2                            // seqz：0 == 0
    TEST_RI sltiu, 0, -1, 1, 3                           // 0 < 0xffffffff
    TEST_RI sltiu, 0xfffffffe, -1, 1, 4                  // 0xfffffffe < 0xffffffff
    TEST_RI sltiu, 0xffffffff, -1, 0, 5                  // 相等
    TEST_RI sltiu, 0x80000000, -2048, 1, 6               // 0x80000000 < 0xfffff800
    TEST_RI sltiu, 0xfffff800, -2048, 0, 7               // 相等
    TEST_RI sltiu, 0xfffff7ff, -2048, 1, 8
    TEST_RI sltiu, 1, 1, 0, 9                            // seqz：1 != 0
    TEST_RI sltiu, 0x7fffffff, 2047, 0, 10
    TEST_RI sltiu, 2046, 2047, 1, 11
    TEST_RI sltiu, 0xffffffff, 1, 0, 12                  // （slti 成立）
    TEST_RI sltiu, 0x80000000, 1, 0, 13                  // 最高位为 1 是大数
    TEST_RI sltiu, 0x00000800, -2048, 1, 14              // 0x800 < 0xfffff800

    // rd = rs1
    LI      x5, 0x00001000
    PAD_DATA
    sltiu   x5, x5, -1
    PAD_DATA
    CHECK   x5, 1, 15

    // 写 x0 无效
    sltiu   x0, x5, -1
    PAD_DATA
    CHECK   x0, 0, 16
TEST_END
