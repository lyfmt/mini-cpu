#!/usr/bin/env python3
"""scripts/compare_trace.py 的单元测试：python3 -m unittest discover -s scripts"""

import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from compare_trace import TraceFormatError, compare, parse  # noqa: E402

EXPECT = [
    'R 00000000 02 00011000',
    'X 00000004 05 00000000',
    'M 00000008 00010000 0000002a',
    'R 0000000c 1f 80000000',
    'M 00000010 80000000 00000000',
]


def cmp(expect, actual, context=3):
    return compare(parse(expect), parse(actual), context)


class TestCompare(unittest.TestCase):
    def test_identical(self):
        ok, report = cmp(EXPECT, EXPECT)
        self.assertTrue(ok)
        self.assertEqual(report, 'traces match (5 events)')

    def test_x_matches_any_value(self):
        actual = list(EXPECT)
        actual[1] = 'R 00000004 05 12345678'
        self.assertTrue(cmp(EXPECT, actual)[0])

    def test_x_needs_same_pc_and_rd(self):
        for line in ('R 00000004 06 12345678', 'R 00000008 05 12345678',
                     'M 00000004 00010000 00000000'):
            actual = list(EXPECT)
            actual[1] = line
            ok, report = cmp(EXPECT, actual)
            self.assertFalse(ok, line)
            self.assertIn('event #2', report)

    def test_value_mismatch_report(self):
        actual = list(EXPECT)
        actual[2] = 'M 00000008 00010000 0000002b'
        ok, report = cmp(EXPECT, actual, context=1)
        self.assertFalse(ok)
        lines = report.splitlines()
        self.assertEqual(lines[0], 'traces differ at event #3, pc=00000008')
        self.assertEqual(lines[1], '  expected: M 00000008 00010000 0000002a')
        self.assertEqual(lines[2], '  actual:   M 00000008 00010000 0000002b')
        # 上下文：前后各 1 条，出错的那条标 >>
        rows = [l for l in lines if re.match(r'^  (>>|  ) *\d+ ', l)]
        self.assertEqual(len(rows), 3)
        self.assertTrue(any(l.startswith('  >>  3') for l in lines))

    def test_actual_ends_early(self):
        ok, report = cmp(EXPECT, EXPECT[:3])
        self.assertFalse(ok)
        self.assertIn('event #4', report)
        self.assertIn('CPU produced no more events', report)

    def test_actual_has_extra_events(self):
        ok, report = cmp(EXPECT, EXPECT + ['R 00000014 01 00000001'])
        self.assertFalse(ok)
        self.assertIn('event #6', report)
        self.assertIn('no more events expected', report)

    def test_malformed(self):
        for line in ('R 0000000 02 00011000', 'Q 00000000 02 00011000',
                     'R 00000000 2 00011000', 'M 00000000 02 00011000',
                     'R 00000000 0002 00011000', 'R 00000000 02 0X011000'):
            with self.assertRaises(TraceFormatError, msg=line):
                parse([line])


if __name__ == '__main__':
    unittest.main()
