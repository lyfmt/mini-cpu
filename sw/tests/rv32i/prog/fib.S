// 程序测试：斐波那契数。
//
// fib 用递归写：jal 调用，jalr 返回，返回地址和 s0（x8）、参数存在栈上，
// 借此测试子程序调用（嵌套深度 15，fib(15) 共 1973 次调用）。另用循环算
// fib(47) mod 2^32 作对照。期望值由一段独立的 Python 算出。
//
// 调用约定：参数和返回值在 x10，返回地址 x1，栈指针 x2（sp），x8 由被调用者保存。
//
// 失败码：
//   1..5  fib(0)、fib(1)、fib(2)、fib(10)、fib(15) = 0、1、1、55、610
//   6     调用前后 sp 不变
//   7     调用前后 x8 不变
//   8     循环版 fib(47) mod 2^32 = 0xb11924e1
//   9     循环版 fib(46) = 1836311903
#include "test.h"

.macro CALL_FIB n, expect, code
    addi    x10, x0, \n
    PAD_DATA
    jal     x1, fib
    PAD_JUMP
    CHECK   x10, \expect, \code
.endm

TEST_BEGIN
    LI      x8, 0x5a5a, x9
    PAD_DATA
    CALL_FIB 0, 0, 1
    CALL_FIB 1, 1, 2
    CALL_FIB 2, 1, 3
    CALL_FIB 10, 55, 4
    CALL_FIB 15, 610, 5
    CHECK   sp, 0x11000, 6
    CHECK   x8, 0x5a5a, 7

    // 循环版：x11 = fib(k)，x12 = fib(k+1)
    addi    x11, x0, 0
    addi    x12, x0, 1
    addi    x13, x0, 46
.Lloop:
    PAD_DATA
    add     x14, x11, x12
    addi    x11, x12, 0
    PAD_DATA
    addi    x12, x14, 0
    addi    x13, x13, -1
    PAD_DATA
    bne     x13, x0, .Lloop
    PAD_JUMP
    // 循环结束：x11 = fib(46)，x12 = fib(47)
    CHECK   x12, 0xb11924e1, 8
    CHECK   x11, 1836311903, 9
TEST_END

// fib(n)：n < 2 时返回 n，否则返回 fib(n-1) + fib(n-2)
fib:
    PAD_DATA
    slti    x5, x10, 2
    PAD_DATA
    beq     x5, x0, .Lrecurse
    PAD_JUMP
    jalr    x0, 0(x1)
    PAD_JUMP
.Lrecurse:
    addi    sp, sp, -16
    PAD_DATA
    sw      x1, 12(sp)
    sw      x8, 8(sp)
    sw      x10, 4(sp)
    addi    x10, x10, -1
    PAD_DATA
    jal     x1, fib                     // fib(n-1)
    PAD_JUMP
    addi    x8, x10, 0
    lw      x10, 4(sp)
    PAD_DATA
    addi    x10, x10, -2
    PAD_DATA
    jal     x1, fib                     // fib(n-2)
    PAD_JUMP
    add     x10, x10, x8
    lw      x1, 12(sp)
    lw      x8, 8(sp)
    addi    sp, sp, 16
    PAD_DATA
    jalr    x0, 0(x1)
    PAD_JUMP
