#!/usr/bin/env python3
"""比对两份轨迹（格式见实现约定第 6 节）。

    python3 scripts/compare_trace.py expect.trace cpu.trace [-C N]

逐条按顺序比对。期望里的 X 行是通配：只要实际的对应行是 R 行，
并且 pc、rd 相同，就算一致，不比较值。

一致时打印 "traces match (N events)"，退出码 0。不一致时报告第一处不一致的
序号（从 1 起）、PC、期望事件和实际事件，再附上前后各 N 条（默认 3）作为
上下文，退出码 1。文件格式错误时退出码 2。
"""

import argparse
import re
import sys
from collections import namedtuple

Event = namedtuple('Event', 'kind pc a b text')

LINE_RE = re.compile(r'^([RMX]) ([0-9a-f]{8}) ([0-9a-f]{2}|[0-9a-f]{8}) ([0-9a-f]{8})$')


class TraceFormatError(Exception):
    pass


def parse_line(text, where):
    m = LINE_RE.match(text)
    if not m:
        raise TraceFormatError('%s: malformed trace line %r' % (where, text))
    kind, pc, a, b = m.groups()
    if (kind == 'M') != (len(a) == 8):
        raise TraceFormatError('%s: malformed trace line %r' % (where, text))
    return Event(kind, pc, a, b, text)


def parse(lines, name='trace'):
    events = []
    for lineno, line in enumerate(lines, 1):
        text = line.strip()
        if text:
            events.append(parse_line(text, '%s:%d' % (name, lineno)))
    return events


def load(path):
    with open(path) as f:
        return parse(f, path)


def matches(expected, actual):
    if expected.kind == 'X' and actual.kind == 'R':
        return expected.pc == actual.pc and expected.a == actual.a
    return expected[:4] == actual[:4]


def compare(expect, actual, context=3):
    """返回 (是否一致, 报告文本)。expect、actual 是 Event 列表。"""
    n = min(len(expect), len(actual))
    first = next((i for i in range(n) if not matches(expect[i], actual[i])), None)
    if first is None:
        if len(expect) == len(actual):
            return True, 'traces match (%d events)' % len(expect)
        first = n

    lines = []
    exp = expect[first] if first < len(expect) else None
    act = actual[first] if first < len(actual) else None
    pc = (exp or act).pc
    lines.append('traces differ at event #%d, pc=%s' % (first + 1, pc))
    lines.append('  expected: %s' % (exp.text if exp else '(end of trace: no more events expected)'))
    lines.append('  actual:   %s' % (act.text if act else '(end of trace: CPU produced no more events)'))
    if exp and act and exp.kind == 'X':
        lines.append('  (X matches an R event with the same pc and rd)')

    lo = max(0, first - context)
    hi = min(max(len(expect), len(actual)), first + context + 1)
    width = max([len(e.text) for e in expect[lo:hi]] + [len('expected')])
    lines.append('context:')
    lines.append('       %-*s | %s' % (width, 'expected', 'actual'))
    for i in range(lo, hi):
        e = expect[i].text if i < len(expect) else '-'
        a = actual[i].text if i < len(actual) else '-'
        mark = '>>' if i == first else '  '
        lines.append('  %s%3d %-*s | %s' % (mark, i + 1, width, e, a))
    return False, '\n'.join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description='compare two mini-cpu traces')
    parser.add_argument('expect', help='expected trace (from the reference model)')
    parser.add_argument('actual', help='actual trace (from the CPU testbench)')
    parser.add_argument('-C', '--context', type=int, default=3,
                        help='events of context around the first difference (default 3)')
    args = parser.parse_args(argv)
    try:
        expect = load(args.expect)
        actual = load(args.actual)
    except (OSError, TraceFormatError) as e:
        print('compare_trace: %s' % e, file=sys.stderr)
        return 2
    ok, report = compare(expect, actual, args.context)
    print(report)
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
