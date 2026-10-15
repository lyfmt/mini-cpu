#!/usr/bin/env python3
"""qmul 硬件算法的位级模型与穷举验证（设计文档第七节"模乘的内部结构"）。

    python3 scripts/check_barrett.py [-j N]

硬件算法（a、b 取 rs1、rs2 的低 12 位，按无符号数）：
  1. p    = a × b                    12 位 × 12 位，乘积最多 24 位
  2. qhat = (p × 5039) >> 24         5039 = floor(2^24 / 3329)，Barrett 估算的商
  3. r    = p − qhat × 3329
  4. 结果 = r − q（若 r ≥ q），否则 r

对全部 4096 × 4096 种 (a, b) 穷举，检查：
  - 第 3 步的余数 r 落在 [0, 2q) 内，即第 4 步"最多减一次 q"足够；
  - 最终结果等于 (a·b) mod 3329；
  - 每个乘法的两个操作数都在 Zynq-7000 DSP48E1 乘法器的 25 × 18（有符号）之内，
    即无符号时不超过 24 位 × 17 位（两个操作数可以交换端口）。
并打印各个乘法、各个中间量实际用到的最大值和位宽。

只用 Python 标准库；按 a 分块用多进程并行。
"""

import argparse
import os
import sys
from concurrent.futures import ProcessPoolExecutor

Q = 3329
SHIFT = 24
M = (1 << SHIFT) // Q          # 5039

# DSP48E1：A 口 25 位、B 口 18 位，都是有符号数，所以无符号操作数最多 24 位和 17 位
DSP_A_UNSIGNED = 24
DSP_B_UNSIGNED = 17


def qmul_model(rs1, rs2):
    """位级模型。返回 (结果, 中间量字典)，供 RTL 实现时对照。"""
    a = rs1 & 0xFFF
    b = rs2 & 0xFFF
    p = a * b                              # 乘法 1
    qhat = (p * M) >> SHIFT                # 乘法 2
    r = p - qhat * Q                       # 乘法 3
    result = r - Q if r >= Q else r
    return result, {'a': a, 'b': b, 'p': p, 'qhat': qhat, 'r': r}


def check_rows(a_values):
    """检查 a ∈ a_values、b ∈ [0, 4096) 的全部组合。

    返回 (错误列表, 各中间量最大值, r 的最小值, 需要第 4 步减 q 的组合数)。
    """
    errors = []
    max_p = max_pm = max_qhat = max_r = 0
    min_r = 1 << 30
    need_sub = 0
    for a in a_values:
        for b in range(4096):
            result, v = qmul_model(a, b)
            p, qhat, r = v['p'], v['qhat'], v['r']
            min_r = min(min_r, r)
            max_r = max(max_r, r)
            max_p = max(max_p, p)
            max_pm = max(max_pm, p * M)
            max_qhat = max(max_qhat, qhat)
            if r >= Q:
                need_sub += 1
            if not 0 <= r < 2 * Q or result != (a * b) % Q:
                if len(errors) < 10:
                    errors.append('a=%d b=%d: p=%d qhat=%d r=%d result=%d expected=%d'
                                  % (a, b, p, qhat, r, result, (a * b) % Q))
    return errors, (max_p, max_pm, max_qhat, max_r), min_r, need_sub


def width(value):
    return max(1, value.bit_length())


def main():
    parser = argparse.ArgumentParser(description='exhaustive check of the qmul Barrett reduction')
    parser.add_argument('-j', dest='jobs', type=int, default=os.cpu_count() or 1,
                        help='worker processes (default: number of CPUs)')
    args = parser.parse_args()

    chunks = [range(k, 4096, args.jobs * 4) for k in range(args.jobs * 4)]
    errors, need_sub = [], 0
    max_p = max_pm = max_qhat = max_r = 0
    min_r = 1 << 30
    with ProcessPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        for e, (p, pm, qh, r), rmin, ns in pool.map(check_rows, chunks):
            errors += e
            max_p, max_pm = max(max_p, p), max(max_pm, pm)
            max_qhat, max_r = max(max_qhat, qh), max(max_r, r)
            min_r = min(min_r, rmin)
            need_sub += ns

    total = 4096 * 4096
    print('qmul Barrett reduction: q = %d, M = floor(2^%d / q) = %d, %d inputs checked'
          % (Q, SHIFT, M, total))
    print()
    print('intermediate        max value   bits')
    for name, value in (('p = a*b', max_p), ('p*M', max_pm), ('qhat = p*M >> 24', max_qhat),
                        ('r = p - qhat*q', max_r)):
        print('  %-18s %10d   %4d' % (name, value, width(value)))
    print('  r min              %10d' % min_r)
    print()

    mults = [('1  a * b', width(4095), width(4095)),
             ('2  p * %d' % M, width(max_p), width(M)),
             ('3  qhat * %d' % Q, width(max_qhat), width(Q))]
    print('multiplier          operand bits   fits DSP48E1 25x18 (unsigned %dx%d)'
          % (DSP_A_UNSIGNED, DSP_B_UNSIGNED))
    fits_all = True
    for name, wa, wb in mults:
        big, small = max(wa, wb), min(wa, wb)
        fits = big <= DSP_A_UNSIGNED and small <= DSP_B_UNSIGNED
        fits_all &= fits
        print('  %-18s %5d x %-5d    %s' % (name, wa, wb, 'yes' if fits else 'NO'))
    print()

    in_range = 0 <= min_r and max_r < 2 * Q
    print('remainder after step 3 in [0, 2q):       %s' % ('yes' if in_range else 'NO'))
    print('inputs that need the final "- q":        %d (%.1f%%)' % (need_sub, 100.0 * need_sub / total))
    print('result == (a*b) mod q for all inputs:    %s' % ('yes' if not errors else 'NO'))
    for e in errors:
        print('  ' + e)
    ok = in_range and not errors and fits_all
    print('\nRESULT: %s' % ('PASS' if ok else 'FAIL'))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
