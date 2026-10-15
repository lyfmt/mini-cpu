// 冒险场景：函数调用的返回路径。jal 调用、jalr 返回，返回地址寄存器和返回值
// 在跳转前后马上被使用（第五节表"跳转成立""jalr 依赖 load""相邻依赖"在
// 调用约定里的组合）。
//
// nopad 变体里的关键相邻关系：
//   1  jal x1, leaf ; leaf: jalr x0, 0(x1)           函数第一条就用 jal 刚写的 x1 返回
//   2  jal x1, f ; f: sw x1, 12(sp)                  函数入口马上存返回地址（store 数据）
//      f 里 jal x1, g 嵌套调用，返回后 lw x1, 12(sp) ; jalr x0, 0(x1)
//                                                    恢复返回地址后紧跟 jalr（load-use 停顿）
//   3  g: addi x10, x10, 1 ; jalr x0, 0(x1)          返回值算出来马上返回，
//      调用者返回后：add x12, x10, x10               调用者马上用返回值
//   4  jal x1, leaf ; addi x13, x1, 0                调用者返回后马上读 x1
//   5  jal x5, leaf5 ; leaf5: addi x5, x5, 0 ; jalr x0, 0(x5)
//                                                    用 x5 作返回地址寄存器，
//                                                    先自己写一遍再返回（距离 1 转发）
//
// 失败码：
//   1  x20 = 1：leaf 返回后继续执行到这里（返回地址正确）
//   2  f 存进栈里的返回地址 = .Lr2
//   3  x12 = (0x40 + 1) * 2 = 0x82：g 的返回值
//   4  x13 = .Lr4（第 4 组 jal 的返回地址）
//   5  x21 = 5：经过 leaf5 后继续执行
//   6  sp 恢复为 0x11000
//   7  f 返回后 x10 = 0x41
#include "test.h"

TEST_BEGIN
    LI      x10, 0x40
    LI      x20, 0
    LI      x21, 0
    LI      x22, 1
    LI      x23, 5
    // 计数器（nopad，MARK 1-2 之间）：调用与返回 10 次（含 f 里调用 g）；中间 4 个 CHECK 各停 1 拍、成立 1 次
    // PERF 1-2: stalls=4 flushes=14
    PERF_MARK 1

    // 1
    jal     x1, leaf
    PAD_JUMP
    add     x20, x20, x22
    SEP

    // 2、3
    jal     x1, f
.Lr2:
    PAD_JUMP
    add     x12, x10, x10
    SEP
    CHECK   x12, 0x82, 3
    CHECK   x10, 0x41, 7
    lw      x14, -4(sp)
    PAD_DATA
    CHECK   x14, .Lr2, 2
    SEP

    // 4
    jal     x1, leaf
.Lr4:
    PAD_JUMP
    PAD_DATA
    addi    x13, x1, 0
    SEP
    CHECK   x13, .Lr4, 4
    SEP

    // 5
    jal     x5, leaf5
    PAD_JUMP
    add     x21, x21, x23
    PERF_MARK 2

    CHECK   x20, 1, 1
    CHECK   x21, 5, 5
    CHECK   sp, 0x11000, 6
TEST_END

// 叶子函数：第一条就返回
leaf:
    PAD_DATA
    jalr    x0, 0(x1)
    PAD_JUMP

// 用 x5 返回的叶子函数
leaf5:
    PAD_DATA
    addi    x5, x5, 0
    PAD_DATA
    jalr    x0, 0(x5)
    PAD_JUMP

// 非叶子函数：保存返回地址，调用 g，恢复后返回
f:
    PAD_DATA
    sw      x1, -4(sp)
    addi    sp, sp, -16
    PAD_DATA
    sw      x1, 12(sp)
    jal     x1, g
    PAD_JUMP
    lw      x1, 12(sp)
    addi    sp, sp, 16
    PAD_DATA
    jalr    x0, 0(x1)
    PAD_JUMP

g:
    addi    x10, x10, 1
    PAD_DATA
    jalr    x0, 0(x1)
    PAD_JUMP
