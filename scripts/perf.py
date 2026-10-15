#!/usr/bin/env python3
"""性能计数器期望（PERF 行）：解析、按第五节规则推算、与测试平台的 MARK 行比对。

测试源码里的 PERF 行规定两次 MARK 之间硬件计数器的增量：

    // PERF 1-2: stalls=1 flushes=0      MARK 1 到 MARK 2 之间
    // PERF: stalls=1 flushes=0          程序写的第一次和第二次 MARK 之间
    // PERF 1-2: model                   全部取推算值（生成的测试用）

键是 cycles、instret、stalls、flushes，写哪几个都行（至少一个，或者写 model）。
被引用的 MARK 编号在一次运行里只能写一次。只对 nopad 变体检查。

构建时（build.py）：在参考模型的执行流上按设计文档第五节的规则推算每段的增量，
源码里写了的值必须与推算一致，否则构建失败；没写的键用推算值补上。结果写进
nopad 构建目录的 perf.expect，每行一段：

    <起点 MARK> <终点 MARK> cycles=<d> instret=<d> stalls=<d> flushes=<d> line=<源码行号>

运行时（run_tests.py）：从 vvp 输出的 MARK 行算出硬件计数器的增量，与
perf.expect 逐项比较。

推算规则（计数器读"当拍"的值，MARK 行取写 MARK 的 store 在 M 段那一拍）：
  - 一段包括第一次 MARK 的 store 之后、直到第二次 MARK 的 store（含）的全部动态指令；
  - instret = 这些指令的条数；
  - stalls：其中每条指令，若它紧前面的那条动态指令是目标寄存器不为 x0 的 lw，
    且它真的要在 EX 段读这个寄存器（按指令类型确实用到的 rs1/rs2；store 的 rs2 除外），
    记一次；错误路径上的指令不执行，自然不计（冲刷优先）；
  - flushes：其中成立的分支和全部 jal、jalr，每条一次；
  - cycles = instret + stalls + 3 × flushes。
这些式子要求 MARK 的 store 紧跟在一条不会引起停顿的指令后面，MARK_POINT 宏满足。
"""

import re
import sys
from collections import namedtuple
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'model'))

import iss   # noqa: E402

KEYS = ('cycles', 'instret', 'stalls', 'flushes')
FLUSH_PENALTY = 3
EXPECT_FILE = 'perf.expect'

# frm/to 为 None 表示"第一次和第二次 MARK"；values 是源码里写了的键；model 表示写的是 model
Directive = namedtuple('Directive', 'line frm to values')

DIRECTIVE_RE = re.compile(r'^\s*//\s*PERF(?=[\s:\d])(.*)$')
BODY_RE = re.compile(r'^\s*(?:(\d+)\s*-\s*(\d+))?\s*:(.*)$')
MARK_RE = re.compile(r'^MARK ([0-9a-fA-F]{8}) cycles=(\d+) instret=(\d+) stalls=(\d+) flushes=(\d+)\s*$')


class PerfError(Exception):
    pass


def parse(text):
    """返回 Directive 列表。语法错误抛 PerfError。"""
    out = []
    for lineno, line in enumerate(text.splitlines(), 1):
        m = DIRECTIVE_RE.match(line)
        if not m:
            continue
        b = BODY_RE.match(m.group(1))
        if not b:
            raise PerfError('line %d: expected "// PERF [a-b]: key=value ..."' % lineno)
        frm = int(b.group(1)) if b.group(1) else None
        to = int(b.group(2)) if b.group(2) else None
        body = b.group(3).split()
        values = {}
        if body != ['model']:
            if not body:
                raise PerfError('line %d: PERF needs key=value pairs or "model"' % lineno)
            for item in body:
                k, sep, v = item.partition('=')
                if not sep or k not in KEYS or not v.isdigit():
                    raise PerfError('line %d: bad item %r (keys: %s)' % (lineno, item, ', '.join(KEYS)))
                if k in values:
                    raise PerfError('line %d: %s given twice' % (lineno, k))
                values[k] = int(v)
        out.append(Directive(lineno, frm, to, values))
    if sum(1 for d in out if d.frm is None) > 1:
        raise PerfError('more than one "// PERF:" without MARK numbers')
    return out


def branch_taken(name, a, b):
    return {
        'beq': a == b,
        'bne': a != b,
        'blt': iss.to_signed(a) < iss.to_signed(b),
        'bge': iss.to_signed(a) >= iss.to_signed(b),
        'bltu': a < b,
        'bgeu': a >= b,
    }[name]


def load_use(prev, d):
    """d 紧跟在 prev 后面时，按第五节规则是否要停一拍。"""
    if prev is None or prev.name != 'lw' or prev.rd == 0:
        return False
    r = prev.rd
    return ((iss.uses_rs1(d.name) and d.rs1 == r) or
            (iss.uses_rs2(d.name) and d.name != 'sw' and d.rs2 == r))


def estimate(imem, dmem, isa, max_steps=1000000):
    """在参考模型上执行，返回每次写 MARK 时的累计值 [(编号, instret, stalls, flushes)]。"""
    m = iss.Machine(imem, dmem, isa)
    stalls = flushes = 0
    prev = None
    marks = []
    try:
        while m.finish_code is None:
            if m.instret >= max_steps:
                raise PerfError('no FINISH after %d instructions' % max_steps)
            d = iss.decode(m.fetch(m.pc))
            a, b = m.regs[d.rs1], m.regs[d.rs2]
            n = len(m.marks)
            m.step()
            if load_use(prev, d):
                stalls += 1
            if d.name in iss.JUMPS or (d.name in iss.BRANCHES and branch_taken(d.name, a, b)):
                flushes += 1
            if len(m.marks) > n:
                marks.append((m.marks[-1][0], m.instret, stalls, flushes))
            prev = d
    except (iss.SimError, iss.IllegalInstruction) as e:
        raise PerfError('reference model: %s' % e)
    return marks


def expectations(directives, marks):
    """把 PERF 行解析成完整的期望：[(frm, to, {键: 值}, 源码行号)]。不一致抛 PerfError。"""
    ids = [mk[0] for mk in marks]
    out = []
    errors = []
    for d in directives:
        where = 'line %d (PERF %s)' % (d.line, '%d-%d' % (d.frm, d.to) if d.frm is not None else ':')
        if d.frm is None:
            if len(ids) < 2:
                errors.append('%s: the program writes MARK %d time(s), needs 2' % (where, len(ids)))
                continue
            frm, to = ids[0], ids[1]
        else:
            frm, to = d.frm, d.to
        bad = [i for i in (frm, to) if ids.count(i) != 1]
        if bad:
            errors.append('%s: MARK %d must be written exactly once (written %d time(s))'
                          % (where, bad[0], ids.count(bad[0])))
            continue
        i, j = ids.index(frm), ids.index(to)
        if i >= j:
            errors.append('%s: MARK %d is not written before MARK %d' % (where, frm, to))
            continue
        delta = dict(zip(('instret', 'stalls', 'flushes'),
                         (y - x for x, y in zip(marks[i][1:], marks[j][1:]))))
        delta['cycles'] = delta['instret'] + delta['stalls'] + FLUSH_PENALTY * delta['flushes']
        wrong = ['%s=%d (design rules give %d)' % (k, v, delta[k])
                 for k, v in sorted(d.values.items()) if v != delta[k]]
        if wrong:
            errors.append('%s: %s' % (where, ', '.join(wrong)))
            continue
        out.append((frm, to, delta, d.line))
    if errors:
        raise PerfError('\n'.join(errors))
    return out


def write_expect(path, expects):
    with open(path, 'w', newline='\n') as f:
        for frm, to, values, line in expects:
            f.write('%d %d %s line=%d\n' % (frm, to, ' '.join('%s=%d' % (k, values[k]) for k in KEYS), line))


def read_expect(path):
    out = []
    with open(path) as f:
        for text in f:
            fields = text.split()
            if not fields:
                continue
            kv = dict(item.split('=') for item in fields[2:])
            out.append((int(fields[0]), int(fields[1]), {k: int(kv[k]) for k in KEYS}, int(kv['line'])))
    return out


def check(path, sim_output):
    """比对 perf.expect 和 vvp 输出里的 MARK 行。返回 (段数, 问题列表)。"""
    expects = read_expect(path)
    snaps = {}
    for line in sim_output.splitlines():
        m = MARK_RE.match(line.strip())
        if m:
            snaps.setdefault(int(m.group(1), 16), []).append(
                dict(zip(KEYS, (int(m.group(i)) for i in range(2, 6)))))
    problems = []
    for frm, to, want, line in expects:
        where = 'MARK %d -> %d (source line %d)' % (frm, to, line)
        if len(snaps.get(frm, [])) != 1 or len(snaps.get(to, [])) != 1:
            problems.append('%s: MARK lines in the simulation output: %d x MARK %d, %d x MARK %d'
                            % (where, len(snaps.get(frm, [])), frm, len(snaps.get(to, [])), to))
            continue
        got = {k: snaps[to][0][k] - snaps[frm][0][k] for k in KEYS}
        if got != want:
            problems.append('%s:\n    expected %s\n    actual   %s'
                            % (where, ' '.join('%s=%d' % (k, want[k]) for k in KEYS),
                               ' '.join('%s=%d' % (k, got[k]) for k in KEYS)))
    return len(expects), problems
