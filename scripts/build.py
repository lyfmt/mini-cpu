#!/usr/bin/env python3
"""构建测试程序：.S -> prog.elf -> imem.hex / dmem.hex -> prog.dump -> expect.trace。

    python3 scripts/build.py [--isa ISA] [--variant pad|nopad|both] [--suite S] [-k PAT] [-j N]

测试源码在 sw/tests/<isa>/<suite>/<name>.S，构建到
build/<variant>/<isa>/<suite>/<name>/（实现约定第 5 节）。选 ISA 是累积的：
--isa rv32i 同时包括 base9 的测试。每个变体另写 build/<variant>/tests.lst，
列出这次构建的测试目录，供 ModelSim 批量脚本使用。

--random N --seed S 另外加 N 个随机测试（scripts/gen_random.py），种子 S..S+N-1，
ISA 取 --isa 那一层（加 --random-all-isas 则每一层各 N 个）。源码生成到
build/src/<isa>/rand/seed<k>.S，测试 id 是 <isa>/rand/seed<k>；--suite 和 -k
同样筛选它们（suite 名是 rand）。

每个测试依次：
  1. riscv64-elf-gcc 汇编、链接（pad 变体加 -DPAD）；
  2. 拆成 imem.hex / dmem.hex；
  3. 静态检查：代码段里每个字都必须是该测试所属 ISA 子集里的指令；
  4. objdump 生成 prog.dump；
  5. 参考模型生成 expect.trace（--check-uninit；pad 变体另加 --check-pad）。

工具链前缀可用环境变量 RISCV_PREFIX 指定，默认 riscv64-elf-。
"""

import argparse
import fnmatch
import os
import re
import subprocess
import sys
from collections import namedtuple
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / 'model'))
sys.path.insert(0, str(REPO / 'scripts'))

import iss         # noqa: E402
import elf2hex     # noqa: E402
import gen_random  # noqa: E402

ISA_ORDER = ['base9', 'rv32i', 'rv32i_qmul']
VARIANTS = ['pad', 'nopad']
SW_TESTS = REPO / 'sw' / 'tests'
SW_COMMON = REPO / 'sw' / 'common'
BUILD = REPO / 'build'
GEN_SRC = BUILD / 'src'

PREFIX = os.environ.get('RISCV_PREFIX', 'riscv64-elf-')
CFLAGS = ['-march=rv32i', '-mabi=ilp32', '-nostdlib', '-nostartfiles', '-static',
          '-I', str(SW_COMMON), '-T', str(SW_COMMON / 'link.ld'),
          '-Wl,--no-relax', '-Wl,--no-warn-rwx-segments']


class Test(namedtuple('Test', 'isa suite name src')):
    @property
    def id(self):
        return '%s/%s/%s' % (self.isa, self.suite, self.name)

    def outdir(self, variant):
        return BUILD / variant / self.isa / self.suite / self.name

    def reldir(self, variant):
        """相对仓库根、用正斜杠的测试目录，tests.lst 和测试平台 plusargs 用它。"""
        return 'build/%s/%s' % (variant, self.id)


# 构建结果。ok 为 False 时 log 说明原因；ok 为 True 时 finish_code/instret 来自参考模型。
BuildResult = namedtuple('BuildResult', 'test variant ok log finish_code instret')


def isas_upto(isa):
    """ISA 选择是累积的：rv32i 包括 base9，rv32i_qmul 包括前两者。"""
    return ISA_ORDER[:ISA_ORDER.index(isa) + 1]


def selected(test, suites, patterns):
    """suites：只要这些 suite；patterns：测试 id（isa/suite/name）或名字匹配其中任一通配。"""
    if suites and test.suite not in suites:
        return False
    if patterns and not any(fnmatch.fnmatch(test.id, p) or fnmatch.fnmatch(test.name, p)
                            for p in patterns):
        return False
    return True


def discover(isa, suites=None, patterns=None):
    """按 ISA 顺序、suite、文件名列出 sw/tests 下要跑的测试。"""
    tests = []
    for i in isas_upto(isa):
        root = SW_TESTS / i
        if not root.is_dir():
            continue
        for src in sorted(root.glob('*/*.S')):
            t = Test(i, src.parent.name, src.stem, src)
            if selected(t, suites, patterns):
                tests.append(t)
    return tests


def random_tests(isas, count, seed, suites=None, patterns=None):
    """生成随机测试的源码，返回 Test 列表。内容没变的源文件不重写。"""
    tests = []
    for isa in isas:
        for k in range(seed, seed + count):
            name = 'seed%d' % k
            t = Test(isa, 'rand', name, GEN_SRC / isa / 'rand' / (name + '.S'))
            if not selected(t, suites, patterns):
                continue
            text = gen_random.generate(isa, k)
            if not t.src.is_file() or t.src.read_text() != text:
                t.src.parent.mkdir(parents=True, exist_ok=True)
                with open(t.src, 'w', newline='\n') as f:
                    f.write(text)
            tests.append(t)
    return tests


def run(cmd, log):
    """运行命令，把命令行和输出记进 log。返回 CompletedProcess。"""
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          universal_newlines=True)
    log.append('$ ' + ' '.join(str(c) for c in cmd))
    if proc.stdout:
        log.append(proc.stdout.rstrip('\n'))
    return proc


def static_isa_check(test, sections):
    """代码段里每个字都要能译码，且属于测试所属的 ISA 子集。返回错误信息或 None。"""
    allowed = iss.ISA_SUBSETS[test.isa]
    for s in sections:
        if not s.flags & elf2hex.SHF_EXECINSTR:
            continue
        for k in range(0, len(s.data), 4):
            word = int.from_bytes(s.data[k:k + 4], 'little')
            try:
                name = iss.decode(word).name
            except iss.IllegalInstruction as e:
                return 'word %08x at %08x is not a valid instruction (%s)' % (word, s.addr + k, e)
            if name not in allowed:
                return '%s (%08x) at %08x is not in ISA subset %s' % (name, word, s.addr + k, test.isa)
    return None


def build_one(test, variant):
    out = test.outdir(variant)
    out.mkdir(parents=True, exist_ok=True)
    elf = out / 'prog.elf'
    log = []

    def fail(message):
        log.append(message)
        return BuildResult(test, variant, False, '\n'.join(log), None, None)

    # 1. 汇编、链接
    defines = ['-DPAD'] if variant == 'pad' else []
    if run([PREFIX + 'gcc'] + CFLAGS + defines + ['-o', str(elf), str(test.src)], log).returncode:
        return fail('assemble/link failed')

    # 2. 镜像
    try:
        imem, dmem, sections = elf2hex.elf_to_images(str(elf))
    except elf2hex.ElfError as e:
        return fail(str(e))
    elf2hex.write_hex(str(out / 'imem.hex'), imem)
    elf2hex.write_hex(str(out / 'dmem.hex'), dmem)

    # 3. 静态 ISA 检查
    problem = static_isa_check(test, sections)
    if problem:
        return fail('static ISA check: ' + problem)

    # 4. 反汇编，只供调试
    data_sections = [s.name for s in sections
                     if s.type != elf2hex.SHT_NOBITS and not s.flags & elf2hex.SHF_EXECINSTR]
    commands = [[PREFIX + 'objdump', '-d', '-M', 'no-aliases,numeric', str(elf)]]
    if data_sections:
        commands.append([PREFIX + 'objdump', '-s'] +
                        [arg for name in data_sections for arg in ('-j', name)] + [str(elf)])
    with open(out / 'prog.dump', 'w', newline='\n') as f:
        for cmd in commands:
            f.write(subprocess.run(cmd, stdout=subprocess.PIPE, universal_newlines=True).stdout)

    # 5. 期望轨迹
    cmd = [sys.executable, str(REPO / 'model' / 'iss.py'), '--isa', test.isa,
           '--imem', str(out / 'imem.hex'), '--dmem', str(out / 'dmem.hex'),
           '--trace', str(out / 'expect.trace'), '--check-uninit']
    if variant == 'pad':
        cmd.append('--check-pad')
    proc = run(cmd, log)
    if proc.returncode:
        return fail('reference model failed')
    m = re.search(r'^FINISH code=(\d+) instret=(\d+)$', proc.stdout, re.M)
    if not m:
        return fail('reference model printed no FINISH line')
    return BuildResult(test, variant, True, '\n'.join(log), int(m.group(1)), int(m.group(2)))


def write_list(variant, tests):
    path = BUILD / variant / 'tests.lst'
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, 'w', newline='\n') as f:
        for t in tests:
            f.write(t.reldir(variant) + '\n')
    return path


def build_all(tests, variants, jobs):
    """构建 tests × variants，返回 BuildResult 列表（顺序与输入一致），并写 tests.lst。"""
    jobs_list = [(t, v) for v in variants for t in tests]
    with ThreadPoolExecutor(max_workers=max(1, jobs)) as pool:
        results = list(pool.map(lambda tv: build_one(*tv), jobs_list))
    for v in variants:
        write_list(v, tests)
    return results


def add_selection_args(parser):
    parser.add_argument('--isa', choices=ISA_ORDER, default=ISA_ORDER[-1],
                        help='ISA subset; cumulative (rv32i includes base9). default: %(default)s')
    parser.add_argument('--variant', choices=VARIANTS + ['both'], default='pad',
                        help='pad: with padding nops (stage 1); nopad: without. default: %(default)s')
    parser.add_argument('--suite', action='append',
                        help='only these suites (isa, hazard, prog, ...); may repeat or use commas')
    parser.add_argument('-k', dest='patterns', action='append',
                        help='only tests whose id or name matches this glob; may repeat')
    parser.add_argument('-j', dest='jobs', type=int, default=os.cpu_count() or 1,
                        help='parallel jobs (default: number of CPUs)')
    parser.add_argument('--random', type=int, default=0, metavar='N',
                        help='also generate N random tests (suite "rand") for the --isa level')
    parser.add_argument('--seed', type=int, default=1,
                        help='first random seed (default: %(default)s)')
    parser.add_argument('--random-all-isas', action='store_true',
                        help='N random tests for every ISA level up to --isa, not just the top one')


def selection(args):
    suites = None
    if args.suite:
        suites = set(s for item in args.suite for s in item.split(',') if s)
    variants = VARIANTS if args.variant == 'both' else [args.variant]
    tests = discover(args.isa, suites, args.patterns)
    if args.random:
        isas = isas_upto(args.isa) if args.random_all_isas else [args.isa]
        tests += random_tests(isas, args.random, args.seed, suites, args.patterns)
    return tests, variants


def main():
    parser = argparse.ArgumentParser(description='build mini-cpu test images and expected traces')
    add_selection_args(parser)
    parser.add_argument('-v', '--verbose', action='store_true', help='show logs of all builds')
    args = parser.parse_args()
    tests, variants = selection(args)
    if not tests:
        print('build: no tests selected', file=sys.stderr)
        return 1
    results = build_all(tests, variants, args.jobs)
    failed = [r for r in results if not r.ok]
    for r in results:
        if not r.ok or args.verbose:
            print('== %s (%s): %s' % (r.test.id, r.variant, 'ok' if r.ok else 'BUILD FAILED'))
            print(r.log)
    print('built %d test image(s), %d failed' % (len(results), len(failed)))
    for v in variants:
        print('wrote build/%s/tests.lst' % v)
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
