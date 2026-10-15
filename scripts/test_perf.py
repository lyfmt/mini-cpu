#!/usr/bin/env python3
"""scripts/perf.py 的单元测试：python3 -m unittest discover -s scripts"""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import perf  # noqa: E402


def r_type(rd, rs1, rs2):                 # add
    return rs2 << 20 | rs1 << 15 | rd << 7 | 0x33


def i_type(op, f3, rd, rs1, imm):
    return (imm & 0xfff) << 20 | rs1 << 15 | f3 << 12 | rd << 7 | op


def sw(rs2, rs1, imm):
    return (imm >> 5) << 25 | rs2 << 20 | rs1 << 15 | 2 << 12 | (imm & 31) << 7 | 0x23


def lui(rd, imm20):
    return imm20 << 12 | rd << 7 | 0x37


def ori(rd, rs1, imm):
    return i_type(0x13, 6, rd, rs1, imm)


def lw(rd, rs1, imm):
    return i_type(0x03, 2, rd, rs1, imm)


BEQ_X0_X0_PLUS8 = 0x00000463
JAL_X0_PLUS4 = 0x0040006f

# MARK 1 ; lw/add（停 1）; lw x0/add x0（不停）; lw/sw 数据（不停）; beq 成立 ; jal 到下一条 ; MARK 2 ; FINISH
PROGRAM = [
    lui(31, 0x80000),            # 00 t6 = I/O 基址
    ori(30, 0, 1),               # 04
    sw(30, 31, 0x14),            # 08 MARK 1
    lui(1, 0x10),                # 0c x1 = 0x10000
    lw(2, 1, 0),                 # 10
    r_type(3, 2, 2),             # 14 load-use：停 1 拍
    lw(0, 1, 0),                 # 18
    r_type(4, 0, 0),             # 1c 读 x0：不停
    lw(5, 1, 0),                 # 20
    sw(5, 1, 4),                 # 24 store 的数据：不停
    BEQ_X0_X0_PLUS8,             # 28 成立，跳过 2c
    r_type(0, 0, 0),             # 2c
    JAL_X0_PLUS4,                # 30 跳到下一条，照样冲刷
    ori(30, 0, 2),               # 34
    sw(30, 31, 0x14),            # 38 MARK 2
    sw(0, 31, 0),                # 3c FINISH 0
]
# 窗口是 MARK 1 的 store 之后到 MARK 2 的 store（含）：0c..38 中执行了 11 条
MODEL = {'instret': 11, 'stalls': 1, 'flushes': 2, 'cycles': 11 + 1 + 3 * 2}


def marks():
    return perf.estimate(PROGRAM, [0x1234] * 4, 'base9')


class TestParse(unittest.TestCase):
    def test_forms(self):
        ds = perf.parse('x\n  // PERF 1-2: stalls=1 flushes=0\n// PERF: cycles=5\n'
                        '//PERF 3 - 4 : model\n// PERFORMANCE notes are ignored\n')
        self.assertEqual(ds, [perf.Directive(2, 1, 2, {'stalls': 1, 'flushes': 0}),
                              perf.Directive(3, None, None, {'cycles': 5}),
                              perf.Directive(4, 3, 4, {})])

    def test_errors(self):
        for text in ['// PERF 1-2 stalls=1', '// PERF 1-2: stall=1', '// PERF 1-2: stalls=x',
                     '// PERF 1-2: stalls=1 stalls=2', '// PERF 1-2:', '// PERF 1: stalls=1',
                     '// PERF: stalls=1\n// PERF: flushes=1']:
            with self.assertRaises(perf.PerfError, msg=text):
                perf.parse(text)


class TestEstimate(unittest.TestCase):
    def test_rules(self):
        m = marks()
        self.assertEqual([x[0] for x in m], [1, 2])
        (frm, to, delta, _), = perf.expectations([perf.Directive(1, 1, 2, {})], m)
        self.assertEqual((frm, to), (1, 2))
        self.assertEqual(delta, MODEL)

    def test_bare_form_uses_first_two_marks(self):
        (frm, to, delta, line), = perf.expectations([perf.Directive(7, None, None, {'stalls': 1})], marks())
        self.assertEqual((frm, to, delta['stalls'], line), (1, 2, 1, 7))

    def test_hand_count_must_agree(self):
        with self.assertRaises(perf.PerfError) as cm:
            perf.expectations([perf.Directive(9, 1, 2, {'stalls': 2, 'flushes': 2})], marks())
        self.assertIn('line 9', str(cm.exception))
        self.assertIn('stalls=2 (design rules give 1)', str(cm.exception))

    def test_unknown_or_reversed_mark(self):
        for d in (perf.Directive(1, 1, 3, {}), perf.Directive(1, 2, 1, {})):
            with self.assertRaises(perf.PerfError):
                perf.expectations([d], marks())


class TestCheck(unittest.TestCase):
    def setUp(self):
        fd, self.path = tempfile.mkstemp()
        os.close(fd)
        perf.write_expect(self.path, [(1, 2, MODEL, 12)])

    def tearDown(self):
        os.unlink(self.path)

    @staticmethod
    def sim(c, i, s, f):
        return ('MARK 00000001 cycles=100 instret=50 stalls=3 flushes=4\n'
                'MARK 00000002 cycles=%d instret=%d stalls=%d flushes=%d\nRESULT: PASS ...\n'
                % (100 + c, 50 + i, 3 + s, 4 + f))

    def test_match(self):
        self.assertEqual(perf.check(self.path, self.sim(18, 11, 1, 2)), (1, []))

    def test_mismatch(self):
        count, problems = perf.check(self.path, self.sim(19, 11, 2, 2))
        self.assertEqual(count, 1)
        self.assertEqual(len(problems), 1)
        self.assertIn('expected cycles=18 instret=11 stalls=1 flushes=2', problems[0])
        self.assertIn('actual   cycles=19 instret=11 stalls=2 flushes=2', problems[0])

    def test_missing_mark(self):
        _, problems = perf.check(self.path, 'MARK 00000001 cycles=1 instret=1 stalls=0 flushes=0\n')
        self.assertIn('0 x MARK 2', problems[0])


if __name__ == '__main__':
    unittest.main()
