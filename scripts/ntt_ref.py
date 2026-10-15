#!/usr/bin/env python3
"""Kyber（ML-KEM）正向 NTT 的参考实现，以及 NTT 评估程序的数据文件生成（设计文档第七节）。

    python3 scripts/ntt_ref.py [-n N] [-o sw/ntt/ntt_data.S]

做三件事：
  1. 检查 ζ 表：17 是模 q 的 256 次本原单位根，ζ[i] = 17^BitRev7(i) mod q；
  2. 交叉验证：对 N 个随机多项式（默认 200），按 FIPS 203 算法 9 算出的 NTT，
     与按数学定义算出的结果逐项比较。数学定义：输出的第 i 对
     (f̂[2i], f̂[2i+1]) 等于 f 对 (X² − ζ^(2·BitRev7(i)+1)) 取模所得的一次多项式；
  3. 给出 -o 时，生成汇编数据文件：ζ 表、确定的伪随机输入多项式、期望输出。

数据全部放在 .data 段，链接进数据存储器（设计文档第八节"常量表的位置"）。
系数按 32 位字存放，因为 CPU 只有 lw/sw。

只用 Python 标准库。
"""

import argparse
import random
import sys

Q = 3329
N = 256
ROOT = 17                  # 模 q 的 256 次本原单位根
SEED = 0x4b594245          # 输入多项式的种子（"KYBE"）


def bitrev7(i):
    return int(format(i, '07b')[::-1], 2)


# ζ[i] = 17^BitRev7(i) mod q，i = 0..127。NTT 只用到 ζ[1..127]，ζ[0] = 1 不用。
ZETAS = [pow(ROOT, bitrev7(i), Q) for i in range(128)]


def ntt(f):
    """FIPS 203 算法 9：7 层，每层 128 次蝴蝶。返回新列表，系数在 [0, q)。

    评估程序的汇编按同样的循环结构写：len 从 128 减半到 2，每组取下一个 ζ。
    """
    f = list(f)
    i = 1
    length = 128
    while length >= 2:
        for start in range(0, N, 2 * length):
            zeta = ZETAS[i]
            i += 1
            for j in range(start, start + length):
                t = zeta * f[j + length] % Q
                f[j + length] = (f[j] - t) % Q
                f[j] = (f[j] + t) % Q
        length //= 2
    return f


def ntt_by_definition(f):
    """按数学定义：第 i 对输出是 f mod (X² − γ_i)，γ_i = ζ^(2·BitRev7(i)+1)。

    X² ≡ γ 时，Σ f_k X^k = Σ f_{2m} γ^m + X · Σ f_{2m+1} γ^m。
    """
    out = []
    for i in range(N // 2):
        gamma = pow(ROOT, 2 * bitrev7(i) + 1, Q)
        even = odd = 0
        power = 1
        for m in range(N // 2):
            even = (even + f[2 * m] * power) % Q
            odd = (odd + f[2 * m + 1] * power) % Q
            power = power * gamma % Q
        out += [even, odd]
    return out


def butterflies():
    """数一下蝴蝶次数，核对"7 层 × 128 = 896"。"""
    count, length = 0, 128
    while length >= 2:
        count += N // 2
        length //= 2
    return count


def input_poly():
    """确定的伪随机输入：xorshift32 每次取 12 位，小于 q 的留下（与 Kyber 的拒绝采样同理）。

    自己写生成器而不用 random 模块，保证不同 Python 版本生成同样的数据。
    """
    x = SEED
    coeffs = []
    while len(coeffs) < N:
        x ^= (x << 13) & 0xFFFFFFFF
        x ^= x >> 17
        x ^= (x << 5) & 0xFFFFFFFF
        for v in (x & 0xFFF, (x >> 12) & 0xFFF):
            if v < Q and len(coeffs) < N:
                coeffs.append(v)
    return coeffs


def self_check(count):
    """返回错误信息列表；空表示全部通过。"""
    errors = []
    if pow(ROOT, 128, Q) != Q - 1 or pow(ROOT, 256, Q) != 1:
        errors.append('17 is not a primitive 256th root of unity mod %d' % Q)
    if len(set(ZETAS)) != 128:
        errors.append('zeta table has repeated entries')
    if butterflies() != 896:
        errors.append('butterfly count %d != 896' % butterflies())

    rng = random.Random(1)
    cases = [[0] * N, [1] + [0] * (N - 1), [Q - 1] * N, input_poly()]
    cases += [[rng.randrange(Q) for _ in range(N)] for _ in range(count)]
    for k, f in enumerate(cases):
        a, b = ntt(f), ntt_by_definition(f)
        if a != b:
            first = next(i for i in range(N) if a[i] != b[i])
            errors.append('case %d: ntt[%d] = %d, by definition %d' % (k, first, a[first], b[first]))
    return errors, len(cases)


def words(label, values, comment):
    lines = ['', '// %s' % comment, '    .balign 4', '%s:' % label]
    for k in range(0, len(values), 8):
        lines.append('    .word   ' + ', '.join('%4d' % v for v in values[k:k + 8]))
    return lines


def data_file():
    f = input_poly()
    expect = ntt(f)
    lines = [
        '// NTT 评估程序的数据（Kyber，q = 3329，n = 256）。',
        '//',
        '// 由 scripts/ntt_ref.py 生成，不要手改。重新生成：',
        '//     python3 scripts/ntt_ref.py -o sw/ntt/ntt_data.S',
        '//',
        '// 全部放在 .data 段，链接进数据存储器。系数和 ζ 都按 32 位字存放。',
        '//   ntt_zetas   128 个字，ζ[i] = 17^BitRev7(i) mod q；NTT 依次用 ζ[1..127]',
        '//   ntt_poly    256 个字，输入多项式（xorshift32 拒绝采样，种子 0x%08x）；' % SEED,
        '//               NTT 在这里原地计算',
        '//   ntt_expect  256 个字，ntt_poly 的 NTT（FIPS 203 算法 9）',
        '',
        '    .pushsection .data',
    ]
    lines += words('ntt_zetas', ZETAS, 'ζ 表')
    lines += words('ntt_poly', f, '输入多项式，系数在 [0, q)')
    lines += words('ntt_expect', expect, '期望输出')
    lines += ['', '    .popsection', '']
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description='Kyber forward NTT reference and data generator')
    parser.add_argument('-n', type=int, default=200,
                        help='random polynomials for the cross-check (default 200)')
    parser.add_argument('-o', '--output', help='write the assembly data file here')
    args = parser.parse_args()

    errors, cases = self_check(args.n)
    for e in errors:
        print('FAIL: ' + e)
    if errors:
        return 1
    print('ntt_ref: zeta table ok; %d butterflies; NTT == definition on %d polynomials'
          % (butterflies(), cases))
    if args.output:
        with open(args.output, 'w', newline='\n') as f:
            f.write(data_file())
        print('wrote %s' % args.output)
    return 0


if __name__ == '__main__':
    sys.exit(main())
