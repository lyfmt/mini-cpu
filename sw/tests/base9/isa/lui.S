// lui rd, imm20：rd <- imm20 << 12，低 12 位为 0。
//
// 失败码：
//   1  lui 0x80000 = 0x80000000（最高位为 1，不做任何扩展）
//   2  lui 0xfffff = 0xfffff000
//   3  lui 0x00000 = 0（rd 原来是 0x7ff，低位被清零）
//   4  lui 0x12345 = 0x12345000
//   5  lui 0x00001 = 0x00001000
//   6  lui 0xabcde = 0xabcde000（rd 原来是 0xffffffff，低 12 位被清零）
//   7  lui 0x7ffff = 0x7ffff000
//   8  lui x0, ... 之后 x0 仍为 0
#include "test.h"

TEST_BEGIN
    LI      x3, 0x7ff
    LI      x6, -1
    PAD_DATA

    lui     x1, 0x80000
    lui     x2, 0xfffff
    lui     x3, 0
    lui     x4, 0x12345
    lui     x5, 0x00001
    lui     x6, 0xabcde
    lui     x7, 0x7ffff
    lui     x0, 0x12345

    CHECK   x1, 0x80000000, 1
    CHECK   x2, 0xfffff000, 2
    CHECK   x3, 0, 3
    CHECK   x4, 0x12345000, 4
    CHECK   x5, 0x00001000, 5
    CHECK   x6, 0xabcde000, 6
    CHECK   x7, 0x7ffff000, 7
    CHECK   x0, 0, 8
TEST_END
