// lw rd, imm(rs1)：rd <- Mem[rs1 + 符号扩展(imm12)]
//
// 数据表 tbl 共 2048 字节：A = tbl，B = tbl_end = A + 2048。
// 用 A 加正偏移、B 加负偏移，覆盖立即数的两端（2044 和 -2048）。
//
// 失败码：
//   1  lw 0(A)     = 0x11223344（偏移 0）
//   2  lw 4(A)     = 0x80000000
//   3  lw 8(A)     = 0xffffffff
//   4  lw 12(A)    = 0x7fffffff
//   5  lw 2044(A)  = 0xcafef00d（最大的对齐正偏移）
//   6  lw -4(B)    = 0xcafef00d（负偏移）
//   7  lw -2048(B) = 0x11223344（最小负偏移）
//   8  lw -2044(B) = 0x80000000
//   9  rd = rs1：lw x9, 8(x9)，x9 = A -> 0xffffffff
//  10  lw x0, ... 之后 x0 仍为 0
#include "test.h"

    .data
    .balign 4
tbl:
    .word   0x11223344          // A + 0
    .word   0x80000000          // A + 4
    .word   0xffffffff          // A + 8
    .word   0x7fffffff          // A + 12
    .skip   2044 - 16
    .word   0xcafef00d          // A + 2044
tbl_end:

TEST_BEGIN
    LA      x1, tbl
    LA      x2, tbl_end
    LA      x9, tbl
    PAD_DATA

    lw      x10, 0(x1)
    lw      x11, 4(x1)
    lw      x12, 8(x1)
    lw      x13, 12(x1)
    lw      x14, 2044(x1)
    lw      x15, -4(x2)
    lw      x16, -2048(x2)
    lw      x17, -2044(x2)
    lw      x9, 8(x9)
    lw      x0, 0(x1)

    CHECK   x10, 0x11223344, 1
    CHECK   x11, 0x80000000, 2
    CHECK   x12, 0xffffffff, 3
    CHECK   x13, 0x7fffffff, 4
    CHECK   x14, 0xcafef00d, 5
    CHECK   x15, 0xcafef00d, 6
    CHECK   x16, 0x11223344, 7
    CHECK   x17, 0x80000000, 8
    CHECK   x9, 0xffffffff, 9
    CHECK   x0, 0, 10
TEST_END
