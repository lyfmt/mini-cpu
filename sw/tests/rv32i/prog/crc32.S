// 程序测试：CRC-32（IEEE 802.3，反射形式，多项式 0xedb88320，初值和结果都取反），
// 逐位计算。
//
// 只有 lw，所以按字读出再用 srl/andi 取出第 i 个字节（小端）。期望值由一段
// 独立的 Python（zlib.crc32）算出：
//   "123456789"                                    0xcbf43926（CRC-32 的标准校验值）
//   "The quick brown fox jumps over the lazy dog"  0x414fa339
//   64 字节 (7i + 3) mod 256                        0xcbd9ecf0
//   空串                                            0x00000000
//
// crc32 子程序：x13 = 数据地址，x12 = 字节数；返回 x10；用到 x11、x14..x19。
//
// 失败码：1..4 依次对应上面四个数据
#include "test.h"

    .data
    .balign 4
msg_check:
    .ascii  "123456789"
    .balign 4
msg_fox:
    .ascii  "The quick brown fox jumps over the lazy dog"
    .balign 4
msg_pattern:
    .set    k, 0
    .rept   64
    .byte   (k * 7 + 3) & 0xff
    .set    k, k + 1
    .endr

.macro CRC data, len, expect, code
    LA      x13, \data
    LI      x12, \len
    PAD_DATA
    jal     x1, crc32
    PAD_JUMP
    CHECK   x10, \expect, \code
.endm

TEST_BEGIN
    CRC     msg_check, 9, 0xcbf43926, 1
    CRC     msg_fox, 43, 0x414fa339, 2
    CRC     msg_pattern, 64, 0xcbd9ecf0, 3
    CRC     msg_check, 0, 0x00000000, 4
TEST_END

crc32:
    LI      x14, 0xedb88320, x15
    addi    x10, x0, -1                 // crc = 0xffffffff
    addi    x11, x0, 0                  // i
.Lbyte:
    PAD_DATA
    beq     x11, x12, .Ldone
    PAD_JUMP
    andi    x15, x11, -4
    andi    x17, x11, 3
    PAD_DATA
    add     x15, x15, x13
    slli    x17, x17, 3
    PAD_DATA
    lw      x16, 0(x15)
    PAD_DATA
    srl     x16, x16, x17
    PAD_DATA
    andi    x16, x16, 0xff
    PAD_DATA
    xor     x10, x10, x16
    addi    x18, x0, 8
.Lbit:
    PAD_DATA
    andi    x19, x10, 1
    srli    x10, x10, 1
    PAD_DATA
    beq     x19, x0, .Lnoxor
    PAD_JUMP
    xor     x10, x10, x14
.Lnoxor:
    addi    x18, x18, -1
    PAD_DATA
    bne     x18, x0, .Lbit
    PAD_JUMP
    addi    x11, x11, 1
    jal     x0, .Lbyte
    PAD_JUMP
.Ldone:
    xori    x10, x10, -1
    jalr    x0, 0(x1)
    PAD_JUMP
