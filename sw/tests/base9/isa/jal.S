// jal rd, offset：rd <- PC + 4；PC <- PC + 符号扩展(offset)
//
// 返回地址的期望值：第一项按地址手工算出（jal 在 0x4，紧跟 TEST_BEGIN 的
// 一条 lui），其余用紧跟在 jal 后面的标号，由汇编器给出 jal 的地址 + 4。
//
// 失败码：
//   1  jal x1 位于 0x4，x1 = 0x00000008
//   2  jal 之后的指令被执行了（应该跳过）
//   3  jal x7 的返回地址；x7 原来是 0xffffffff，被覆盖
//   4  jal 之后的指令被执行了
//   5  jal x0 不写寄存器，x0 仍为 0
//   6  jal x0 之后的指令被执行了
//   7..9  向后跳的路径走错了
//  10  向后跳的目标块里的标记
//  11  向后跳的 jal x9 的返回地址
//  12..14  远距离跳转的路径走错了
//  15  远距离向前跳（偏移 > 2 KB，用到 J 型立即数的第 11 位 inst[20]）的返回地址
//  16  远距离向后跳的目标块里的标记
//  17  远距离向后跳（负偏移，inst[19:12] 和 inst[31] 全为 1）的返回地址
#include "test.h"

TEST_BEGIN
    jal     x1, .Lt1            // 地址 0x4
.Lr1:
    PAD_JUMP
    TEST_FAIL 2
.Lt1:
    CHECK   x1, 0x00000008, 1

    LI      x7, -1
    PAD_DATA
    jal     x7, .Lt2
.Lr2:
    PAD_JUMP
    TEST_FAIL 4
.Lt2:
    CHECK   x7, .Lr2, 3

    jal     x0, .Lt3
    PAD_JUMP
    TEST_FAIL 6
.Lt3:
    CHECK   x0, 0, 5

    // 短距离向后跳
    jal     x0, .Lfwd4
    PAD_JUMP
    TEST_FAIL 7
.Lback4:
    ori     x8, x0, 0x44
    jal     x0, .Ldone4
    PAD_JUMP
    TEST_FAIL 8
.Lfwd4:
    jal     x9, .Lback4
.Lr4:
    PAD_JUMP
    TEST_FAIL 9
.Ldone4:
    CHECK   x8, 0x44, 10
    CHECK   x9, .Lr4, 11

    // 远距离：中间隔着 520 条不会执行的空指令（2080 字节）
    jal     x29, .Lfar_fwd
.Lr5:
    PAD_JUMP
    TEST_FAIL 12
.Lfar_back:
    ori     x10, x0, 0x55
    jal     x0, .Lfar_done
    PAD_JUMP
    TEST_FAIL 13
    .rept   520
    NOP0
    .endr
.Lfar_fwd:
    jal     x11, .Lfar_back
.Lr6:
    PAD_JUMP
    TEST_FAIL 14
.Lfar_done:
    CHECK   x29, .Lr5, 15
    CHECK   x10, 0x55, 16
    CHECK   x11, .Lr6, 17
TEST_END
