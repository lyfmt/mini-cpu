// 程序测试：用循环求 1 + 2 + ... + 100。
//
// base9 没有 addi 和 bne，计数靠 add 一个存着 1 的寄存器，
// 循环条件用 slt 算出 (i < 100)，再用 beq 和 1 比较向后跳。
//
// 失败码：
//   1  和 = 5050
//   2  循环结束时 i = 100
//   3  写进存储器的和读回来仍是 5050
#include "test.h"

    .data
    .balign 4
result:
    .word   0

TEST_BEGIN
    LI      x1, 0               // i
    LI      x2, 0               // sum
    LI      x3, 1
    LI      x4, 100
    LA      x6, result
    PAD_DATA
.Lloop:
    add     x1, x1, x3          // i = i + 1
    PAD_DATA
    add     x2, x2, x1          // sum = sum + i
    slt     x5, x1, x4          // i < 100 ?
    PAD_DATA
    beq     x5, x3, .Lloop
    PAD_JUMP

    sw      x2, 0(x6)
    lw      x7, 0(x6)
    CHECK   x2, 5050, 1
    CHECK   x1, 100, 2
    CHECK   x7, 5050, 3
TEST_END
