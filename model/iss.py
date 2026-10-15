#!/usr/bin/env python3
"""mini-cpu 指令级参考模型（ISS）。

一次执行一条指令，没有流水线。读入与 CPU 相同的 imem.hex / dmem.hex，
输出期望轨迹 expect.trace（格式见实现约定第 6 节）。

    python3 model/iss.py --isa {base9|rv32i|rv32i_qmul} \
        --imem imem.hex --dmem dmem.hex --trace expect.trace [--max-steps N]

正常结束（写了 FINISH）时退出码为 0，打印 "FINISH code=<d> instret=<d>"；
写 MARK 时打印 "MARK <data> instret=<d>"。instret 是已执行的指令数，
包括这条 store 本身。

下列情况一律报错退出（退出码 1，打印 PC 和原因）：非法指令、不在所选
ISA 子集里的指令、取指越界、访存越界、访存不对齐（包括跳转目标不是 4 的
倍数）、读 FINISH/MARK、写只读计数器、超过最大步数。

附加的检查选项（构建脚本使用）：
  --check-pad     按阶段 1 的 CPU（无转发、无冲刷，只有寄存器堆旁路）检查
                  空指令填充是否足够：读寄存器的指令与最近一次写它的指令之间
                  至少隔两条；每条分支和跳转后面紧跟三条 add x0,x0,x0。
  --check-uninit  读到从未写过的寄存器（x0 除外）时报错。

只用 Python 标准库。
"""

import argparse
import sys
from collections import namedtuple

MASK32 = 0xFFFFFFFF

# ---------------------------------------------------------------- 地址空间

IMEM_BASE = 0x00000000
DMEM_BASE = 0x00010000
MEM_WORDS = 1024                     # 两块存储器各 4 KB
MEM_BYTES = MEM_WORDS * 4

IO_BASE = 0x80000000
IO_FINISH = 0x00
IO_CYCLE = 0x04
IO_INSTRET = 0x08
IO_STALLS = 0x0C
IO_FLUSHES = 0x10
IO_MARK = 0x14
IO_COUNTERS = (IO_CYCLE, IO_INSTRET, IO_STALLS, IO_FLUSHES)

NOP = 0x00000033                     # add x0, x0, x0

# ---------------------------------------------------------------- ISA 子集

BASE9 = ('add', 'slt', 'sltu', 'ori', 'lui', 'lw', 'sw', 'beq', 'jal')
RV32I = BASE9 + ('sub', 'and', 'or', 'xor', 'sll', 'srl', 'sra',
                 'addi', 'andi', 'xori', 'slti', 'sltiu', 'slli', 'srli', 'srai',
                 'bne', 'blt', 'bge', 'bltu', 'bgeu', 'jalr', 'auipc')
RV32I_QMUL = RV32I + ('qmul',)

ISA_SUBSETS = {
    'base9': frozenset(BASE9),
    'rv32i': frozenset(RV32I),
    'rv32i_qmul': frozenset(RV32I_QMUL),
}

QMUL_MODULUS = 3329

# 各类指令读哪些源寄存器、是否写 rd
R_TYPE = ('add', 'sub', 'sll', 'slt', 'sltu', 'xor', 'srl', 'sra', 'or', 'and', 'qmul')
I_ALU = ('addi', 'slti', 'sltiu', 'xori', 'ori', 'andi', 'slli', 'srli', 'srai')
BRANCHES = ('beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu')
JUMPS = ('jal', 'jalr')


def uses_rs1(name):
    return name not in ('lui', 'auipc', 'jal')


def uses_rs2(name):
    return name in R_TYPE or name in BRANCHES or name == 'sw'


def writes_rd(name):
    return name not in BRANCHES and name != 'sw'


# ---------------------------------------------------------------- 译码

Decoded = namedtuple('Decoded', 'name rd rs1 rs2 imm')


class IllegalInstruction(Exception):
    pass


def sign_extend(value, bits):
    """把 bits 位的补码数扩展成 Python 整数。"""
    sign = 1 << (bits - 1)
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & sign else value


def bits(inst, hi, lo):
    """取 inst[hi:lo]。"""
    return (inst >> lo) & ((1 << (hi - lo + 1)) - 1)


def imm_i(inst):
    return sign_extend(bits(inst, 31, 20), 12)


def imm_s(inst):
    return sign_extend((bits(inst, 31, 25) << 5) | bits(inst, 11, 7), 12)


def imm_b(inst):
    value = ((bits(inst, 31, 31) << 12) | (bits(inst, 7, 7) << 11) |
             (bits(inst, 30, 25) << 5) | (bits(inst, 11, 8) << 1))
    return sign_extend(value, 13)


def imm_u(inst):
    return inst & 0xFFFFF000


def imm_j(inst):
    value = ((bits(inst, 31, 31) << 20) | (bits(inst, 19, 12) << 12) |
             (bits(inst, 20, 20) << 11) | (bits(inst, 30, 21) << 1))
    return sign_extend(value, 21)


R_FUNCT = {
    # (funct7, funct3): name
    (0x00, 0): 'add', (0x20, 0): 'sub', (0x00, 1): 'sll', (0x00, 2): 'slt',
    (0x00, 3): 'sltu', (0x00, 4): 'xor', (0x00, 5): 'srl', (0x20, 5): 'sra',
    (0x00, 6): 'or', (0x00, 7): 'and',
}
I_FUNCT = {0: 'addi', 2: 'slti', 3: 'sltiu', 4: 'xori', 6: 'ori', 7: 'andi'}
B_FUNCT = {0: 'beq', 1: 'bne', 4: 'blt', 5: 'bge', 6: 'bltu', 7: 'bgeu'}


def decode(inst):
    """把 32 位指令字译成 Decoded；不认识的编码抛 IllegalInstruction。

    imm 已按格式拼好并做了符号扩展（lui/auipc 的 imm 是放在高 20 位的值）。
    """
    opcode = bits(inst, 6, 0)
    rd = bits(inst, 11, 7)
    funct3 = bits(inst, 14, 12)
    rs1 = bits(inst, 19, 15)
    rs2 = bits(inst, 24, 20)
    funct7 = bits(inst, 31, 25)

    if opcode == 0b0110011:
        name = R_FUNCT.get((funct7, funct3))
        if name is None:
            raise IllegalInstruction('unknown OP funct7=%02x funct3=%d' % (funct7, funct3))
        return Decoded(name, rd, rs1, rs2, 0)

    if opcode == 0b0010011:
        if funct3 in I_FUNCT:
            return Decoded(I_FUNCT[funct3], rd, rs1, 0, imm_i(inst))
        # 移位：移位量在 rs2 字段，funct7 区分逻辑/算术
        if funct3 == 1 and funct7 == 0x00:
            return Decoded('slli', rd, rs1, 0, rs2)
        if funct3 == 5 and funct7 == 0x00:
            return Decoded('srli', rd, rs1, 0, rs2)
        if funct3 == 5 and funct7 == 0x20:
            return Decoded('srai', rd, rs1, 0, rs2)
        raise IllegalInstruction('unknown OP-IMM funct7=%02x funct3=%d' % (funct7, funct3))

    if opcode == 0b0000011:
        if funct3 == 2:
            return Decoded('lw', rd, rs1, 0, imm_i(inst))
        raise IllegalInstruction('unsupported load funct3=%d (only lw)' % funct3)

    if opcode == 0b0100011:
        if funct3 == 2:
            return Decoded('sw', 0, rs1, rs2, imm_s(inst))
        raise IllegalInstruction('unsupported store funct3=%d (only sw)' % funct3)

    if opcode == 0b1100011:
        if funct3 in B_FUNCT:
            return Decoded(B_FUNCT[funct3], 0, rs1, rs2, imm_b(inst))
        raise IllegalInstruction('unknown BRANCH funct3=%d' % funct3)

    if opcode == 0b0110111:
        return Decoded('lui', rd, 0, 0, imm_u(inst))

    if opcode == 0b0010111:
        return Decoded('auipc', rd, 0, 0, imm_u(inst))

    if opcode == 0b1101111:
        return Decoded('jal', rd, 0, 0, imm_j(inst))

    if opcode == 0b1100111:
        if funct3 == 0:
            return Decoded('jalr', rd, rs1, 0, imm_i(inst))
        raise IllegalInstruction('unknown JALR funct3=%d' % funct3)

    if opcode == 0b0001011:
        if funct3 == 0 and funct7 == 0x00:
            return Decoded('qmul', rd, rs1, rs2, 0)
        raise IllegalInstruction('unknown custom-0 funct7=%02x funct3=%d' % (funct7, funct3))

    raise IllegalInstruction('unknown opcode %s' % format(opcode, '07b'))


def qmul(a, b):
    """定制指令 qmul：a、b 取低 12 位、按无符号数，结果 (a*b) mod 3329。"""
    return ((a & 0xFFF) * (b & 0xFFF)) % QMUL_MODULUS


def to_signed(value):
    return value - (1 << 32) if value & 0x80000000 else value


# ---------------------------------------------------------------- 模拟器

class SimError(Exception):
    def __init__(self, pc, message):
        super().__init__(message)
        self.pc = pc
        self.message = message

    def __str__(self):
        return 'pc=%08x: %s' % (self.pc, self.message)


class Machine:
    def __init__(self, imem, dmem, isa='rv32i_qmul', check_pad=False,
                 check_uninit=False, on_mark=None):
        if isa not in ISA_SUBSETS:
            raise ValueError('unknown ISA subset %r' % isa)
        self.imem = list(imem) + [0] * (MEM_WORDS - len(imem))
        self.dmem = list(dmem) + [0] * (MEM_WORDS - len(dmem))
        if len(self.imem) != MEM_WORDS or len(self.dmem) != MEM_WORDS:
            raise ValueError('memory image larger than %d words' % MEM_WORDS)
        self.isa = isa
        self.allowed = ISA_SUBSETS[isa]
        self.check_pad = check_pad
        self.check_uninit = check_uninit
        self.on_mark = on_mark

        self.regs = [0] * 32
        self.pc = 0
        self.instret = 0              # 已执行完的指令数
        self.trace = []               # 轨迹行（不含换行）
        self.finish_code = None       # 写了 FINISH 之后是结果码
        self.marks = []               # (data, instret)

        self.last_write = [None] * 32     # --check-pad：最近一次写该寄存器的指令序号
        self.written = [True] + [False] * 31

    # ---- 寄存器

    def read_reg(self, pc, r):
        if self.check_uninit and not self.written[r]:
            raise SimError(pc, 'read of uninitialized register x%d' % r)
        return self.regs[r]

    def write_reg(self, pc, r, value, counter=False):
        """写 rd 并记轨迹。counter=True 表示值读自计数器，记 X 行（值不比对）。"""
        if r == 0:
            return
        self.regs[r] = value & MASK32
        self.written[r] = True
        self.last_write[r] = self.instret
        if counter:
            self.trace.append('X %08x %02x 00000000' % (pc, r))
        else:
            self.trace.append('R %08x %02x %08x' % (pc, r, self.regs[r]))

    # ---- 访存

    def load(self, pc, addr):
        """返回 (读出的值, 是否读自计数器)。"""
        if addr % 4:
            raise SimError(pc, 'misaligned load from %08x' % addr)
        if addr & 0x80000000:
            offset = addr - IO_BASE
            if offset in IO_COUNTERS:
                # 参考模型没有周期的概念，周期数就按每拍一条给；值不参与比对
                value = {IO_CYCLE: self.instret, IO_INSTRET: self.instret,
                         IO_STALLS: 0, IO_FLUSHES: 0}[offset]
                return value, True
            if offset in (IO_FINISH, IO_MARK):
                raise SimError(pc, 'read from write-only I/O register at %08x' % addr)
            raise SimError(pc, 'load from undefined I/O address %08x' % addr)
        if DMEM_BASE <= addr < DMEM_BASE + MEM_BYTES:
            return self.dmem[(addr - DMEM_BASE) // 4], False
        raise SimError(pc, 'load address %08x out of range' % addr)

    def store(self, pc, addr, value):
        if addr % 4:
            raise SimError(pc, 'misaligned store to %08x' % addr)
        if addr & 0x80000000:
            offset = addr - IO_BASE
            if offset == IO_FINISH:
                self.trace.append('M %08x %08x %08x' % (pc, addr, value))
                self.finish_code = value
                return
            if offset == IO_MARK:
                self.trace.append('M %08x %08x %08x' % (pc, addr, value))
                # instret 包括这条 store 本身
                self.marks.append((value, self.instret + 1))
                if self.on_mark:
                    self.on_mark(value, self.instret + 1)
                return
            if offset in IO_COUNTERS:
                raise SimError(pc, 'write to read-only counter at %08x' % addr)
            raise SimError(pc, 'store to undefined I/O address %08x' % addr)
        if DMEM_BASE <= addr < DMEM_BASE + MEM_BYTES:
            self.dmem[(addr - DMEM_BASE) // 4] = value
            self.trace.append('M %08x %08x %08x' % (pc, addr, value))
            return
        raise SimError(pc, 'store address %08x out of range' % addr)

    # ---- 取指、检查

    def fetch(self, pc):
        if pc % 4:
            raise SimError(pc, 'misaligned instruction fetch')
        if not IMEM_BASE <= pc < IMEM_BASE + MEM_BYTES:
            raise SimError(pc, 'instruction fetch out of range')
        return self.imem[(pc - IMEM_BASE) // 4]

    def check_padding(self, pc, d):
        """阶段 1 的 CPU 没有转发和冲刷，用这里的规则保证 pad 变体在它上面也对。"""
        sources = []
        if uses_rs1(d.name):
            sources.append(d.rs1)
        if uses_rs2(d.name):
            sources.append(d.rs2)
        for r in sources:
            last = self.last_write[r]
            if r != 0 and last is not None and self.instret - last < 3:
                raise SimError(pc, 'pad check: x%d is read %d instruction(s) after it was '
                               'written; need at least two instructions in between'
                               % (r, self.instret - last))
        if d.name in BRANCHES or d.name in JUMPS:
            for k in (1, 2, 3):
                slot = pc + 4 * k
                if not (slot < IMEM_BASE + MEM_BYTES and self.imem[slot // 4] == NOP):
                    raise SimError(pc, 'pad check: %s must be followed by three '
                                   'add x0,x0,x0 (word at %08x is not)' % (d.name, slot))

    # ---- 执行一条指令

    def step(self):
        pc = self.pc
        inst = self.fetch(pc)
        try:
            d = decode(inst)
        except IllegalInstruction as e:
            raise SimError(pc, 'illegal instruction %08x (%s)' % (inst, e))
        if d.name not in self.allowed:
            raise SimError(pc, '%s (%08x) is not in ISA subset %s' % (d.name, inst, self.isa))
        if self.check_pad:
            self.check_padding(pc, d)

        name = d.name
        a = self.read_reg(pc, d.rs1) if uses_rs1(name) else 0
        b = self.read_reg(pc, d.rs2) if uses_rs2(name) else 0
        imm = d.imm
        next_pc = (pc + 4) & MASK32

        # 运算类：结果写 rd
        if name == 'add':
            self.write_reg(pc, d.rd, a + b)
        elif name == 'sub':
            self.write_reg(pc, d.rd, a - b)
        elif name == 'sll':
            self.write_reg(pc, d.rd, a << (b & 31))
        elif name == 'slt':
            self.write_reg(pc, d.rd, 1 if to_signed(a) < to_signed(b) else 0)
        elif name == 'sltu':
            self.write_reg(pc, d.rd, 1 if a < b else 0)
        elif name == 'xor':
            self.write_reg(pc, d.rd, a ^ b)
        elif name == 'srl':
            self.write_reg(pc, d.rd, a >> (b & 31))
        elif name == 'sra':
            self.write_reg(pc, d.rd, to_signed(a) >> (b & 31))
        elif name == 'or':
            self.write_reg(pc, d.rd, a | b)
        elif name == 'and':
            self.write_reg(pc, d.rd, a & b)
        elif name == 'qmul':
            self.write_reg(pc, d.rd, qmul(a, b))
        elif name == 'addi':
            self.write_reg(pc, d.rd, a + imm)
        elif name == 'slti':
            self.write_reg(pc, d.rd, 1 if to_signed(a) < imm else 0)
        elif name == 'sltiu':
            self.write_reg(pc, d.rd, 1 if a < (imm & MASK32) else 0)
        elif name == 'xori':
            self.write_reg(pc, d.rd, a ^ (imm & MASK32))
        elif name == 'ori':
            self.write_reg(pc, d.rd, a | (imm & MASK32))
        elif name == 'andi':
            self.write_reg(pc, d.rd, a & (imm & MASK32))
        elif name == 'slli':
            self.write_reg(pc, d.rd, a << imm)
        elif name == 'srli':
            self.write_reg(pc, d.rd, a >> imm)
        elif name == 'srai':
            self.write_reg(pc, d.rd, to_signed(a) >> imm)
        elif name == 'lui':
            self.write_reg(pc, d.rd, imm)
        elif name == 'auipc':
            self.write_reg(pc, d.rd, pc + imm)

        # 访存
        elif name == 'lw':
            addr = (a + imm) & MASK32
            value, is_counter = self.load(pc, addr)
            self.write_reg(pc, d.rd, value, counter=is_counter)
        elif name == 'sw':
            self.store(pc, (a + imm) & MASK32, b)

        # 分支与跳转
        elif name in BRANCHES:
            taken = {
                'beq': a == b,
                'bne': a != b,
                'blt': to_signed(a) < to_signed(b),
                'bge': to_signed(a) >= to_signed(b),
                'bltu': a < b,
                'bgeu': a >= b,
            }[name]
            if taken:
                next_pc = self.jump_target(pc, pc + imm)
        elif name == 'jal':
            next_pc = self.jump_target(pc, pc + imm)
            self.write_reg(pc, d.rd, pc + 4)
        elif name == 'jalr':
            # 先算目标再写 rd，rd 可能就是 rs1
            next_pc = self.jump_target(pc, (a + imm) & ~1)
            self.write_reg(pc, d.rd, pc + 4)
        else:
            raise AssertionError('unhandled instruction ' + name)

        self.instret += 1
        self.pc = next_pc

    @staticmethod
    def jump_target(pc, target):
        target &= MASK32
        if target % 4:
            raise SimError(pc, 'jump target %08x is not a multiple of 4' % target)
        return target

    def run(self, max_steps):
        """执行到写 FINISH 为止，返回结果码。超过 max_steps 条指令则报错。"""
        while self.finish_code is None:
            if self.instret >= max_steps:
                raise SimError(self.pc, 'no FINISH after %d instructions (--max-steps)' % max_steps)
            self.step()
        return self.finish_code


# ---------------------------------------------------------------- 文件与命令行

def load_hex(path):
    """读 $readmemh 格式的镜像：每行一个 8 位十六进制字，最多 1024 行。"""
    words = []
    with open(path) as f:
        for lineno, line in enumerate(f, 1):
            text = line.strip()
            if not text:
                continue
            if len(text) != 8 or any(c not in '0123456789abcdefABCDEF' for c in text):
                raise ValueError('%s:%d: expected 8 hex digits, got %r' % (path, lineno, text))
            words.append(int(text, 16))
    if len(words) > MEM_WORDS:
        raise ValueError('%s: %d words, more than %d' % (path, len(words), MEM_WORDS))
    return words


def main(argv=None):
    parser = argparse.ArgumentParser(description='mini-cpu instruction set simulator')
    parser.add_argument('--isa', required=True, choices=sorted(ISA_SUBSETS))
    parser.add_argument('--imem', required=True, help='instruction memory image')
    parser.add_argument('--dmem', required=True, help='data memory image')
    parser.add_argument('--trace', help='write the expected trace here')
    parser.add_argument('--max-steps', type=int, default=1000000,
                        help='give up after this many instructions (default 1000000)')
    parser.add_argument('--check-pad', action='store_true',
                        help='require the stage-1 padding rules (see module docstring)')
    parser.add_argument('--check-uninit', action='store_true',
                        help='fail on reads of registers that were never written')
    args = parser.parse_args(argv)

    try:
        imem = load_hex(args.imem)
        dmem = load_hex(args.dmem)
    except (OSError, ValueError) as e:
        print('iss: %s' % e, file=sys.stderr)
        return 2

    def on_mark(data, instret):
        print('MARK %08x instret=%d' % (data, instret), flush=True)

    machine = Machine(imem, dmem, args.isa, check_pad=args.check_pad,
                      check_uninit=args.check_uninit, on_mark=on_mark)
    error = None
    try:
        machine.run(args.max_steps)
    except SimError as e:
        error = e

    if args.trace:
        with open(args.trace, 'w', newline='\n') as f:
            for line in machine.trace:
                f.write(line + '\n')

    if error is not None:
        print('ERROR %s' % error, file=sys.stderr)
        return 1
    print('FINISH code=%d instret=%d' % (machine.finish_code, machine.instret))
    return 0


if __name__ == '__main__':
    sys.exit(main())
