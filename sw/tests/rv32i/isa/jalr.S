// rv32i 单指令测试：jalr。按规范：rd = pc + 4；pc = (rs1 + imm) & ~1。
//
// 目标地址用 LA 装进寄存器（标号加偏移由汇编器算出）。每个跳转后面紧跟
// TEST_FAIL：没跳、或者跳到下一条，都会失败。
//
// 失败码：
//   1  返回地址 rd = jalr 的地址 + 4
//   2  rs1 + 0 为奇数：最低位清零后落在目标上；目标处 auipc 读出的 pc 是偶数
//   3  偏移 1 使 rs1 + imm 为奇数（rs1 是目标地址）
//   4  rs1 = 目标 - 2，偏移 3：和为目标 + 1，清零后是目标
//   5  负偏移：rs1 = 目标 + 16，偏移 -16
//   6  负偏移下限：rs1 = 目标 + 2048，偏移 -2048
//   7  正偏移上限：rs1 = 目标 - 2047，偏移 2047
//   8  rd = rs1：目标用的是旧的 rs1（跳到了下一条就是用了新值）
//   9  rd = rs1 时 rd 写入返回地址
//  10  rd = rs1 加偏移
//  11  rd = x0：跳转照常，x0 仍为 0，rs1 不变
//  12  向后跳：两次 jal 调用子程序、jalr 返回，子程序执行两次
//  13  第 2 项的返回地址
//  其他码：在对应目标前面的 TEST_FAIL（没有跳或跳错）
#include "test.h"

TEST_BEGIN
    // 1：返回地址
    LA      x5, .Lt1
    PAD_DATA
.Lj1:
    jalr    x1, 0(x5)
    PAD_JUMP
    TEST_FAIL 101
.Lt1:
    CHECK   x1, .Lj1 + 4, 1

    // 2：rs1 为奇数
    LA      x5, .Lt2+1
    PAD_DATA
.Lj2:
    jalr    x1, 0(x5)
    PAD_JUMP
    TEST_FAIL 102
.Lt2:
    auipc   x11, 0
    PAD_DATA
    CHECK   x11, .Lt2, 2
    CHECK   x1, .Lj2 + 4, 13

    // 3：偏移为奇数
    LA      x5, .Lt3
    PAD_DATA
    jalr    x0, 1(x5)
    PAD_JUMP
    TEST_FAIL 103
.Lt3:
    auipc   x11, 0
    PAD_DATA
    CHECK   x11, .Lt3, 3

    // 4：和为奇数
    LA      x5, .Lt4-2
    PAD_DATA
    jalr    x0, 3(x5)
    PAD_JUMP
    TEST_FAIL 104
.Lt4:
    auipc   x11, 0
    PAD_DATA
    CHECK   x11, .Lt4, 4

    // 5：负偏移
    LA      x5, .Lt5+16
    PAD_DATA
    jalr    x0, -16(x5)
    PAD_JUMP
    TEST_FAIL 105
.Lt5:
    auipc   x11, 0
    PAD_DATA
    CHECK   x11, .Lt5, 5

    // 6：偏移 -2048
    LA      x5, .Lt6+2048
    PAD_DATA
    jalr    x0, -2048(x5)
    PAD_JUMP
    TEST_FAIL 106
.Lt6:
    auipc   x11, 0
    PAD_DATA
    CHECK   x11, .Lt6, 6

    // 7：偏移 2047（rs1 = 目标 - 2047，和是目标本身）
    LA      x5, .Lt7-2047
    PAD_DATA
    jalr    x0, 2047(x5)
    PAD_JUMP
    TEST_FAIL 107
.Lt7:
    auipc   x11, 0
    PAD_DATA
    CHECK   x11, .Lt7, 7

    // 8、9：rd = rs1
    LA      x5, .Lt8
    PAD_DATA
.Lj8:
    jalr    x5, 0(x5)
    PAD_JUMP
    TEST_FAIL 8
.Lt8:
    CHECK   x5, .Lj8 + 4, 9

    // 10：rd = rs1，带偏移
    LA      x6, .Lt10-8
    PAD_DATA
.Lj10:
    jalr    x6, 8(x6)
    PAD_JUMP
    TEST_FAIL 110
.Lt10:
    CHECK   x6, .Lj10 + 4, 10

    // 11：rd = x0
    LA      x5, .Lt11
    PAD_DATA
    jalr    x0, 0(x5)
    PAD_JUMP
    TEST_FAIL 111
.Lt11:
    CHECK   x0, 0, 11
    CHECK   x5, .Lt11, 11

    // 12：向后跳（子程序返回）
    LI      x12, 0
    PAD_DATA
    jal     x1, .Lsub
    PAD_JUMP
    jal     x1, .Lsub
    PAD_JUMP
    CHECK   x12, 2, 12
TEST_END

// 子程序在 TEST_END 后面，返回是向后跳
.Lsub:
    addi    x12, x12, 1
    PAD_DATA
    jalr    x0, 0(x1)
    PAD_JUMP
