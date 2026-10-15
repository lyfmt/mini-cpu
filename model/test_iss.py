#!/usr/bin/env python3
"""参考模型 model/iss.py 的单元测试。

    python3 -m unittest discover -s model -p 'test_*.py'
    MINICPU_SLOW=1 ...   另外对 qmul 的 Barrett 实现做 4096 x 4096 穷举（十几秒）

期望值都是按 RISC-V 规范手工算出的常数，或来自 GNU 汇编器的编码，
不从参考模型自己的输出抄。
"""

import io
import os
import random
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import iss  # noqa: E402
from iss import Decoded, Machine, SimError  # noqa: E402

NOP = 0x00000033


# ---------------------------------------------------------------- 独立的小汇编器
# 只用于构造测试程序，按规范的位域直接拼，不调用 iss 里的任何函数。

REG = {'x%d' % i: i for i in range(32)}


def r_type(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def i_type(imm, rs1, funct3, rd, opcode):
    return ((imm & 0xfff) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def s_type(imm, rs2, rs1, funct3, opcode):
    imm &= 0xfff
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm & 0x1f) << 7) | opcode


def b_type(imm, rs2, rs1, funct3):
    imm &= 0x1fff
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3f) << 25) | (rs2 << 20) | (rs1 << 15) | \
        (funct3 << 12) | (((imm >> 1) & 0xf) << 8) | (((imm >> 11) & 1) << 7) | 0b1100011


def u_type(imm20, rd, opcode):
    return ((imm20 & 0xfffff) << 12) | (rd << 7) | opcode


def j_type(imm, rd):
    imm &= 0x1fffff
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3ff) << 21) | (((imm >> 11) & 1) << 20) | \
        (((imm >> 12) & 0xff) << 12) | (rd << 7) | 0b1101111


R_OPS = {'add': (0, 0), 'sub': (0x20, 0), 'sll': (0, 1), 'slt': (0, 2), 'sltu': (0, 3),
         'xor': (0, 4), 'srl': (0, 5), 'sra': (0x20, 5), 'or': (0, 6), 'and': (0, 7)}
I_OPS = {'addi': 0, 'slti': 2, 'sltiu': 3, 'xori': 4, 'ori': 6, 'andi': 7}
B_OPS = {'beq': 0, 'bne': 1, 'blt': 4, 'bge': 5, 'bltu': 6, 'bgeu': 7}


def asm(name, *ops):
    """asm('add', 1, 2, 3) 之类，寄存器写成整数。"""
    if name in R_OPS:
        f7, f3 = R_OPS[name]
        rd, rs1, rs2 = ops
        return r_type(f7, rs2, rs1, f3, rd, 0b0110011)
    if name == 'qmul':
        rd, rs1, rs2 = ops
        return r_type(0, rs2, rs1, 0, rd, 0b0001011)
    if name in I_OPS:
        rd, rs1, imm = ops
        return i_type(imm, rs1, I_OPS[name], rd, 0b0010011)
    if name in ('slli', 'srli', 'srai'):
        rd, rs1, sh = ops
        f7 = 0x20 if name == 'srai' else 0
        f3 = 1 if name == 'slli' else 5
        return r_type(f7, sh, rs1, f3, rd, 0b0010011)
    if name == 'lw':
        rd, imm, rs1 = ops
        return i_type(imm, rs1, 2, rd, 0b0000011)
    if name == 'sw':
        rs2, imm, rs1 = ops
        return s_type(imm, rs2, rs1, 2, 0b0100011)
    if name in B_OPS:
        rs1, rs2, imm = ops
        return b_type(imm, rs2, rs1, B_OPS[name])
    if name == 'lui':
        rd, imm20 = ops
        return u_type(imm20, rd, 0b0110111)
    if name == 'auipc':
        rd, imm20 = ops
        return u_type(imm20, rd, 0b0010111)
    if name == 'jal':
        rd, imm = ops
        return j_type(imm, rd)
    if name == 'jalr':
        rd, imm, rs1 = ops
        return i_type(imm, rs1, 0, rd, 0b1100111)
    raise ValueError(name)


# 结束序列：x31 = 0x80000000，把 x30 写进 FINISH
def finish_with(reg):
    return [asm('lui', 31, 0x80000), asm('sw', reg, 0, 31)]


FINISH_OK = [asm('lui', 31, 0x80000), asm('sw', 0, 0, 31)]


def run(program, dmem=(), isa='rv32i_qmul', max_steps=10000, **kw):
    """执行 program（字列表）到 FINISH 为止，返回 Machine。"""
    m = Machine(program, list(dmem), isa, **kw)
    m.run(max_steps)
    return m


def li(rd, value):
    """用 lui + addi 装常数（测试程序用，rv32i）。"""
    value &= 0xffffffff
    lo = value & 0xfff
    if lo >= 0x800:
        lo -= 0x1000
    hi = ((value - lo) >> 12) & 0xfffff
    return [asm('lui', rd, hi), asm('addi', rd, rd, lo)]


# ---------------------------------------------------------------- 译码

# GNU as 2.47（-march=rv32i）给出的编码；不依赖本文件的汇编器
GAS_ENCODINGS = [
    (0x003100b3, Decoded('add', 1, 2, 3, 0)),
    (0x41df0fb3, Decoded('sub', 31, 30, 29, 0)),
    (0x007312b3, Decoded('sll', 5, 6, 7, 0)),
    (0x00a4a433, Decoded('slt', 8, 9, 10, 0)),
    (0x00d635b3, Decoded('sltu', 11, 12, 13, 0)),
    (0x0107c733, Decoded('xor', 14, 15, 16, 0)),
    (0x013958b3, Decoded('srl', 17, 18, 19, 0)),
    (0x416ada33, Decoded('sra', 20, 21, 22, 0)),
    (0x019c6bb3, Decoded('or', 23, 24, 25, 0)),
    (0x01cdfd33, Decoded('and', 26, 27, 28, 0)),
    (0x80010093, Decoded('addi', 1, 2, 0, -2048)),
    (0x7ff20193, Decoded('addi', 3, 4, 0, 2047)),
    (0xfff32293, Decoded('slti', 5, 6, 0, -1)),
    (0x00143393, Decoded('sltiu', 7, 8, 0, 1)),
    (0xaaa54493, Decoded('xori', 9, 10, 0, -1366)),
    (0x55566593, Decoded('ori', 11, 12, 0, 1365)),
    (0xff077693, Decoded('andi', 13, 14, 0, -16)),
    (0x01f81793, Decoded('slli', 15, 16, 0, 31)),
    (0x00195893, Decoded('srli', 17, 18, 0, 1)),
    (0x41fa5993, Decoded('srai', 19, 20, 0, 31)),
    (0x800b2a83, Decoded('lw', 21, 22, 0, -2048)),
    (0x7fcc2b83, Decoded('lw', 23, 24, 0, 2044)),
    (0x819d2023, Decoded('sw', 0, 26, 25, -2048)),
    (0x7fbe2fa3, Decoded('sw', 0, 28, 27, 2047)),
    (0xffdf2fa3, Decoded('sw', 0, 30, 29, -1)),
    (0x80208063, Decoded('beq', 0, 1, 2, -4096)),
    (0x7e418fe3, Decoded('beq', 0, 3, 4, 4094)),
    (0x006290e3, Decoded('bne', 0, 5, 6, 2048)),
    (0xfe83cfe3, Decoded('blt', 0, 7, 8, -2)),
    (0x00a4d163, Decoded('bge', 0, 9, 10, 2)),
    (0x80c5e0e3, Decoded('bltu', 0, 11, 12, -2048)),
    (0x00e6f263, Decoded('bgeu', 0, 13, 14, 4)),
    (0xfffff7b7, Decoded('lui', 15, 0, 0, 0xfffff000)),
    (0x80000837, Decoded('lui', 16, 0, 0, 0x80000000)),
    (0x12345897, Decoded('auipc', 17, 0, 0, 0x12345000)),
    (0x8000096f, Decoded('jal', 18, 0, 0, -1048576)),
    (0x7ffff9ef, Decoded('jal', 19, 0, 0, 1048574)),
    (0x0010006f, Decoded('jal', 0, 0, 0, 2048)),
    (0xfffff0ef, Decoded('jal', 1, 0, 0, -2)),
    (0x800a8a67, Decoded('jalr', 20, 21, 0, -2048)),
    (0x7ff08067, Decoded('jalr', 0, 1, 0, 2047)),
    (0x018b8b0b, Decoded('qmul', 22, 23, 24, 0)),    # .insn r 0x0b, 0, 0, x22, x23, x24
]


class TestDecode(unittest.TestCase):
    def test_gas_encodings(self):
        for word, expected in GAS_ENCODINGS:
            with self.subTest(word='%08x' % word):
                self.assertEqual(iss.decode(word), expected)

    def test_immediate_helpers(self):
        # I：inst[31:20]
        self.assertEqual(iss.imm_i(0xfff00000), -1)
        self.assertEqual(iss.imm_i(0x7ff00000), 2047)
        self.assertEqual(iss.imm_i(0x80000000), -2048)
        # S：inst[31:25] 和 inst[11:7]
        self.assertEqual(iss.imm_s(0xfe000f80), -1)
        self.assertEqual(iss.imm_s(0x00000f80), 0x1f)
        self.assertEqual(iss.imm_s(0x7e000000), 0x7e0)
        # B：inst[31] -> 12，inst[7] -> 11，inst[30:25] -> 10:5，inst[11:8] -> 4:1
        self.assertEqual(iss.imm_b(0x00000080), 0x800)
        self.assertEqual(iss.imm_b(0x80000000), -4096)
        self.assertEqual(iss.imm_b(0x7e000f00), 0x7fe)
        self.assertEqual(iss.imm_b(0xfe000f80), -2)
        # U
        self.assertEqual(iss.imm_u(0xabcde123), 0xabcde000)
        # J：inst[31] -> 20，inst[19:12] -> 19:12，inst[20] -> 11，inst[30:21] -> 10:1
        self.assertEqual(iss.imm_j(0x00100000), 0x800)
        self.assertEqual(iss.imm_j(0x000ff000), 0xff000)
        self.assertEqual(iss.imm_j(0x7fe00000), 0x7fe)
        self.assertEqual(iss.imm_j(0x80000000), -0x100000)

    def test_round_trip_random(self):
        # 用本文件的汇编器拼随机指令，再译回来
        rng = random.Random(1)
        for _ in range(3000):
            rd, rs1, rs2 = rng.randrange(32), rng.randrange(32), rng.randrange(32)
            imm12 = rng.randrange(-2048, 2048)
            immb = rng.randrange(-2048, 2048) * 2
            immj = rng.randrange(-(1 << 19), 1 << 19) * 2
            imm20 = rng.randrange(1 << 20)
            name = rng.choice(list(R_OPS) + list(I_OPS) + list(B_OPS) +
                              ['lw', 'sw', 'lui', 'auipc', 'jal', 'jalr', 'qmul'])
            if name in R_OPS or name == 'qmul':
                word, want = asm(name, rd, rs1, rs2), Decoded(name, rd, rs1, rs2, 0)
            elif name in I_OPS or name in ('lw', 'jalr'):
                word = asm(name, rd, imm12, rs1) if name in ('lw', 'jalr') else asm(name, rd, rs1, imm12)
                want = Decoded(name, rd, rs1, 0, imm12)
            elif name == 'sw':
                word, want = asm('sw', rs2, imm12, rs1), Decoded('sw', 0, rs1, rs2, imm12)
            elif name in B_OPS:
                word, want = asm(name, rs1, rs2, immb), Decoded(name, 0, rs1, rs2, immb)
            elif name in ('lui', 'auipc'):
                word, want = asm(name, rd, imm20), Decoded(name, rd, 0, 0, imm20 << 12)
            else:
                word, want = asm('jal', rd, immj), Decoded('jal', rd, 0, 0, immj)
            self.assertEqual(iss.decode(word), want, '%08x %s' % (word, name))

    def test_illegal_encodings(self):
        illegal = [
            0x00000000,                     # 全 0
            0xffffffff,                     # 全 1
            r_type(0x01, 3, 2, 0, 1, 0b0110011),    # mul（M 扩展）
            r_type(0x20, 3, 2, 1, 1, 0b0110011),    # funct7 不对的 sll
            r_type(0x20, 3, 2, 1, 1, 0b0010011),    # slli 带 funct7 = 0100000
            r_type(0x01, 3, 2, 5, 1, 0b0010011),    # srli 带奇怪的 funct7
            i_type(0, 2, 0, 1, 0b0000011),          # lb
            i_type(0, 2, 4, 1, 0b0000011),          # lbu
            s_type(0, 2, 1, 0, 0b0100011),          # sb
            b_type(8, 2, 1, 2),                     # funct3 = 010 的分支
            i_type(0, 2, 1, 1, 0b1100111),          # jalr funct3 != 0
            0x0000000f,                             # fence
            0x00000073,                             # ecall
            0x00100073,                             # ebreak
            0x30002573,                             # csrr a0, mstatus
            r_type(0, 3, 2, 1, 1, 0b0001011),       # custom-0 funct3 = 001（qadd 留位）
            r_type(1, 3, 2, 0, 1, 0b0001011),       # custom-0 funct7 != 0
            0x00000001,                             # 压缩指令空间
        ]
        for word in illegal:
            with self.subTest(word='%08x' % word):
                with self.assertRaises(iss.IllegalInstruction):
                    iss.decode(word)


# ---------------------------------------------------------------- 语义

class TestSemantics(unittest.TestCase):
    def regs_after(self, body, isa='rv32i_qmul', dmem=()):
        return run(body + FINISH_OK, dmem, isa).regs

    def alu(self, name, a, b):
        """x1 = a，x2 = b，执行 name x3, x1, x2，返回 x3。"""
        return self.regs_after(li(1, a) + li(2, b) + [asm(name, 3, 1, 2)])[3]

    def alui(self, name, a, imm):
        return self.regs_after(li(1, a) + [asm(name, 3, 1, imm)])[3]

    def test_register_ops(self):
        cases = [
            ('add', 0x7fffffff, 1, 0x80000000),
            ('add', 0xffffffff, 1, 0),
            ('add', 0xfffffffd, 0xfffffffb, 0xfffffff8),
            ('sub', 0, 1, 0xffffffff),
            ('sub', 0x80000000, 1, 0x7fffffff),
            ('slt', 0xffffffff, 1, 1),
            ('slt', 1, 0xffffffff, 0),
            ('slt', 0x80000000, 0x7fffffff, 1),
            ('slt', 5, 5, 0),
            ('sltu', 0xffffffff, 1, 0),
            ('sltu', 1, 0xffffffff, 1),
            ('sltu', 0x7fffffff, 0x80000000, 1),
            ('sltu', 3, 3, 0),
            ('and', 0xf0f0ff00, 0x0ff0f0f0, 0x00f0f000),
            ('or', 0xf0f00000, 0x0000f0f0, 0xf0f0f0f0),
            ('xor', 0xffff0000, 0xff00ff00, 0x00ffff00),
            ('sll', 1, 31, 0x80000000),
            ('sll', 0x12345678, 0, 0x12345678),
            ('sll', 1, 33, 2),                      # 只取低 5 位
            ('srl', 0x80000000, 31, 1),
            ('srl', 0xf0000000, 4, 0x0f000000),
            ('sra', 0xf0000000, 4, 0xff000000),
            ('sra', 0x80000000, 31, 0xffffffff),
            ('sra', 0x70000000, 4, 0x07000000),
            ('srl', 0x80000000, 0xffffffe0, 0x80000000),  # 移位量低 5 位为 0
        ]
        for name, a, b, want in cases:
            with self.subTest(op=name, a=hex(a), b=hex(b)):
                self.assertEqual(self.alu(name, a, b), want)

    def test_immediate_ops(self):
        cases = [
            ('addi', 0, -1, 0xffffffff),
            ('addi', 0x7fffffff, 1, 0x80000000),
            ('addi', 5, -2048, 0xfffff805),
            ('slti', 0xfffffffe, -1, 1),
            ('slti', 0, -1, 0),
            ('sltiu', 5, -1, 1),            # -1 当无符号是 0xffffffff
            ('sltiu', 0xffffffff, -1, 0),
            ('sltiu', 0, 1, 1),
            ('xori', 0x12345678, -1, 0xedcba987),
            ('ori', 0x12345000, -2048, 0xfffff800),
            ('ori', 0, 0x7ff, 0x7ff),
            ('andi', 0x12345678, -16, 0x12345670),
            ('andi', 0x12345678, 0x0ff, 0x78),
            ('slli', 3, 31, 0x80000000),
            ('srli', 0x80000000, 31, 1),
            ('srai', 0x80000000, 31, 0xffffffff),
            ('srai', 0x80000000, 0, 0x80000000),
        ]
        for name, a, imm, want in cases:
            with self.subTest(op=name, a=hex(a), imm=imm):
                self.assertEqual(self.alui(name, a, imm), want)

    def test_lui_auipc(self):
        regs = self.regs_after([asm('lui', 1, 0x80000), asm('lui', 2, 0xfffff),
                                asm('auipc', 3, 0x00001), asm('auipc', 4, 0xfffff)])
        self.assertEqual(regs[1], 0x80000000)
        self.assertEqual(regs[2], 0xfffff000)
        self.assertEqual(regs[3], 0x8 + 0x1000)             # auipc 在 0x8
        self.assertEqual(regs[4], (0xc + 0xfffff000) & 0xffffffff)

    def test_x0_is_not_writable(self):
        regs = self.regs_after([asm('addi', 0, 0, 5), asm('lui', 0, 1), asm('add', 1, 0, 0)])
        self.assertEqual(regs[0], 0)
        self.assertEqual(regs[1], 0)

    def test_lw_sw(self):
        dmem = [0x11111111, 0x22222222, 0x33333333]
        prog = li(1, 0x00010000) + li(2, 0x00010800) + [
            asm('lw', 3, 4, 1),             # 0x22222222
            asm('lw', 4, -2048, 2),         # 0x11111111
            asm('sw', 3, 8, 1),
            asm('lw', 5, 8, 1),
            asm('sw', 4, -4, 2),            # 0x000107fc
            asm('lw', 6, 2044, 1),
        ]
        m = run(prog + FINISH_OK, dmem)
        self.assertEqual(m.regs[3], 0x22222222)
        self.assertEqual(m.regs[4], 0x11111111)
        self.assertEqual(m.regs[5], 0x22222222)
        self.assertEqual(m.regs[6], 0x11111111)
        self.assertEqual(m.dmem[2], 0x22222222)
        self.assertEqual(m.dmem[511], 0x11111111)

    def branch_taken(self, name, a, b):
        # 跳了 x5 = 1，没跳 x5 = 0
        prog = li(1, a) + li(2, b) + [
            asm('addi', 5, 0, 1),
            asm(name, 1, 2, 8),             # 跳过下一条
            asm('addi', 5, 0, 0),
        ]
        return self.regs_after(prog)[5] == 1

    def test_branches(self):
        cases = [
            ('beq', 5, 5, True), ('beq', 5, 4, False), ('beq', 0x80000001, 1, False),
            ('bne', 5, 5, False), ('bne', 5, 6, True),
            ('blt', 0xffffffff, 1, True), ('blt', 1, 0xffffffff, False), ('blt', 3, 3, False),
            ('bge', 0xffffffff, 1, False), ('bge', 1, 0xffffffff, True), ('bge', 3, 3, True),
            ('bltu', 0xffffffff, 1, False), ('bltu', 1, 0xffffffff, True), ('bltu', 3, 3, False),
            ('bgeu', 0xffffffff, 1, True), ('bgeu', 1, 0xffffffff, False), ('bgeu', 3, 3, True),
        ]
        for name, a, b, taken in cases:
            with self.subTest(op=name, a=hex(a), b=hex(b)):
                self.assertEqual(self.branch_taken(name, a, b), taken)

    def test_backward_branch(self):
        # x1 = 3；循环 x1 -= 1 直到 0，x2 计次数
        prog = [asm('addi', 1, 0, 3),
                asm('addi', 2, 2, 1),       # 0x4
                asm('addi', 1, 1, -1),
                asm('bne', 1, 0, -8)]       # 回到 0x4
        self.assertEqual(self.regs_after(prog)[2], 3)

    def test_jal_jalr(self):
        prog = [
            asm('jal', 1, 12),              # 0x0 -> 0xc，x1 = 4
            asm('addi', 9, 0, 1),           # 0x4 不应执行
            asm('jal', 0, 16),              # 0x8 -> 0x18
            asm('addi', 3, 0, 0x21),        # 0xc：x3 = 0x21
            asm('jalr', 4, -0x18, 3),       # 0x10：目标 0x21 - 0x18 = 0x9，最低位清零得 0x8；x4 = 0x14
            asm('addi', 9, 0, 2),           # 0x14 不应执行
            asm('jalr', 1, 0, 1),           # 0x18：rd = rs1，先算目标 4 再写 x1 = 0x1c
        ]
        # 0x4 处再放一条跳到结束的 jal，覆盖"不应执行"那条
        prog[1] = asm('jal', 0, 0x20 - 0x4)
        prog += [asm('addi', 9, 0, 3)] + FINISH_OK      # 0x1c 不应执行；0x20 结束
        m = run(prog)
        self.assertEqual(m.regs[1], 0x1c)
        self.assertEqual(m.regs[4], 0x14)
        self.assertEqual(m.regs[9], 0)

    def test_qmul_values(self):
        cases = [
            (0, 0, 0), (1, 1, 1), (3328, 3328, 1),          # (-1)·(-1) = 1
            (3329, 5, 0), (17, 17, 289), (1000, 1000, 1000000 % 3329),
            (4095, 4095, (4095 * 4095) % 3329),
            (0xfffff001, 0x80000002, 2),                    # 只取低 12 位：1 * 2
            (0xffffffff, 0xffffffff, (4095 * 4095) % 3329),
        ]
        for a, b, want in cases:
            with self.subTest(a=hex(a), b=hex(b)):
                self.assertEqual(self.alu('qmul', a, b), want)

    def test_qmul_random_against_definition(self):
        # 在指令层面抽查：任意 32 位输入，与 (a[11:0] * b[11:0]) % 3329 比。
        # 每个程序 150 组（900 条指令），放得进 1024 字的指令存储器
        rng = random.Random(2)
        for batch in range(10):
            prog, want = [], {}
            for k in range(150):
                a, b = rng.getrandbits(32), rng.getrandbits(32)
                prog += li(1, a) + li(2, b) + [asm('qmul', 3, 1, 2),
                                              asm('sw', 3, 4 * k, 10)]
                want[k] = ((a & 0xfff) * (b & 0xfff)) % 3329
            m = run(li(10, 0x00010000) + prog + FINISH_OK)
            for k, v in want.items():
                self.assertEqual(m.dmem[k], v)


def barrett_qmul(a, b):
    """设计文档第七节的硬件算法，与参考模型无关的独立实现。"""
    p = (a & 0xfff) * (b & 0xfff)
    q = (p * 5039) >> 24
    r = p - q * 3329
    assert 0 <= r < 2 * 3329, (a, b, r)
    return r - 3329 if r >= 3329 else r


class TestQmul(unittest.TestCase):
    def test_wide_sample(self):
        rng = random.Random(3)
        edges = [0, 1, 2, 3328, 3329, 3330, 4094, 4095]
        pairs = [(a, b) for a in edges for b in edges]
        pairs += [(a, rng.randrange(4096)) for a in range(4096)]
        pairs += [(rng.getrandbits(32), rng.getrandbits(32)) for _ in range(20000)]
        for a, b in pairs:
            want = ((a & 0xfff) * (b & 0xfff)) % 3329
            self.assertEqual(iss.qmul(a, b), want)
            self.assertEqual(barrett_qmul(a, b), want)

    @unittest.skipUnless(os.environ.get('MINICPU_SLOW'), 'set MINICPU_SLOW=1 for the exhaustive check')
    def test_barrett_exhaustive(self):
        for a in range(4096):
            for b in range(4096):
                self.assertEqual(barrett_qmul(a, b), iss.qmul(a, b))


# ---------------------------------------------------------------- 轨迹、I/O

class TestTraceAndIO(unittest.TestCase):
    def test_trace_lines(self):
        prog = li(1, 0x00010000) + [
            asm('addi', 2, 0, 0x2a),        # 0x08：R
            asm('addi', 0, 0, 1),           # 0x0c：写 x0，不记
            asm('sw', 2, 4, 1),             # 0x10：M
            asm('lui', 3, 0x80000),         # 0x14：R
            asm('lw', 4, 4, 3),             # 0x18：读 CYCLE，X
            asm('lw', 0, 8, 3),             # 0x1c：读 INSTRET 到 x0，不记
            asm('addi', 5, 0, 7),
            asm('sw', 5, 0x14, 3),          # 0x24：MARK
            asm('sw', 2, 0, 3),             # 0x28：FINISH 42
            asm('addi', 6, 0, 1),           # 不应执行
        ]
        marks = []
        m = Machine(prog, [], 'rv32i', on_mark=lambda d, n: marks.append((d, n)))
        self.assertEqual(m.run(100), 42)
        self.assertEqual(m.trace, [
            'R 00000000 01 00010000',
            'R 00000004 01 00010000',
            'R 00000008 02 0000002a',
            'M 00000010 00010004 0000002a',
            'R 00000014 03 80000000',
            'X 00000018 04 00000000',
            'R 00000020 05 00000007',
            'M 00000024 80000014 00000007',
            'M 00000028 80000000 0000002a',
        ])
        self.assertEqual(marks, [(7, 10)])
        self.assertEqual(m.instret, 11)
        self.assertEqual(m.regs[6], 0)

    def test_counter_values_are_plausible(self):
        prog = [asm('lui', 3, 0x80000), asm('lw', 1, 8, 3), asm('lw', 2, 8, 3),
                asm('lw', 4, 0x0c, 3), asm('lw', 5, 0x10, 3)] + FINISH_OK
        m = run(prog)
        self.assertEqual(m.regs[2] - m.regs[1], 1)
        self.assertEqual((m.regs[4], m.regs[5]), (0, 0))


class TestErrors(unittest.TestCase):
    def expect_error(self, prog, pattern, isa='rv32i_qmul', dmem=(), **kw):
        with self.assertRaises(SimError) as cm:
            run(prog, dmem, isa, **kw)
        self.assertRegex(cm.exception.message, pattern)
        return cm.exception

    def test_illegal_instruction(self):
        e = self.expect_error([asm('addi', 1, 0, 1), 0x00000000], 'illegal instruction')
        self.assertEqual(e.pc, 4)

    def test_isa_subsets(self):
        self.expect_error([asm('addi', 1, 0, 1)] + FINISH_OK, 'not in ISA subset base9', 'base9')
        self.expect_error([asm('sub', 1, 0, 0)] + FINISH_OK, 'not in ISA subset base9', 'base9')
        self.expect_error([asm('qmul', 1, 0, 0)] + FINISH_OK, 'not in ISA subset rv32i', 'rv32i')
        # base9 的九条在 base9 下都能执行
        prog = [asm('lui', 1, 0x10), asm('ori', 2, 0, 3), asm('add', 3, 2, 2),
                asm('slt', 4, 2, 3), asm('sltu', 5, 3, 2), asm('sw', 3, 0, 1),
                asm('lw', 6, 0, 1), asm('beq', 0, 0, 8), 0, asm('jal', 7, 4)] + FINISH_OK
        m = run(prog, isa='base9')
        self.assertEqual(m.regs[6], 6)
        self.assertEqual(m.regs[7], 0x28)

    def test_fetch_out_of_range(self):
        self.expect_error([asm('jal', 0, 0xffc)] + [NOP] * 1022 + [asm('jal', 0, 8)],
                          'fetch out of range')
        self.expect_error([NOP] * 1024, 'fetch out of range')     # 顺序执行越过末尾

    def test_jump_target_misaligned(self):
        self.expect_error([asm('addi', 1, 0, 6), asm('jalr', 0, 0, 1)], 'not a multiple of 4')
        self.expect_error([asm('jal', 0, 2)], 'not a multiple of 4')
        self.expect_error([asm('beq', 0, 0, 6)], 'not a multiple of 4')
        # 不成立的分支不检查目标
        run([asm('bne', 0, 0, 6)] + FINISH_OK)

    def test_memory_errors(self):
        base = li(1, 0x00010000)
        self.expect_error(base + [asm('lw', 2, 2, 1)], 'misaligned load')
        self.expect_error(base + [asm('sw', 2, 1, 1)], 'misaligned store')
        self.expect_error([asm('lw', 2, 0, 0)], 'load address 00000000 out of range')
        self.expect_error(li(1, 0x00011000) + [asm('lw', 2, 0, 1)], 'out of range')
        self.expect_error(li(1, 0x00011000) + [asm('sw', 2, 0, 1)], 'out of range')
        self.expect_error(base + [asm('sw', 2, -4, 1)], 'out of range')
        self.expect_error(li(1, 0x40000000) + [asm('sw', 2, 0, 1)], 'out of range')

    def test_io_errors(self):
        io = [asm('lui', 1, 0x80000)]
        self.expect_error(io + [asm('lw', 2, 0x00, 1)], 'write-only')        # 读 FINISH
        self.expect_error(io + [asm('lw', 2, 0x14, 1)], 'write-only')        # 读 MARK
        for off in (0x04, 0x08, 0x0c, 0x10):
            self.expect_error(io + [asm('sw', 0, off, 1)], 'read-only counter')
        self.expect_error(io + [asm('lw', 2, 0x18, 1)], 'undefined I/O')
        self.expect_error(io + [asm('sw', 2, 0x7fc, 1)], 'undefined I/O')

    def test_max_steps(self):
        self.expect_error([asm('jal', 0, 0)], 'no FINISH after 50', max_steps=50)

    def test_check_uninit(self):
        self.expect_error([asm('add', 1, 2, 0)] + FINISH_OK, 'uninitialized register x2',
                          check_uninit=True)
        run([asm('add', 1, 0, 0), asm('add', 2, 1, 1)] + FINISH_OK, check_uninit=True)

    def test_check_pad(self):
        nop2 = [NOP, NOP]
        # 依赖之间只隔一条：报错；隔两条：通过
        self.expect_error([asm('addi', 1, 0, 1), NOP, asm('add', 2, 1, 1)] + FINISH_OK,
                          'x1 is read 2 instruction', check_pad=True)
        run([asm('addi', 1, 0, 1)] + nop2 + [asm('add', 2, 1, 1)] + nop2 + FINISH_OK[:1] +
            nop2 + FINISH_OK[1:], check_pad=True)
        # 分支后面不是三条 add x0,x0,x0：报错
        self.expect_error([asm('beq', 0, 0, 16), NOP, NOP, asm('addi', 0, 0, 0)] + FINISH_OK,
                          'three add x0,x0,x0', check_pad=True)
        # store 的数据寄存器也算读
        self.expect_error([asm('lui', 1, 0x10), NOP, NOP, asm('addi', 2, 0, 5),
                           asm('sw', 2, 0, 1)] + FINISH_OK, 'x2 is read 1', check_pad=True)


class TestFilesAndCli(unittest.TestCase):
    def test_load_hex(self):
        with tempfile.TemporaryDirectory() as d:
            good = os.path.join(d, 'good.hex')
            with open(good, 'w') as f:
                f.write('00000033\n\nDEADBEEF\n')
            self.assertEqual(iss.load_hex(good), [0x33, 0xdeadbeef])
            for text in ('0x000033\n', '1234567\n', '123456789\n', 'gggggggg\n',
                         '00000000\n' * 1025):
                bad = os.path.join(d, 'bad.hex')
                with open(bad, 'w') as f:
                    f.write(text)
                with self.assertRaises(ValueError):
                    iss.load_hex(bad)

    def run_cli(self, prog, *extra):
        with tempfile.TemporaryDirectory() as d:
            imem, dmem, trace = (os.path.join(d, n) for n in ('i.hex', 'd.hex', 't.trace'))
            with open(imem, 'w') as f:
                f.write(''.join('%08x\n' % w for w in prog))
            open(dmem, 'w').close()
            out, err = io.StringIO(), io.StringIO()
            with redirect_stdout(out), redirect_stderr(err):
                code = iss.main(['--isa', 'base9', '--imem', imem, '--dmem', dmem,
                                 '--trace', trace] + list(extra))
            with open(trace) as f:
                return code, out.getvalue(), err.getvalue(), f.read()

    def test_cli_finish(self):
        prog = [asm('ori', 1, 0, 9), asm('lui', 2, 0x80000), asm('sw', 1, 0x14, 2),
                asm('sw', 1, 0, 2)]
        code, out, err, trace = self.run_cli(prog)
        self.assertEqual(code, 0)
        self.assertEqual(out, 'MARK 00000009 instret=3\nFINISH code=9 instret=4\n')
        self.assertEqual(trace.splitlines()[-1], 'M 0000000c 80000000 00000009')

    def test_cli_error(self):
        code, out, err, trace = self.run_cli([asm('ori', 1, 0, 1), asm('addi', 1, 0, 1)])
        self.assertEqual(code, 1)
        self.assertIn('pc=00000004', err)
        self.assertIn('not in ISA subset base9', err)
        self.assertEqual(trace, 'R 00000000 01 00000001\n')       # 出错前的部分轨迹


if __name__ == '__main__':
    unittest.main()
