#!/usr/bin/env python3
"""NTT 评估报告：软件模乘版与 qmul 版的对比（设计文档第七节"怎么证明它有用"第 2 点）。

    python3 scripts/ntt_report.py [--iss-only] [--variant nopad|pad] [--max-cycles N]

两个评估程序：
  rv32i/ntt/ntt_sw        模乘调用软件子程序
  rv32i_qmul/ntt/ntt_qmul 模乘用一条 qmul
它们在 NTT 前后各写一次 MARK（1 和 2），这里只统计两次 MARK 之间的部分。

CPU 模式（默认）：构建两个程序，iverilog 编译 CPU，各跑一次 vvp，从测试平台打印的
两行 MARK 里取硬件计数器的差值（cycles、instret、stalls、flushes），给出对比表、
加速比，并按
    cycles ≈ instret + stalls + 3 × flushes
把省下的周期拆成"指令变少""停顿变少""冲刷变少"三部分（剩下的记为 other）。
程序必须以 FINISH 0 结束（结果与 Python 参考实现逐项相等），轨迹也要与参考模型一致。

--iss-only：不跑 CPU，只用参考模型。退休指令数是准确的；停顿、冲刷是按第五节的
流水线规则从参考模型的执行过程推算的（load 后紧跟着用它的结果停 1 拍，store 的
数据不算；每次跳转成立冲刷一次），周期数再按上式估算。

CPU 模式下也做同样的推算，与硬件计数器对照，不一致时给出提示。

构建复用 scripts/build.py，跑 CPU 复用 scripts/run_tests.py；不改写 tests.lst。
"""

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build        # noqa: E402
import run_tests    # noqa: E402
import iss          # noqa: E402  （build 已把 model/ 加进 sys.path）

TESTS = [('sw', 'rv32i/ntt/ntt_sw'), ('qmul', 'rv32i_qmul/ntt/ntt_qmul')]
BUTTERFLIES = 896
FLUSH_PENALTY = 3

MARK_RE = re.compile(r'^MARK ([0-9a-fA-F]{8}) cycles=(\d+) instret=(\d+) '
                     r'stalls=(\d+) flushes=(\d+)\s*$')
FIELDS = ('cycles', 'instret', 'stalls', 'flushes')


class ReportError(Exception):
    pass


# ---------------------------------------------------------------- 构建

def find_test(test_id):
    tests = build.discover('rv32i_qmul', patterns=[test_id])
    if len(tests) != 1:
        raise ReportError('test %s not found under sw/tests' % test_id)
    return tests[0]


def build_tests(variant):
    """逐个 build_one（不用 build_all，以免改写 build/<variant>/tests.lst）。"""
    tests = {}
    for key, test_id in TESTS:
        test = find_test(test_id)
        r = build.build_one(test, variant)
        if not r.ok:
            raise ReportError('build of %s (%s) failed:\n%s' % (test_id, variant, r.log))
        if r.finish_code != 0:
            raise ReportError('%s: reference model ended with FINISH %d, expected 0'
                              % (test_id, r.finish_code))
        tests[key] = test
    return tests


# ---------------------------------------------------------------- 参考模型推算

def model_window(test, variant, max_steps):
    """在参考模型上跑一遍，返回两次 MARK 之间的 instret 以及推算的 stalls、flushes、cycles。"""
    out = test.outdir(variant)
    machine = iss.Machine(iss.load_hex(str(out / 'imem.hex')), iss.load_hex(str(out / 'dmem.hex')),
                          test.isa)
    stalls = flushes = 0
    prev = None
    snaps = {}
    try:
        while machine.finish_code is None:
            if machine.instret >= max_steps:
                raise ReportError('%s: no FINISH within %d instructions' % (test.id, max_steps))
            pc = machine.pc
            d = iss.decode(machine.fetch(pc))
            # load-use：上一条是写非 x0 的 lw，这一条在 EX 段要用它（store 的数据 rs2 除外）
            if prev is not None and prev.name == 'lw' and prev.rd != 0:
                if ((iss.uses_rs1(d.name) and d.rs1 == prev.rd) or
                        (iss.uses_rs2(d.name) and d.name != 'sw' and d.rs2 == prev.rd)):
                    stalls += 1
            marks = len(machine.marks)
            machine.step()
            if d.name in iss.JUMPS or (d.name in iss.BRANCHES and machine.pc != pc + 4):
                flushes += 1
            prev = d
            if len(machine.marks) > marks:
                snaps[machine.marks[-1][0]] = (machine.instret, stalls, flushes)
    except (iss.SimError, iss.IllegalInstruction) as e:
        raise ReportError('%s: reference model error: %s' % (test.id, e))
    if machine.finish_code != 0:
        raise ReportError('%s: FINISH %d on the reference model' % (test.id, machine.finish_code))
    if 1 not in snaps or 2 not in snaps:
        raise ReportError('%s: MARK 1 / MARK 2 not both written' % test.id)
    w = dict(zip(('instret', 'stalls', 'flushes'),
                 (b - a for a, b in zip(snaps[1], snaps[2]))))
    w['cycles'] = w['instret'] + w['stalls'] + FLUSH_PENALTY * w['flushes']
    return w


# ---------------------------------------------------------------- CPU

def cpu_window(test, variant, max_cycles):
    row = run_tests.Row(test, variant)
    args = argparse.Namespace(max_cycles=max_cycles, pipe=False, context=3)
    run_tests.run_cpu(row, args)
    log = test.outdir(variant) / 'sim.log'
    if not row.passed:
        raise ReportError('%s (%s) failed on the CPU: %s\n%s\n(see %s)'
                          % (test.id, variant, row.note, row.details, log))
    marks = {}
    with open(log) as f:
        for line in f:
            m = MARK_RE.match(line.strip())
            if m:
                marks[int(m.group(1), 16)] = [int(m.group(i)) for i in range(2, 6)]
    if 1 not in marks or 2 not in marks:
        raise ReportError('%s: no "MARK 00000001/00000002 cycles=..." lines in %s' % (test.id, log))
    return dict(zip(FIELDS, (b - a for a, b in zip(marks[1], marks[2]))))


# ---------------------------------------------------------------- 输出

def ratio(a, b):
    return '%.2fx' % (a / b) if b else '-'


def print_report(w, title, estimated):
    sw, qm = w['sw'], w['qmul']
    for v in (sw, qm):
        v['other'] = v['cycles'] - v['instret'] - v['stalls'] - FLUSH_PENALTY * v['flushes']
    est = ' (est.)' if estimated else ''

    print(title)
    print()
    print('%-30s %12s %12s %9s' % ('between MARK 1 and MARK 2', 'ntt_sw', 'ntt_qmul', 'sw/qmul'))
    rows = [('cycles' + est, 'cycles'), ('instret', 'instret'),
            ('stalls' + est, 'stalls'), ('flushes' + est, 'flushes')]
    for label, k in rows:
        print('%-30s %12d %12d %9s' % (label, sw[k], qm[k], ratio(sw[k], qm[k])))
    print('%-30s %12.3f %12.3f' % ('CPI' + est, sw['cycles'] / sw['instret'], qm['cycles'] / qm['instret']))
    print('%-30s %12.1f %12.1f' % ('cycles per butterfly' + est, sw['cycles'] / BUTTERFLIES,
                                   qm['cycles'] / BUTTERFLIES))
    print('%-30s %12.1f %12.1f' % ('instructions per butterfly', sw['instret'] / BUTTERFLIES,
                                   qm['instret'] / BUTTERFLIES))
    if not estimated:
        print('%-30s %12d %12d' % ('other (*)', sw['other'], qm['other']))
        print('(*) other = cycles - instret - stalls - 3 x flushes')
    print()
    print('speedup (cycles ntt_sw / ntt_qmul)%s: %.2fx' % (est, sw['cycles'] / qm['cycles']))
    print()

    saved = sw['cycles'] - qm['cycles']
    parts = [('fewer instructions', 'instret', sw['instret'] - qm['instret']),
             ('fewer stall cycles', 'stalls', sw['stalls'] - qm['stalls']),
             ('fewer flush cycles', '3 x flushes',
              FLUSH_PENALTY * (sw['flushes'] - qm['flushes']))]
    if not estimated:
        parts.append(('other', 'other', sw['other'] - qm['other']))
    print('where the saved cycles come from%s (cycles = instret + stalls + 3 x flushes%s):'
          % (est, '' if estimated else ' + other'))
    for label, term, value in parts:
        share = 100.0 * value / saved if saved else 0.0
        print('  %-22s %-14s %10d  %6.1f%%' % (label, 'delta ' + term, value, share))
    print('  %-22s %-14s %10d  %6.1f%%' % ('total', 'delta cycles', saved, 100.0 if saved else 0.0))


def main():
    parser = argparse.ArgumentParser(description='NTT evaluation: software modmul vs qmul')
    parser.add_argument('--iss-only', action='store_true',
                        help='reference model only: exact instruction counts, estimated cycles')
    parser.add_argument('--variant', choices=build.VARIANTS, default='nopad',
                        help='program variant (default nopad: the CPU handles hazards itself)')
    parser.add_argument('--max-cycles', type=int, default=2000000,
                        help='passed to the testbench as +MAXCYCLES (default %(default)s)')
    parser.add_argument('--max-steps', type=int, default=2000000,
                        help='instruction limit on the reference model (default %(default)s)')
    args = parser.parse_args()

    try:
        print('building %s (%s) ...' % (', '.join(t for _, t in TESTS), args.variant), flush=True)
        tests = build_tests(args.variant)
        model = {k: model_window(t, args.variant, args.max_steps) for k, t in tests.items()}

        if args.iss_only:
            print()
            print_report(model, 'NTT evaluation on the reference model, variant %s.\n'
                         'instret is exact; stalls and flushes are derived from the executed '
                         'instruction stream\n(load-use = 1 stall, taken jump = 1 flush) and '
                         'cycles = instret + stalls + 3 x flushes.' % args.variant, estimated=True)
            return 0

        print('compiling RTL with iverilog ...', flush=True)
        error = run_tests.compile_rtl()
        if error:
            raise ReportError(error)
        cpu = {}
        for key, test in tests.items():
            print('simulating %s ...' % test.id, flush=True)
            cpu[key] = cpu_window(test, args.variant, args.max_cycles)
        print()
        print_report(cpu, 'NTT evaluation on the CPU (iverilog), variant %s; '
                     'hardware counters between the two MARKs.' % args.variant, estimated=False)

        # 硬件计数器与参考模型推算的对照
        print()
        notes = []
        for key, _ in TESTS:
            for k in ('instret', 'stalls', 'flushes'):
                if cpu[key][k] != model[key][k]:
                    notes.append('  ntt_%s %s: CPU %d, reference model %s %d'
                                 % (key, k, cpu[key][k],
                                    'count' if k == 'instret' else 'estimate', model[key][k]))
        if notes:
            print('counters that differ from the reference model:')
            print('\n'.join(notes))
        else:
            print('instret, stalls and flushes all match the reference model.')
        return 0
    except ReportError as e:
        print('ntt_report: %s' % e, file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
