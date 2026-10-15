// 程序测试：排序。
//
// 同一组 16 个数（含负数、重复值、最大最小值）排两次：
//   A：插入排序，按有符号数从小到大（blt/bge）；
//   B：选择排序，按无符号数从大到小（bltu/bgeu）。
// 期望结果由一段独立的 Python（sorted()）算出，写成常数。
//
// 失败码：
//   1..16   A[0..15]
//   17..32  B[0..15]
#include "test.h"

#define N 16

    .data
    .balign 4
arr_a:
    .word   0x12345678, -5, 0x7fffffff, 0, 0x80000000, 42, -5, 1000
    .word   -1, 0x00010000, 7, 0x80000001, 3, 999999, -100000, 1
arr_b:
    .word   0x12345678, -5, 0x7fffffff, 0, 0x80000000, 42, -5, 1000
    .word   -1, 0x00010000, 7, 0x80000001, 3, 999999, -100000, 1

TEST_BEGIN
    LA      x17, arr_a
    LA      x20, arr_b
    LI      x18, N
    PAD_DATA

    // ---- A：插入排序，有符号升序
    addi    x11, x0, 1                  // i
.Lins_outer:
    PAD_DATA
    bge     x11, x18, .Lins_done
    PAD_JUMP
    slli    x12, x11, 2
    PAD_DATA
    add     x12, x12, x17               // &A[i]
    PAD_DATA
    lw      x13, 0(x12)                 // key
    addi    x14, x12, -4                // p = &A[i-1]
.Lins_inner:
    PAD_DATA
    bltu    x14, x17, .Lins_place       // p 越过了 A[0]
    PAD_JUMP
    lw      x15, 0(x14)
    PAD_DATA
    bge     x13, x15, .Lins_place       // key >= *p：位置找到了
    PAD_JUMP
    sw      x15, 4(x14)
    addi    x14, x14, -4
    jal     x0, .Lins_inner
    PAD_JUMP
.Lins_place:
    sw      x13, 4(x14)
    addi    x11, x11, 1
    jal     x0, .Lins_outer
    PAD_JUMP
.Lins_done:

    // ---- B：选择排序，无符号降序
    slli    x21, x18, 2
    PAD_DATA
    add     x21, x21, x20               // 末尾
    addi    x19, x18, -1
    addi    x11, x0, 0                  // i
.Lsel_outer:
    PAD_DATA
    bge     x11, x19, .Lsel_done
    PAD_JUMP
    slli    x12, x11, 2
    PAD_DATA
    add     x12, x12, x20               // &B[i]
    PAD_DATA
    addi    x14, x12, 0                 // 最大值的位置
    lw      x15, 0(x12)                 // 最大值
    addi    x16, x12, 4                 // q
.Lsel_inner:
    PAD_DATA
    bgeu    x16, x21, .Lsel_swap
    PAD_JUMP
    lw      x22, 0(x16)
    PAD_DATA
    bgeu    x15, x22, .Lsel_next        // 当前最大值 >= *q
    PAD_JUMP
    addi    x14, x16, 0
    addi    x15, x22, 0
.Lsel_next:
    addi    x16, x16, 4
    jal     x0, .Lsel_inner
    PAD_JUMP
.Lsel_swap:
    lw      x22, 0(x12)
    sw      x15, 0(x12)
    PAD_DATA
    sw      x22, 0(x14)
    addi    x11, x11, 1
    jal     x0, .Lsel_outer
    PAD_JUMP
.Lsel_done:

.macro CHECK_AT base, index, value, code
    lw      x10, (\index * 4)(\base)
    PAD_DATA
    CHECK   x10, \value, \code
.endm

    CHECK_AT x17, 0, 0x80000000, 1
    CHECK_AT x17, 1, 0x80000001, 2
    CHECK_AT x17, 2, 0xfffe7960, 3
    CHECK_AT x17, 3, 0xfffffffb, 4
    CHECK_AT x17, 4, 0xfffffffb, 5
    CHECK_AT x17, 5, 0xffffffff, 6
    CHECK_AT x17, 6, 0x00000000, 7
    CHECK_AT x17, 7, 0x00000001, 8
    CHECK_AT x17, 8, 0x00000003, 9
    CHECK_AT x17, 9, 0x00000007, 10
    CHECK_AT x17, 10, 0x0000002a, 11
    CHECK_AT x17, 11, 0x000003e8, 12
    CHECK_AT x17, 12, 0x00010000, 13
    CHECK_AT x17, 13, 0x000f423f, 14
    CHECK_AT x17, 14, 0x12345678, 15
    CHECK_AT x17, 15, 0x7fffffff, 16

    CHECK_AT x20, 0, 0xffffffff, 17
    CHECK_AT x20, 1, 0xfffffffb, 18
    CHECK_AT x20, 2, 0xfffffffb, 19
    CHECK_AT x20, 3, 0xfffe7960, 20
    CHECK_AT x20, 4, 0x80000001, 21
    CHECK_AT x20, 5, 0x80000000, 22
    CHECK_AT x20, 6, 0x7fffffff, 23
    CHECK_AT x20, 7, 0x12345678, 24
    CHECK_AT x20, 8, 0x000f423f, 25
    CHECK_AT x20, 9, 0x00010000, 26
    CHECK_AT x20, 10, 0x000003e8, 27
    CHECK_AT x20, 11, 0x0000002a, 28
    CHECK_AT x20, 12, 0x00000007, 29
    CHECK_AT x20, 13, 0x00000003, 30
    CHECK_AT x20, 14, 0x00000001, 31
    CHECK_AT x20, 15, 0x00000000, 32
TEST_END
