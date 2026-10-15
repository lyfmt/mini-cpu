#!/usr/bin/env python3
"""回归驱动（实现约定第 9 节）。

    python3 scripts/run_tests.py [--isa ISA] [--variant pad|nopad|both] [--suite S] [-k PAT]
                                 [--random N [--seed S] [--random-all-isas]]
                                 [-j N] [--iss-only] [--max-cycles N] [--pipe] [-C N]
                                 [--rtl-root DIR]

依次完成：构建（含参考模型生成期望轨迹）、iverilog 编译一次、逐个用 vvp 运行、
解析测试平台的 RESULT 行、打印汇总表。有任何失败就以非 0 退出。

  --isa       ISA 子集，累积选择：rv32i 同时跑 base9 的测试
  --variant   pad（带空指令填充，阶段 1）或 nopad（阶段 2 起）；both 两个都跑
  --suite     只跑这些 suite（isa、hazard、prog……），可重复或用逗号分隔
  -k          只跑 id（isa/suite/name）或名字匹配通配的测试，可重复
  --iss-only  不跑 CPU，只在参考模型上跑：测试必须以 FINISH 0 结束
  --rtl-root  从 DIR/sim/files.f 编译 RTL（文件路径相对 DIR），默认仓库根；
              用来跑 RTL 的副本，例如变异测试

每个测试的仿真输出存在它的构建目录里：sim.log（vvp 的全部输出）、
cpu.trace（CPU 的轨迹）。测试平台报 FAIL 时，脚本再用 compare_trace
比对一次期望轨迹，给出第一处不一致的上下文。nopad 变体的构建目录里有
perf.expect 时（源码里的 // PERF 行，见 scripts/perf.py），再比对 MARK 行
给出的计数器增量，不一致也判 FAIL。

iverilog 的输出是 build/sim/ 下本进程独有的临时文件，进程退出时删除，
几个会话同时跑测试不会互相覆盖。
"""

import argparse
import atexit
import os
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build           # noqa: E402
import compare_trace   # noqa: E402
import perf            # noqa: E402

REPO = build.REPO
FILES_F = 'sim/files.f'
VVP_DIR = REPO / 'build' / 'sim'

# compile_rtl 最近一次的输出；run_cpu 不给 vvp 参数时用它
compiled_vvp = None

RESULT_RE = re.compile(r'^RESULT: (PASS|FAIL)\b(.*?)\s*cycles=(\d+) instret=(\d+) '
                       r'stalls=(\d+) flushes=(\d+)\s*$')


class Row:
    """汇总表的一行。"""

    def __init__(self, test, variant):
        self.test = test
        self.variant = variant
        self.passed = False
        self.cycles = self.instret = self.stalls = self.flushes = None
        self.note = ''
        self.details = ''         # 失败时打印在汇总表后面

    @property
    def name(self):
        return '%s/%s' % (self.variant, self.test.id)


def remove_quietly(path):
    try:
        os.unlink(path)
    except OSError:
        pass


def compile_rtl(rtl_root=None):
    """iverilog 编译一次，输出到 build/sim/cpu-*.vvp（本进程独有，进程退出时删除）。

    rtl_root：读 rtl_root/sim/files.f，文件路径相对 rtl_root；默认仓库根。
    返回 (vvp 文件的路径, None)，失败时返回 (None, 错误信息)。"""
    global compiled_vvp
    root = Path(rtl_root) if rtl_root else REPO
    if not (root / FILES_F).is_file():
        return None, ('%s not found (RTL not ready?); use --iss-only to run on the reference model only'
                      % (root / FILES_F))
    VVP_DIR.mkdir(parents=True, exist_ok=True)
    fd, vvp = tempfile.mkstemp(prefix='cpu-', suffix='.vvp', dir=str(VVP_DIR))
    os.close(fd)
    atexit.register(remove_quietly, vvp)
    cmd = ['iverilog', '-g2001', '-s', 'tb_top', '-o', vvp, '-f', FILES_F]
    proc = subprocess.run(cmd, cwd=str(root), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          universal_newlines=True)
    if proc.returncode:
        return None, '$ (cd %s) %s\n%s\niverilog failed' % (root, ' '.join(cmd), proc.stdout.rstrip())
    compiled_vvp = vvp
    return vvp, None


def run_cpu(row, args, vvp=None):
    """跑一个测试，结果填进 row。vvp 默认用 compile_rtl 最近一次的输出。"""
    d = row.test.reldir(row.variant)
    cmd = ['vvp', '-n', vvp or compiled_vvp,
           '+IMEM=%s/imem.hex' % d, '+DMEM=%s/dmem.hex' % d,
           '+EXPECT=%s/expect.trace' % d, '+TRACE=%s/cpu.trace' % d]
    if args.max_cycles:
        cmd.append('+MAXCYCLES=%d' % args.max_cycles)
    if args.pipe:
        cmd.append('+PIPE')
    out_dir = row.test.outdir(row.variant)
    trace = out_dir / 'cpu.trace'
    if trace.exists():
        trace.unlink()
    proc = subprocess.run(cmd, cwd=str(REPO), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          universal_newlines=True)
    with open(out_dir / 'sim.log', 'w', newline='\n') as f:
        f.write('$ %s\n%s' % (' '.join(cmd), proc.stdout))

    result = None
    for line in proc.stdout.splitlines():
        m = RESULT_RE.match(line.strip())
        if m:
            result = m
    if result is None:
        row.note = 'no RESULT line (vvp exit %d)' % proc.returncode
        row.details = '\n'.join(proc.stdout.splitlines()[-20:])
        return
    row.cycles, row.instret, row.stalls, row.flushes = (int(result.group(i)) for i in range(3, 7))
    tb_pass = result.group(1) == 'PASS'

    # 测试平台已经在线比对过；这里再独立比对一次，失败时还能给出上下文
    same, report = None, ''
    if trace.exists():
        try:
            same, report = compare_trace.compare(compare_trace.load(str(out_dir / 'expect.trace')),
                                                 compare_trace.load(str(trace)), args.context)
        except compare_trace.TraceFormatError as e:
            same, report = False, str(e)

    if tb_pass and same is not False:
        row.passed = True
        if same is None:
            row.note = 'no cpu.trace to cross-check'
        expect = out_dir / perf.EXPECT_FILE
        if row.variant == 'nopad' and expect.exists():
            count, problems = perf.check(str(expect), proc.stdout)
            if problems:
                row.passed = False
                row.note = 'perf counters differ'
                row.details = '\n'.join(problems)
            else:
                row.note = (row.note + '; ' if row.note else '') + 'perf ok (%d)' % count
        return
    row.note = result.group(2).strip() if not tb_pass else 'testbench PASS but traces differ'
    lines = [l for l in proc.stdout.splitlines() if l.strip()]
    if report and same is False:
        row.details = lines[-1] + '\n' + report
    else:
        row.details = '\n'.join(lines[-8:])


def fmt(value):
    return '-' if value is None else str(value)


def print_table(rows):
    width = max([len(r.name) for r in rows] + [4])
    print()
    print('%-*s  %-6s %9s %9s %7s %7s  %s' % (width, 'TEST', 'RESULT', 'CYCLES', 'INSTRET',
                                              'STALLS', 'FLUSHES', 'NOTE'))
    for r in rows:
        print('%-*s  %-6s %9s %9s %7s %7s  %s' % (width, r.name, 'PASS' if r.passed else 'FAIL',
                                                  fmt(r.cycles), fmt(r.instret), fmt(r.stalls),
                                                  fmt(r.flushes), r.note))
    failed = [r for r in rows if not r.passed]
    for r in failed:
        if r.details:
            print('\n==== %s: %s' % (r.name, r.note))
            print(r.details)
    print('\n%d passed, %d failed, %d total' % (len(rows) - len(failed), len(failed), len(rows)))
    return failed


def main():
    parser = argparse.ArgumentParser(
        description='mini-cpu regression: build, generate expected traces, simulate, summarize')
    build.add_selection_args(parser)
    parser.add_argument('--iss-only', action='store_true',
                        help='run on the reference model only; a test passes if it writes FINISH 0')
    parser.add_argument('--max-cycles', type=int, help='passed to the testbench as +MAXCYCLES')
    parser.add_argument('--pipe', action='store_true',
                        help='pass +PIPE (pipeline diagram in each sim.log)')
    parser.add_argument('-C', '--context', type=int, default=3,
                        help='trace context lines shown on a mismatch (default 3)')
    parser.add_argument('--rtl-root', metavar='DIR',
                        help='compile DIR/sim/files.f (paths relative to DIR) instead of the repository RTL')
    args = parser.parse_args()

    tests, variants = build.selection(args)
    if not tests:
        print('run_tests: no tests selected', file=sys.stderr)
        return 1

    print('building %d test(s) x %s ...' % (len(tests), '/'.join(variants)), flush=True)
    results = build.build_all(tests, variants, args.jobs)
    rows = []
    for b in results:
        row = Row(b.test, b.variant)
        if not b.ok:
            row.note = 'build failed'
            row.details = b.log
        else:
            row.instret = b.instret
        rows.append((row, b))

    if args.iss_only:
        for row, b in rows:
            if b.ok:
                row.passed = b.finish_code == 0
                if not row.passed:
                    row.note = 'reference model: FINISH code=%d' % b.finish_code
    else:
        print('compiling RTL with iverilog ...', flush=True)
        vvp, error = compile_rtl(args.rtl_root)
        if error:
            print('run_tests: %s' % error, file=sys.stderr)
            return 2
        to_run = [row for row, b in rows if b.ok]
        for row in to_run:
            row.instret = None
        print('simulating %d test(s) ...' % len(to_run), flush=True)
        with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
            list(pool.map(lambda row: run_cpu(row, args, vvp), to_run))

    failed = print_table([row for row, b in rows])
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
