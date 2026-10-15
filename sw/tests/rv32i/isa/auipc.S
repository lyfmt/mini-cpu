// rv32i 单指令测试：auipc。期望值按 RISC-V 规范手工计算：rd = pc + (imm << 12)。
//
// 第一组紧跟在 TEST_BEGIN（0x0 处的一条 lui）之后，pc 是确定的，期望值直接写成
// 常数；汇编时用 .if 确认这组指令确实从 0x4 开始。第二组在程序中间，期望值写成
// "标号 + 偏移"。覆盖：立即数 0、1、最高位为 1（0x80000、0xfffff，结果回绕）、
// 0x7ffff；与 lui 的区别（立即数 1 得 0x1008 而不是 0x1000）；写 x0。
//
// 失败码：每个用例的最后一个参数，说明见行尾注释。
#include "test.h"

TEST_BEGIN
.Lfirst:
    auipc   x10, 0                  // 0x04
    auipc   x11, 1                  // 0x08
    auipc   x12, 0x80000            // 0x0c
    auipc   x13, 0xfffff            // 0x10
    auipc   x14, 0x7ffff            // 0x14
    auipc   x0, 0x12345             // 0x18
    .if .Lfirst - _start != 4
    .error "auipc.S: the first group must start at 0x4"
    .endif
    PAD_DATA
    CHECK   x10, 0x00000004, 1      // 0x4 + 0
    CHECK   x11, 0x00001008, 2      // 0x8 + 0x1000
    CHECK   x12, 0x8000000c, 3      // 0xc + 0x80000000
    CHECK   x13, 0xfffff010, 4      // 0x10 + 0xfffff000，回绕
    CHECK   x14, 0x7ffff014, 5      // 0x14 + 0x7ffff000
    CHECK   x0, 0, 6                // 写 x0 无效

.La7:
    auipc   x15, 0x12345
    PAD_DATA
    CHECK   x15, .La7 + 0x12345000, 7
.La8:
    auipc   x15, 0x80001
    PAD_DATA
    CHECK   x15, .La8 + 0x80001000, 8
.La9:
    auipc   x15, 0xfffff
    PAD_DATA
    CHECK   x15, .La9 - 0x1000, 9
.La10:
    auipc   x15, 0
    PAD_DATA
    CHECK   x15, .La10, 10
TEST_END
