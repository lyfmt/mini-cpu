/*
 * Kyber 正向 NTT 的汇编主体（设计文档第七节），两个评估程序共用。
 *
 * 包含它的测试先定义汇编宏
 *
 *     MODMUL rd, rs1, rs2        rd <- rs1 · rs2 mod q，rs1、rs2 在 [0, q)
 *
 * 再 #include 本文件。这是两个版本唯一的差异点：
 *   sw/tests/rv32i/ntt/ntt_sw.S         调用软件模乘子程序
 *   sw/tests/rv32i_qmul/ntt/ntt_qmul.S  一条 qmul
 * 本文件固定用 MODMUL a2, s5, a1；MODMUL 可以改写 a0、a1、a3、ra，
 * 但不能动下面列出的其他寄存器。
 *
 * 算法与 scripts/ntt_ref.py 的 ntt() 相同（FIPS 203 算法 9）：
 *
 *     i = 1
 *     for len = 128, 64, ..., 2:
 *         for start = 0, 2·len, ... < 256:
 *             ζ = zetas[i++]
 *             for j = start .. start+len−1:
 *                 t        = ζ · f[j+len] mod q      MODMUL
 *                 f[j+len] = f[j] − t mod q          模减，5 条
 *                 f[j]     = f[j] + t mod q          模加，5 条
 *
 * 7 层 × 128 = 896 次蝴蝶。模加、模减不用分支（设计文档"为什么只做模乘"）：
 *   模加  add；sltu 判断和 < q；addi −1 变成掩码（和 ≥ q 时全 1）；and q；sub
 *   模减  sub；slt 判断差 < 0；取负变成掩码（为负时全 1）；and q；add
 *
 * 数据（sw/ntt/ntt_data.S，由 scripts/ntt_ref.py 生成）在数据存储器里：
 * NTT 在 ntt_poly 上原地计算，算完与 ntt_expect 逐项比较。
 * NTT 前后各写一次 MARK（1 和 2），测试平台据此打印计数器快照。
 *
 * 失败码：k + 1（1..256）表示第一处不等的是第 k 个系数。
 *
 * 寄存器：
 *   s0  f 的基址            s5  ζ               t0  &f[j+len]
 *   s1  指向下一个 ζ        s6  &f[j]           t1  a = f[j]
 *   s2  len × 4（字节）     s7  &f[start+len]   t2、t3  模加、模减的临时值
 *   s3  &f[start]           s8  q               a1  b = f[j+len]
 *   s4  &f[256]             s9  4（len = 1 时结束）  a2  t = ζ·b mod q
 */
#define NTT_Q 3329

TEST_BEGIN
    LA      s0, ntt_poly
    LA      s1, ntt_zetas
    LI      s8, NTT_Q, t2
    LI      s9, 4
    PAD_DATA
    addi    s1, s1, 4               // ζ[0] 不用
    addi    s4, s0, 1024

    MARK_POINT 1

    addi    s2, x0, 512             // len = 128
.Llayer:
    addi    s3, s0, 0               // start = 0
    PAD_DATA
.Lgroup:
    addi    s6, s3, 0               // j = start
    add     s7, s3, s2              // j 的终点 start + len
    lw      s5, 0(s1)               // ζ = zetas[i++]
    addi    s1, s1, 4
.Lbfly:
    add     t0, s6, s2
    PAD_DATA
    lw      a1, 0(t0)               // b = f[j+len]
    lw      t1, 0(s6)               // a = f[j]
    PAD_DATA
    MODMUL  a2, s5, a1              // t = ζ·b mod q
    PAD_DATA

    // f[j+len] = a − t mod q
    sub     t2, t1, a2
    PAD_DATA
    slt     t3, t2, x0
    PAD_DATA
    sub     t3, x0, t3
    PAD_DATA
    and     t3, t3, s8
    PAD_DATA
    add     t2, t2, t3
    PAD_DATA
    sw      t2, 0(t0)

    // f[j] = a + t mod q
    add     t2, t1, a2
    PAD_DATA
    sltu    t3, t2, s8
    PAD_DATA
    addi    t3, t3, -1
    PAD_DATA
    and     t3, t3, s8
    PAD_DATA
    sub     t2, t2, t3
    PAD_DATA
    sw      t2, 0(s6)

    addi    s6, s6, 4
    PAD_DATA
    bne     s6, s7, .Lbfly
    PAD_JUMP

    add     s3, s7, s2              // start += 2·len
    PAD_DATA
    bne     s3, s4, .Lgroup
    PAD_JUMP

    srli    s2, s2, 1               // len /= 2
    PAD_DATA
    bne     s2, s9, .Llayer
    PAD_JUMP

    MARK_POINT 2

    // 与期望输出逐项比较；t0 = k + 1，既是循环计数也是失败码
    LA      s1, ntt_expect
    addi    t0, x0, 1
    addi    s7, x0, 257
.Lcompare:
    lw      t1, 0(s0)
    lw      t2, 0(s1)
    PAD_DATA
    bne     t1, t2, .Lmismatch
    PAD_JUMP
    addi    s0, s0, 4
    addi    s1, s1, 4
    addi    t0, t0, 1
    PAD_DATA
    bne     t0, s7, .Lcompare
    PAD_JUMP
TEST_END

.Lmismatch:
    addi    t5, t0, 0               // 交给 TEST_END 的失败出口写进 FINISH
    jal     x0, __test_fail
    PAD_JUMP

#include "ntt_data.S"
