// sw rs2, imm(rs1)：Mem[rs1 + 符号扩展(imm12)] <- rs2
//
// 缓冲区 buf 共 2048 字节：A = buf，B = buf_end = A + 2048，初值见 .data。
// 写进去再用 lw 读回来检查；对拍时 M 事件还会逐条核对地址和数据。
//
// 失败码：
//   1  sw 0(A)       写 0x12345678，读回
//   2  sw 4(A)       写 0x80000001，读回
//   3  A+8 没被旁边的写动过，仍是 0xa2a2a2a2
//   4  A+0 没被写 A+4 动过，仍是 0x12345678
//   5  sw 2044(A)    写 0xdeadbeef（最大正偏移），从 -4(B) 读回
//   6  sw -2048(B)   写 0x80000001（最小负偏移），从 0(A) 读回
//   7  sw -2040(B)   写 0xdeadbeef 到 A+8，读回
//   8  A+12 仍是 0xa3a3a3a3
//   9  sw x0, 12(A)  写入 0
//  10  同一地址连写两次，后一次生效：0xdeadbeef
//  11  rs2 = rs1：sw x1, 16(x1) 写入的是地址本身
#include "test.h"

    .data
    .balign 4
buf:
    .word   0xa0a0a0a0          // A + 0
    .word   0xa1a1a1a1          // A + 4
    .word   0xa2a2a2a2          // A + 8
    .word   0xa3a3a3a3          // A + 12
    .word   0xa4a4a4a4          // A + 16
    .skip   2044 - 20
    .word   0xafafafaf          // A + 2044
buf_end:

TEST_BEGIN
    LA      x1, buf
    LA      x2, buf_end
    LI      x3, 0x12345678
    LI      x4, 0x80000001
    LI      x5, 0xdeadbeef, x20
    PAD_DATA

    sw      x3, 0(x1)
    lw      x10, 0(x1)
    sw      x4, 4(x1)
    lw      x11, 4(x1)
    lw      x12, 8(x1)
    lw      x13, 0(x1)
    sw      x5, 2044(x1)
    lw      x14, -4(x2)
    sw      x4, -2048(x2)
    lw      x15, 0(x1)
    sw      x5, -2040(x2)
    lw      x16, 8(x1)
    lw      x17, 12(x1)
    sw      x0, 12(x1)
    lw      x18, 12(x1)
    sw      x3, 4(x1)
    sw      x5, 4(x1)
    lw      x19, 4(x1)
    sw      x1, 16(x1)
    lw      x21, 16(x1)

    CHECK   x10, 0x12345678, 1
    CHECK   x11, 0x80000001, 2
    CHECK   x12, 0xa2a2a2a2, 3
    CHECK   x13, 0x12345678, 4
    CHECK   x14, 0xdeadbeef, 5
    CHECK   x15, 0x80000001, 6
    CHECK   x16, 0xdeadbeef, 7
    CHECK   x17, 0xa3a3a3a3, 8
    CHECK   x18, 0, 9
    CHECK   x19, 0xdeadbeef, 10
    CHECK   x21, buf, 11
TEST_END
