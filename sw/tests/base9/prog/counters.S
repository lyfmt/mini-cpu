// 程序测试：读硬件计数器、写 MARK。
//
// 读 CYCLE/INSTRET/STALLS/FLUSHES 的 load 在期望轨迹里是 X 行（只比 pc 和 rd，
// 不比值）。按实现约定第 3 节，读数不存进存储器、不写给 MARK/FINISH、不参与
// 分支，也不参与任何运算；读进来的寄存器随后被覆盖。两次 MARK 之间是一个
// 10 次的循环，测试平台打印的两行计数器快照之差就是这段代码的开销。
//
// 失败码：
//   1  循环执行了 10 次
//   2  读计数器的寄存器随后被正常覆盖（读数不影响后面的指令）
#include "test.h"

TEST_BEGIN
    READ_COUNTER x1, IO_CYCLE
    READ_COUNTER x2, IO_INSTRET
    MARK_POINT 1

    LI      x5, 0
    LI      x6, 1
    LI      x7, 10
    PAD_DATA
.Lloop:
    add     x5, x5, x6
    PAD_DATA
    slt     x8, x5, x7
    PAD_DATA
    beq     x8, x6, .Lloop
    PAD_JUMP

    MARK_POINT 2
    READ_COUNTER x3, IO_CYCLE
    READ_COUNTER x4, IO_INSTRET
    READ_COUNTER x9, IO_STALLS
    READ_COUNTER x10, IO_FLUSHES
    PAD_DATA
    // 覆盖所有读过计数器的寄存器
    LI      x1, 0x11
    LI      x2, 0x22
    LI      x3, 0x33
    LI      x4, 0x44
    LI      x9, 0x99
    LI      x10, 0x100
    PAD_DATA

    CHECK   x5, 10, 1
    CHECK   x4, 0x44, 2
    CHECK   x10, 0x100, 2
TEST_END
