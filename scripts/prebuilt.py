#!/usr/bin/env python3
"""生成 prebuilt/：ModelSim 回归、演示和 Vivado 综合在 Windows 上要用的镜像，随仓库提交。

    python3 scripts/prebuilt.py [-j N] [--no-check]

步骤：
  1. 构建 nopad 变体的全部手写测试（含 demo、perf、ntt）加每层种子 1..30 的随机测试
     （同 make images 的选择，只是只要 nopad）；
  2. 清空 prebuilt/（README.md 除外），把每个测试的 imem.hex、dmem.hex、expect.trace
     拷到 prebuilt/<isa>/<suite>/<name>/，demo 和 ntt 另带 prog.dump（看波形时对照反汇编）；
  3. 写 prebuilt/tests.lst，每行一个测试目录（相对仓库根，形如 prebuilt/base9/isa/add）；
  4. 除非 --no-check：iverilog 编译一次，逐个以 prebuilt/ 里的文件运行 tests.lst 的
     每个测试（+EXPECT 在线比对），全部 PASS 才算成功。只读 prebuilt/，不读 build/。

退出码：0 成功，1 构建或检查失败。
"""

import argparse
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build        # noqa: E402
import run_tests    # noqa: E402

REPO = build.REPO
PREBUILT = REPO / 'prebuilt'
VARIANT = 'nopad'
RANDOM_PER_ISA = 30
FILES = ['imem.hex', 'dmem.hex', 'expect.trace']
DUMP_SUITES = {'demo', 'ntt'}


def select_tests():
    isa = build.ISA_ORDER[-1]
    tests = build.discover(isa)
    tests += build.random_tests(build.isas_upto(isa), RANDOM_PER_ISA, 1)
    return tests


def copy_tests(tests):
    for p in PREBUILT.iterdir() if PREBUILT.exists() else []:
        if p.name == 'README.md':
            continue
        if p.is_dir():
            shutil.rmtree(p)
        else:
            p.unlink()
    PREBUILT.mkdir(exist_ok=True)
    lines = []
    for t in tests:
        src = t.outdir(VARIANT)
        dst = PREBUILT / t.isa / t.suite / t.name
        dst.mkdir(parents=True)
        names = FILES + (['prog.dump'] if t.suite in DUMP_SUITES else [])
        for n in names:
            shutil.copyfile(src / n, dst / n)
        lines.append('prebuilt/%s/%s/%s' % (t.isa, t.suite, t.name))
    with open(PREBUILT / 'tests.lst', 'w', newline='\n') as f:
        f.write(''.join(l + '\n' for l in lines))
    return lines


def check(dirs, jobs):
    vvp, err = run_tests.compile_rtl()
    if vvp is None:
        print(err)
        return False

    def one(d):
        cmd = ['vvp', '-n', vvp, '+IMEM=%s/imem.hex' % d, '+DMEM=%s/dmem.hex' % d,
               '+EXPECT=%s/expect.trace' % d]
        proc = subprocess.run(cmd, cwd=str(REPO), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              universal_newlines=True)
        last = [l for l in proc.stdout.splitlines() if l.startswith('RESULT:')]
        return d, (last[-1] if last else 'no RESULT line')

    with ThreadPoolExecutor(max_workers=max(1, jobs)) as pool:
        results = list(pool.map(one, dirs))
    failed = [(d, r) for d, r in results if not r.startswith('RESULT: PASS')]
    for d, r in failed:
        print('FAIL %s: %s' % (d, r))
    print('prebuilt check: %d tests, %d PASS, %d FAIL' % (len(results), len(results) - len(failed),
                                                           len(failed)))
    return not failed


def main():
    parser = argparse.ArgumentParser(description='regenerate prebuilt/ (images for ModelSim / Vivado)')
    parser.add_argument('-j', dest='jobs', type=int, default=os.cpu_count() or 1)
    parser.add_argument('--no-check', action='store_true', help='skip the iverilog run over prebuilt/')
    args = parser.parse_args()

    tests = select_tests()
    results = build.build_all(tests, [VARIANT], args.jobs)
    failed = [r for r in results if not r.ok]
    for r in failed:
        print('== %s (%s): BUILD FAILED\n%s' % (r.test.id, r.variant, r.log))
    if failed:
        return 1
    dirs = copy_tests(tests)
    print('wrote %d tests to prebuilt/ and prebuilt/tests.lst' % len(dirs))
    if not args.no_check and not check(dirs, args.jobs):
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
