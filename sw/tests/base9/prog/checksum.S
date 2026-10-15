// 程序测试：对一张 16 个字的表做校验和，并统计负数个数、求有符号最大值。
//
//   s1 = s1 + w ;  s2 = s2 + s1      （类似 Fletcher，模 2^32）
//   neg = neg + (w < 0)
//   max = (max < w) ? w : max        （有符号）
//
// 期望值按上面的定义对表中数据手工算出（不来自参考模型）：
//   s1 = 0x567c6dae，s2 = 0xafc8e191，neg = 8，max = 0x7fffffff
//
// 失败码：
//   1  s1
//   2  s2
//   3  neg
//   4  max
//   5  写进存储器的 s1 读回
//   6  写进存储器的 s2 读回
#include "test.h"

    .data
    .balign 4
table:
    .word   0x00000001, 0x80000000, 0xffffffff, 0x12345678
    .word   0x9abcdef0, 0x0000ffff, 0xffff0000, 0x7fffffff
    .word   0x00000000, 0xdeadbeef, 0xcafebabe, 0x01020304
    .word   0xa5a5a5a5, 0x5a5a5a5a, 0x00000100, 0xfedcba98
table_end:
result:
    .word   0, 0

TEST_BEGIN
    LA      x1, table           // 指针
    LA      x2, table_end
    LI      x3, 4
    LI      x4, 0               // s1
    LI      x5, 0               // s2
    LI      x6, 0               // neg
    LI      x8, 0x80000000      // max，从最小的负数开始
    LA      x12, result
    PAD_DATA
.Lloop:
    beq     x1, x2, .Ldone
    PAD_JUMP
    lw      x9, 0(x1)
    add     x1, x1, x3
    PAD_DATA
    add     x4, x4, x9
    slt     x10, x9, x0
    PAD_DATA
    add     x5, x5, x4
    add     x6, x6, x10
    slt     x11, x8, x9
    PAD_DATA
    beq     x11, x0, .Lskip
    PAD_JUMP
    add     x8, x9, x0
.Lskip:
    jal     x0, .Lloop
    PAD_JUMP
.Ldone:
    sw      x4, 0(x12)
    sw      x5, 4(x12)
    lw      x13, 0(x12)
    lw      x14, 4(x12)

    CHECK   x4, 0x567c6dae, 1
    CHECK   x5, 0xafc8e191, 2
    CHECK   x6, 8, 3
    CHECK   x8, 0x7fffffff, 4
    CHECK   x13, 0x567c6dae, 5
    CHECK   x14, 0xafc8e191, 6
TEST_END
