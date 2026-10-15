/*
 * 测试程序公共宏。每个测试的骨架：
 *
 *     #include "test.h"
 *     TEST_BEGIN
 *         ...                         // 测试代码
 *         CHECK  x5, 0x80000000, 1    // x5 不等于期望值就以 FINISH 1 结束
 *     TEST_END                        // 全部通过：FINISH 0
 *
 * 这些宏只用 base9 指令（add slt sltu ori lui lw sw beq jal），
 * 所以 base9 和更大的子集都能用。
 *
 * 约定：
 *   - x30（t5）、x31（t6）归宏使用，测试代码不要在里面放要保留的值。
 *   - x2（sp）在 TEST_BEGIN 里设为栈顶 0x0001_1000。
 *   - 失败码 1..2047，同一个测试里每个检查用不同的码，这样从码值就能
 *     定位是哪一项错了。0xbad00000 表示失败码本身没构造出来（见 TEST_END）。
 *   - 宏内部已按 pad 变体的要求放好填充；但宏和前后测试代码之间的依赖
 *     由测试代码自己负责（比如 LI 之后马上用这个寄存器，要先 PAD_DATA）。
 *   - 汇编源文件用 // 或 C 风格的块注释：.S 先过 C 预处理器，
 *     行首的 # 会被当成预处理指令。
 */
#ifndef MINICPU_TEST_H
#define MINICPU_TEST_H

#include "io.h"
#include "pad.h"

/* ------------------------------------------------------------------
 * LI rd, value [, tmp]：把 32 位常数装进 rd，只用 base9 指令。
 *
 * ori 的立即数是符号扩展的：立即数第 11 位为 1 时，ori 会把高 20 位
 * 全部置 1。所以分几种情况：
 *   0 .. 0x7ff                ori  rd, x0, value
 *   0xfffff800 .. 0xffffffff  ori  rd, x0, value（负立即数，正好符号扩展）
 *   低 12 位为 0              lui  rd, value >> 12
 *   低 12 位的第 11 位为 0    lui  rd, hi ; ori rd, rd, lo
 *   其余                      lui  rd, hi + 1 ; ori tmp, x0, lo - 4096 ;
 *                             add  rd, rd, tmp      （需要临时寄存器 tmp）
 * value 必须是汇编时就能算出的常数。
 * ------------------------------------------------------------------ */
.macro LI rd, value, tmp
    .if ((\value) & 0xfffff800) == 0
        ori     \rd, x0, (\value) & 0x7ff
    .elseif ((\value) & 0xfffff800) == 0xfffff800
        ori     \rd, x0, ((\value) & 0xfff) - 0x1000
    .elseif ((\value) & 0xfff) == 0
        lui     \rd, ((\value) >> 12) & 0xfffff
    .elseif ((\value) & 0x800) == 0
        lui     \rd, ((\value) >> 12) & 0xfffff
        PAD_DATA
        ori     \rd, \rd, (\value) & 0x7ff
    .else
        .ifb \tmp
            .error "LI: this value needs a scratch register: LI rd, value, tmp"
            .exitm
        .endif
        lui     \rd, (((\value) + 0x800) >> 12) & 0xfffff
        ori     \tmp, x0, ((\value) & 0xfff) - 0x1000
        PAD_DATA
        add     \rd, \rd, \tmp
    .endif
.endm

/* ------------------------------------------------------------------
 * LA rd, label：把标号的地址装进 rd，只用 base9 指令。
 *
 * 地址由链接器写进 .rodata 里的一个字，再用 lui + lw 读出来。
 * 不用 lui + ori 拼地址，因为 %lo 是按加法（符号扩展）算的，和 ori 不配。
 * ------------------------------------------------------------------ */
.macro LA rd, label
    .pushsection .rodata
    .balign 4
.Laddress\@:
    .word   \label
    .popsection
    lui     \rd, %hi(.Laddress\@)
    PAD_DATA
    lw      \rd, %lo(.Laddress\@)(\rd)
.endm

/* ------------------------------------------------------------------
 * 开头与结尾
 * ------------------------------------------------------------------ */
.macro TEST_BEGIN
    .section .text.init, "ax", @progbits
    .globl _start
_start:
    lui     sp, STACK_TOP >> 12
.endm

/* 写 FINISH 0，然后原地循环（参考模型和测试平台在这次写入后就停了）。 */
.macro TEST_PASS
    lui     t6, IO_BASE_HI
    PAD_DATA
    sw      x0, IO_FINISH(t6)
    jal     x0, .
.endm

/* 以失败码 code 结束。 */
.macro TEST_FAIL code
    .if (\code) < 1 || (\code) > 2047
        .error "TEST_FAIL: code must be in 1..2047"
    .endif
    ori     t5, x0, \code
    jal     x0, __test_fail
    PAD_JUMP
.endm

/* 通过时的结尾，后面跟公共的失败出口：把 t5 里的失败码写进 FINISH。
 * 失败码由 TEST_FAIL 用 ori 构造；要是 ori 本身有错，构造出的码可能是 0，
 * 失败就会被当成通过。所以这里先看一眼：t5 为 0 时改写 0xbad00000（用 lui
 * 构造）。 */
.macro TEST_END
    TEST_PASS
__test_fail:
    lui     t6, IO_BASE_HI
    beq     t5, x0, __test_fail_zero
    PAD_JUMP
    sw      t5, IO_FINISH(t6)
    jal     x0, .
__test_fail_zero:
    lui     t5, 0xbad00
    PAD_DATA
    sw      t5, IO_FINISH(t6)
    jal     x0, .
.endm

/* ------------------------------------------------------------------
 * CHECK reg, value, code：reg 不等于 value 就以失败码 code 结束。
 *
 * 期望值由汇编器写进 .rodata，再用 lw 读出来比较，而不是用 lui/ori 现场
 * 构造：这样检查 lui、ori、add 的测试，期望值就不依赖被测指令本身。
 * value 可以是常数，也可以是标号（例如 jal 的返回地址）。
 * ------------------------------------------------------------------ */
.macro CHECK reg, value, code
    .irp scratch, t5, t6, x30, x31
        .ifc \reg, \scratch
            .error "CHECK: t5/t6 are used by the macro itself"
        .endif
    .endr
    .pushsection .rodata
    .balign 4
.Lexpect\@:
    .word   \value
    .popsection
    lui     t6, %hi(.Lexpect\@)
    PAD_DATA
    lw      t5, %lo(.Lexpect\@)(t6)
    PAD_DATA
    beq     \reg, t5, .Lcheck_ok\@
    PAD_JUMP
    TEST_FAIL \code
.Lcheck_ok\@:
.endm

/* ------------------------------------------------------------------
 * 计数器与打点（用 t6 存 I/O 基址）
 * ------------------------------------------------------------------ */

/* READ_COUNTER rd, IO_CYCLE 等：读一个硬件计数器。值在对拍时不比较。 */
.macro READ_COUNTER rd, offset
    lui     t6, IO_BASE_HI
    PAD_DATA
    lw      \rd, \offset(t6)
.endm

/* MARK_POINT id：写 MARK，测试平台打印当时的计数器。id 取 0..2047。 */
.macro MARK_POINT id
    .if (\id) < 0 || (\id) > 2047
        .error "MARK_POINT: id must be in 0..2047"
    .endif
    ori     t5, x0, \id
    lui     t6, IO_BASE_HI
    PAD_DATA
    sw      t5, IO_MARK(t6)
.endm

#endif
