#!/usr/bin/env python3
"""随机测试生成器（设计文档第九节"随机测试"）。

    python3 scripts/gen_random.py --isa {base9|rv32i|rv32i_qmul} --seed N [-o prog.S]

生成一个 .S 测试程序（默认写到标准输出），和手写测试一样用 build.py 构建。
同一个 ISA、同一个种子总是生成同样的程序。程序不自检，最后写 FINISH 0；
判定标准是 CPU 的轨迹与参考模型完全一致。

约束：
  - 随机指令只写 x1..x6，源操作数偏向最近写过的寄存器，相邻指令依赖密集。
    x7 是数据区基址，只读；x8 是循环计数器，x9 恒为 1，x10 是 base9 循环的
    临时寄存器，只在循环控制里用。
  - 访存只用 x7 加合法偏移、从指针表读出的指针加偏移，或者（rv32i）
    andi 截出的对齐偏移加 x7，地址总在数据区内并且对齐。
  - 分支和 jal 只向前跳，跳过后面 0..3 项；向后跳的只有循环（2..5 次）
    和函数返回，所以程序一定结束。
  - jalr 的目标来自 jal 的返回地址（函数返回）、auipc 算出的地址，或从
    代码指针表读出的地址；偏移有正有负，有时故意让目标地址为奇数。
  - 除了单条随机指令，还按第五节场景表有意生成冒险组合：load 后紧跟使用、
    load 后紧跟 store、分支/jalr 依赖 load 或刚算出的值、同一寄存器连续写、
    写 x0、跳转后紧跟 store、错误路径上的 load-use、连续跳转等。
    每类组合实际出现了多少，用 scripts/rand_stats.py 统计。

每条普通指令后面跟 PAD_DATA，每条分支、跳转后面跟 PAD_JUMP，每个跳转目标
后面跟 PAD_DATA，所以 pad 变体同样满足阶段 1 的填充规则。
"""

import argparse
import random
import sys

ISAS = ('base9', 'rv32i', 'rv32i_qmul')

WORK = (1, 2, 3, 4, 5, 6)      # 随机指令的目的寄存器
BASE = 7                       # 数据区基址，只读
CNT = 8                        # 循环计数器
ONE = 9                        # 常数 1
TMP = 10                       # base9 循环的临时寄存器

# 数据区布局（相对 rand_data 的字节偏移）
RW_WORDS = 64                  # 0..255：可读写，随机初值
PTR_OFF = RW_WORDS * 4         # 指针表：指向可读写区的指针，只读
PTR_WORDS = 8
SLOT_OFF = PTR_OFF + PTR_WORDS * 4    # 函数保存返回地址的槽
MAX_FUNCS = 2
CODE_OFF = SLOT_OFF + MAX_FUNCS * 4   # 代码指针表，只读

# pad 变体的代码字数上限（指令存储器 1024 字，留出余量）
MAIN_BUDGET = 802       # 含两处 PERF_MARK（2 × PERF_MARK_WORDS）
PERF_MARK_WORDS = 11     # pad 变体里 PERF_MARK 的字数：SEP 3 + MARK_POINT 5 + SEP 3

R_BASE9 = ('add', 'slt', 'sltu')
R_RV32I = R_BASE9 + ('sub', 'and', 'or', 'xor', 'sll', 'srl', 'sra')
I_BASE9 = ('ori',)
I_RV32I = ('ori', 'addi', 'andi', 'xori', 'slti', 'sltiu')
SHIFT_I = ('slli', 'srli', 'srai')
SHIFT_R = ('sll', 'srl', 'sra')
BRANCH_RV32I = ('beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu')


class Ctx:
    """生成一段代码时的限制。"""

    def __init__(self, loop=True, call=True, avoid=()):
        self.loop = loop          # 能不能生成循环
        self.call = call          # 能不能生成函数调用
        self.avoid = frozenset(avoid)   # 不能写的寄存器


class Pending:
    """一个还没放下的向前跳转目标：再过 count 项之后放下。"""

    def __init__(self, count, label, chain):
        self.count = count
        self.label = label
        self.chain = chain        # 目标处紧跟一条跳转（连续跳转）


class Function:
    def __init__(self, label, link, save, slot):
        self.label = label
        self.link = link          # 返回地址寄存器
        self.save = save          # True：返回地址先存进槽，返回前再读出来
        self.slot = slot


class Generator:
    def __init__(self, isa, seed):
        if isa not in ISAS:
            raise ValueError('unknown ISA subset %r' % isa)
        self.isa = isa
        self.seed = seed
        self.rng = random.Random('%s:%d' % (isa, seed))
        self.rv32i = isa != 'base9'
        self.has_qmul = isa == 'rv32i_qmul'

        self.out = []             # 当前写入的代码行
        self.size = 0             # pad 变体的代码字数
        self.nlabel = 0
        self.recent = []          # 最近写过的 x1..x6，最新的在最后
        self.pending = []         # 本层还没放下的跳转目标
        self.new_pending = []     # 当前这一项产生的跳转目标
        self.forced = None        # 下一项必须是哪一类
        self.loops = 0
        self.functions = []
        self.function_text = []
        self.code_ptrs = []       # 代码指针表：(标号, 加数)
        self.link_to_use = None
        self.rw_init = [self.value() for _ in range(RW_WORDS)]
        self.ptr_init = [self.rng.randrange(RW_WORDS) for _ in range(PTR_WORDS)]

        self.r_ops = R_RV32I if self.rv32i else R_BASE9
        self.i_ops = I_RV32I if self.rv32i else I_BASE9
        self.branch_ops = BRANCH_RV32I if self.rv32i else ('beq',)

    # ------------------------------------------------------------ 随机数

    def chance(self, p):
        return self.rng.random() < p

    def value(self):
        r = self.rng.random()
        if r < 0.3:
            return self.rng.choice([0, 1, 2, 0xffffffff, 0x7fffffff, 0x80000000,
                                    0xfffff800, 0x7ff, 0x800, 0xfff])
        if r < 0.5:
            return self.rng.randrange(-64, 64) & 0xffffffff
        return self.rng.getrandbits(32)

    def imm12(self):
        r = self.rng.random()
        if r < 0.3:
            return self.rng.choice([0, 1, -1, 2047, -2048, 0x7f0, -0x7f0])
        if r < 0.6:
            return self.rng.randrange(-16, 17)
        return self.rng.randrange(-2048, 2048)

    def imm20(self):
        if self.chance(0.4):
            return self.rng.choice([0, 1, 0x80000, 0xfffff, 0x7ffff])
        return self.rng.randrange(1 << 20)

    def shamt(self):
        if self.chance(0.4):
            return self.rng.choice([0, 1, 31, 30])
        return self.rng.randrange(32)

    def src(self):
        """源寄存器：多半取最近写过的，制造密集依赖。"""
        r = self.rng.random()
        if self.recent and r < 0.6:
            return self.rng.choice(self.recent[-3:])
        if r < 0.66:
            return 0
        return self.rng.choice(WORK)

    def dest(self, ctx, avoid=(), x0=True):
        if x0 and self.chance(0.04):
            return 0
        choices = [r for r in WORK if r not in ctx.avoid and r not in avoid]
        return self.rng.choice(choices)

    def rw_off(self, span=RW_WORDS):
        return 4 * self.rng.randrange(span)

    # ------------------------------------------------------------ 输出

    def label(self):
        self.nlabel += 1
        return '.Lr%d' % self.nlabel

    def wrote(self, r):
        if r in WORK:
            if r in self.recent:
                self.recent.remove(r)
            self.recent.append(r)
            del self.recent[:-4]

    def op(self, text, rd=None):
        """普通指令，后跟 PAD_DATA。"""
        self.out.append('    ' + text)
        self.out.append('    PAD_DATA')
        self.size += 3
        if rd is not None:
            self.wrote(rd)

    def ctl(self, text, rd=None):
        """分支、跳转，后跟 PAD_JUMP。"""
        self.out.append('    ' + text)
        self.out.append('    PAD_JUMP')
        self.size += 4
        if rd is not None:
            self.wrote(rd)

    def target(self, label):
        """跳转目标，后跟 PAD_DATA（pad 变体里跳转写的链接寄存器要隔开）。"""
        self.out.append(label + ':')
        self.out.append('    PAD_DATA')
        self.size += 2

    def forward(self, skip=None, chain=None):
        """新建一个向前跳转的目标标号，放在后面第 skip 项之后。"""
        if skip is None:
            skip = self.rng.choice([0, 1, 1, 2, 2, 3])
        if chain is None:
            chain = self.chance(0.2)
        label = self.label()
        self.new_pending.append(Pending(skip, label, chain))
        return label

    def after_jump(self):
        """跳转后面紧跟的几条在 nopad 变体里是错误路径（跳转成立时被冲刷）。"""
        self.forced = self.rng.choice(['wp_store', 'wp_load_use', 'wp_load_use', None, None])

    # ------------------------------------------------------------ 单条指令

    def alu_text(self, rd, need=None, ops=None):
        """一条随机运算指令。need 不为 None 时它必须是一个源操作数。"""
        if ops is None:
            ops = list(self.r_ops) * 2 + list(self.i_ops) * 2
            if self.rv32i:
                ops += list(SHIFT_I)
            if self.has_qmul:
                ops += ['qmul'] * 2
            if need is None:
                ops += ['lui'] + (['auipc'] if self.rv32i else [])
        name = self.rng.choice(ops)
        if name in self.r_ops or name == 'qmul':
            a, b = self.src(), self.src()
            if need is not None:
                if self.chance(0.5):
                    a = need
                else:
                    b = need
            return '%s x%d, x%d, x%d' % (name, rd, a, b)
        a = need if need is not None else self.src()
        if name in SHIFT_I:
            return '%s x%d, x%d, %d' % (name, rd, a, self.shamt())
        if name in ('lui', 'auipc'):
            return '%s x%d, 0x%x' % (name, rd, self.imm20())
        return '%s x%d, x%d, %d' % (name, rd, a, self.imm12())

    def alu(self, ctx, need=None, avoid=(), ops=None):
        rd = self.dest(ctx, avoid)
        self.op(self.alu_text(rd, need, ops), rd)
        return rd

    def load(self, ctx, avoid=(), x0=True):
        """从数据区读一个字：可读写区、指针表或代码指针表。"""
        rd = self.dest(ctx, avoid, x0)
        r = self.rng.random()
        if r < 0.75:
            off = self.rw_off()
        elif r < 0.9 or not self.code_ptrs:
            off = PTR_OFF + 4 * self.rng.randrange(PTR_WORDS)
        else:
            off = CODE_OFF + 4 * self.rng.randrange(len(self.code_ptrs))
        self.op('lw x%d, %d(x%d)' % (rd, off, BASE), rd)
        return rd

    def store(self, data=None):
        if data is None:
            data = self.src()
        self.op('sw x%d, %d(x%d)' % (data, self.rw_off(), BASE))

    def use(self, ctx, r, kinds=('alu', 'alu', 'store', 'branch')):
        """一条读 r 的指令。"""
        kind = self.rng.choice(kinds)
        if kind == 'alu':
            self.alu(ctx, need=r)
        elif kind == 'store':
            self.op('sw x%d, %d(x%d)' % (r, self.rw_off(), BASE))
        elif kind == 'branch':
            self.branch(a=r)

    def branch(self, a=None, b=None, skip=None, name=None):
        if name is None:
            name = self.rng.choice(self.branch_ops)
        if a is None:
            a = self.src()
        if b is None:
            r = self.rng.random()
            b = a if r < 0.2 else 0 if r < 0.4 else self.src()
        if self.chance(0.5):
            a, b = b, a
        self.ctl('%s x%d, x%d, %s' % (name, a, b, self.forward(skip)))
        self.after_jump()

    # ------------------------------------------------------------ 各类项

    def it_alu(self, ctx):
        self.alu(ctx)

    def it_mem(self, ctx):
        r = self.rng.random()
        if r < 0.35:
            self.load(ctx)
        elif r < 0.65:
            self.store()
        elif r < 0.8 or not self.rv32i:
            # 经指针表里的指针访问
            p = self.rng.randrange(PTR_WORDS)
            rp = self.dest(ctx, x0=False)
            self.op('lw x%d, %d(x%d)' % (rp, PTR_OFF + 4 * p, BASE), rp)
            off = 4 * self.rng.randrange(RW_WORDS) - 4 * self.ptr_init[p]
            if self.chance(0.5):
                rd = self.dest(ctx)
                self.op('lw x%d, %d(x%d)' % (rd, off, rp), rd)
            else:
                self.op('sw x%d, %d(x%d)' % (self.src(), off, rp))
        else:
            # 用 andi 截出对齐的偏移，再加基址
            rt = self.dest(ctx, x0=False)
            self.op('andi x%d, x%d, 0x7c' % (rt, self.src()), rt)
            self.op('add x%d, x%d, x%d' % (rt, rt, BASE), rt)
            off = 4 * self.rng.randrange(RW_WORDS - 31)
            if self.chance(0.5):
                rd = self.dest(ctx)
                self.op('lw x%d, %d(x%d)' % (rd, off, rt), rd)
            else:
                self.op('sw x%d, %d(x%d)' % (self.src(), off, rt))

    def it_raw(self, ctx):
        """写 r，隔 0..2 条，再读 r。"""
        r = self.alu(ctx) if self.chance(0.8) else self.load(ctx)
        if r == 0:
            return
        for _ in range(self.rng.choice([0, 0, 1, 2])):
            self.alu(ctx, avoid=(r,))
        self.use(ctx, r)

    def it_waw(self, ctx):
        """同一寄存器连续写两次，再读。"""
        r = self.dest(ctx, x0=False)
        for _ in range(2):
            if self.chance(0.2):
                self.op('lw x%d, %d(x%d)' % (r, self.rw_off(), BASE), r)
            else:
                self.op(self.alu_text(r), r)
        self.use(ctx, r)

    def it_x0(self, ctx):
        """写 x0，随后读 x0。"""
        if self.chance(0.7):
            self.op(self.alu_text(0))
        else:
            self.op('lw x0, %d(x%d)' % (self.rw_off(), BASE))
        if self.chance(0.3):
            self.alu(ctx)
        self.use(ctx, 0)

    def it_load_use(self, ctx):
        kinds = ['alu', 'alu', 'branch', 'address']
        if self.has_qmul:
            kinds.append('qmul')
        kind = self.rng.choice(kinds)
        if kind == 'address':
            # 读出的值紧接着当地址用：从指针表读
            self.ptr_access(ctx, self.dest(ctx, x0=False), store=self.chance(0.6))
            return
        r = self.load(ctx, x0=False)
        if kind == 'qmul':
            self.alu(ctx, need=r, ops=['qmul'])
        else:
            self.use(ctx, r, (kind,))

    def ptr_access(self, ctx, rp, store):
        p = self.rng.randrange(PTR_WORDS)
        self.op('lw x%d, %d(x%d)' % (rp, PTR_OFF + 4 * p, BASE), rp)
        off = 4 * self.rng.randrange(RW_WORDS) - 4 * self.ptr_init[p]
        if store:
            self.op('sw x%d, %d(x%d)' % (self.src(), off, rp))
        else:
            rd = self.dest(ctx)
            self.op('lw x%d, %d(x%d)' % (rd, off, rp), rd)

    def it_load_dist2(self, ctx):
        r = self.load(ctx, x0=False)
        self.alu(ctx, avoid=(r,))
        self.use(ctx, r)

    def it_load_store(self, ctx):
        """load 后紧跟 store：依赖在数据，或依赖在地址。"""
        if self.chance(0.5):
            r = self.load(ctx, x0=False)
            self.op('sw x%d, %d(x%d)' % (r, self.rw_off(), BASE))
        else:
            self.ptr_access(ctx, self.dest(ctx, x0=False), store=True)

    def it_alu_store(self, ctx):
        """运算后隔 0..1 条 store 它的结果。"""
        r = self.dest(ctx, x0=False)
        self.op(self.alu_text(r), r)
        if self.chance(0.7):
            self.alu(ctx, avoid=(r,))
        self.op('sw x%d, %d(x%d)' % (r, self.rw_off(), BASE))

    def it_branch(self, ctx):
        r = self.rng.random()
        if r < 0.3:
            self.branch()
        elif r < 0.55:
            a = self.alu(ctx)
            if self.chance(0.3):
                self.alu(ctx, avoid=(a,))
            self.branch(a=a)
        elif r < 0.8:
            a = self.load(ctx)
            self.branch(a=a)
        else:
            # 复制一份再比较：相等，beq/bge/bgeu 成立
            a = self.src()
            b = self.dest(ctx, x0=False)
            self.op(('addi x%d, x%d, 0' if self.rv32i and self.chance(0.5) else
                     'add x%d, x%d, x0') % (b, a), b)
            self.branch(a=a, b=b)

    def it_jal(self, ctx):
        rd = 0 if self.chance(0.5) else self.dest(ctx, x0=False)
        self.ctl('jal x%d, %s' % (rd, self.forward(self.rng.choice([0, 1, 1, 2]))), rd)
        self.after_jump()

    def it_jump(self, ctx):
        """一定成立的跳转（连续跳转的第二条）。"""
        r = self.rng.random()
        if r < 0.4:
            self.it_jal(ctx)
        elif r < 0.7 or not self.rv32i:
            a = self.src()
            name = self.rng.choice(['beq', 'bge', 'bgeu'] if self.rv32i else ['beq'])
            self.branch(a=a, b=a, name=name)
        else:
            self.rng.choice([self.it_jalr_auipc, self.it_jalr_load])(ctx)

    def it_jalr_auipc(self, ctx):
        """auipc + jalr：目标由 auipc 算出，可选加一个偏移再减回来。"""
        rb = self.dest(ctx, x0=False)
        tgt = self.forward()
        au = self.label()
        self.out.append(au + ':')
        self.op('auipc x%d, %%pcrel_hi(%s)' % (rb, tgt), rb)
        odd = 1 if self.chance(0.3) else 0
        rd = self.rng.choice([0, rb, self.dest(ctx, x0=False)])
        if self.chance(0.4):
            self.ctl('jalr x%d, %%pcrel_lo(%s)(x%d)' % (rd, au, rb), rd)
        else:
            self.op('addi x%d, x%d, %%pcrel_lo(%s)' % (rb, rb, au), rb)
            k = self.rng.choice([0, 8, -8, 2044, -2040, self.rng.randrange(-511, 512) * 4])
            if k:
                self.op('addi x%d, x%d, %d' % (rb, rb, -k), rb)
            self.ctl('jalr x%d, %d(x%d)' % (rd, k + odd, rb), rd)
        self.after_jump()

    def it_jalr_load(self, ctx):
        """从代码指针表读出目标地址，紧跟 jalr（jalr 依赖 load）。"""
        tgt = self.forward()
        k = self.rng.choice([0, 0, 4, -4, 16, -2044, 2044])
        odd = 1 if self.chance(0.3) else 0
        self.code_ptrs.append((tgt, k))
        off = CODE_OFF + 4 * (len(self.code_ptrs) - 1)
        rp = self.dest(ctx, x0=False)
        self.op('lw x%d, %d(x%d)' % (rp, off, BASE), rp)
        if self.chance(0.25):
            self.alu(ctx, avoid=(rp,))
        rd = self.rng.choice([0, rp, self.dest(ctx, x0=False)])
        self.ctl('jalr x%d, %d(x%d)' % (rd, odd - k, rp), rd)
        self.after_jump()

    def it_shift(self, ctx):
        """移位量来自刚算出的值。"""
        r = self.dest(ctx, x0=False)
        self.op(self.alu_text(r), r)
        if self.chance(0.3):
            self.alu(ctx, avoid=(r,))
        rd = self.dest(ctx)
        self.op('%s x%d, x%d, x%d' % (self.rng.choice(SHIFT_R), rd, self.src(), r), rd)

    def it_upper(self, ctx):
        """lui / auipc 的结果马上被使用。"""
        r = self.dest(ctx, x0=False)
        name = self.rng.choice(['lui', 'auipc'] if self.rv32i else ['lui'])
        self.op('%s x%d, 0x%x' % (name, r, self.imm20()), r)
        if self.chance(0.3):
            self.alu(ctx, avoid=(r,))
        self.use(ctx, r)

    def it_qmul(self, ctx):
        """qmul 的结果被转发，或 qmul 的操作数来自转发。"""
        if self.chance(0.5):
            r = self.dest(ctx, x0=False)
            self.op(self.alu_text(r, ops=['qmul']), r)
            self.use(ctx, r)
        else:
            r = self.alu(ctx) if self.chance(0.7) else self.load(ctx)
            self.alu(ctx, need=r, ops=['qmul'])

    def it_wp_store(self, ctx):
        self.store()

    def it_wp_load_use(self, ctx):
        r = self.load(ctx, x0=False)
        self.use(ctx, r, ('alu', 'alu', 'store', 'branch'))

    def it_call(self, ctx):
        if len(self.functions) < MAX_FUNCS and (not self.functions or self.chance(0.5)):
            f = self.make_function()
        else:
            f = self.rng.choice(self.functions)
        self.ctl('jal x%d, %s' % (f.link, f.label), f.link)
        # 返回地址寄存器在调用者里马上被使用
        if f.save is False and self.chance(0.3):
            self.forced = 'use_link'
            self.link_to_use = f.link

    def it_use_link(self, ctx):
        self.use(ctx, self.link_to_use, ('alu', 'store', 'branch'))

    def it_loop(self, ctx):
        n = self.rng.randrange(2, 6)
        head = self.label()
        forms = ['b9_exit', 'b9_slt']
        if self.rv32i:
            forms += ['bne', 'blt', 'bltu', 'bge']
        form = self.rng.choice(forms)
        if form.startswith('b9'):
            self.op('ori x%d, x0, %d' % (CNT, -n))
        else:
            self.op('addi x%d, x0, %d' % (CNT, n))
        self.target(head)
        self.block(Ctx(loop=False, call=ctx.call, avoid=ctx.avoid), count=self.rng.randrange(3, 8))
        if form == 'b9_exit':
            exit_label = self.label()
            self.op('add x%d, x%d, x%d' % (CNT, CNT, ONE))
            self.ctl('beq x%d, x0, %s' % (CNT, exit_label))
            self.ctl('jal x0, %s' % head)
            self.target(exit_label)
        elif form == 'b9_slt':
            self.op('add x%d, x%d, x%d' % (CNT, CNT, ONE))
            self.op('slt x%d, x%d, x0' % (TMP, CNT))
            self.ctl('beq x%d, x%d, %s' % (TMP, ONE, head))
        else:
            self.op('addi x%d, x%d, -1' % (CNT, CNT))
            cond = {'bne': 'bne x%d, x0' % CNT, 'blt': 'blt x0, x%d' % CNT,
                    'bltu': 'bltu x0, x%d' % CNT, 'bge': 'bge x%d, x%d' % (CNT, ONE)}[form]
            self.ctl('%s, %s' % (cond, head))
        self.loops += 1

    # ------------------------------------------------------------ 函数

    def make_function(self):
        index = len(self.functions)
        f = Function('.Lfunc%d' % index, self.rng.choice(WORK), self.chance(0.5),
                     SLOT_OFF + 4 * index)
        self.functions.append(f)

        saved = (self.out, self.recent)
        self.out, self.recent = [], [f.link]
        self.target(f.label)
        avoid = () if f.save else (f.link,)
        if f.save:
            self.op('sw x%d, %d(x%d)' % (f.link, f.slot, BASE))
        self.block(Ctx(loop=False, call=False, avoid=avoid), count=self.rng.randrange(2, 6))
        ctx = Ctx(loop=False, call=False, avoid=avoid)
        if f.save:
            r = self.dest(ctx, x0=False)
            self.op('lw x%d, %d(x%d)' % (r, f.slot, BASE), r)
            if self.chance(0.3):
                self.alu(ctx, avoid=(r,))
        else:
            r = f.link
        rd = self.rng.choice([0, 0, r, self.dest(ctx, x0=False)])
        k = self.rng.choice([0, 0, 0, 1, 'adj'])
        if k == 'adj':
            # 先把返回地址加上一个数，再用负偏移减回来
            k = self.rng.choice([8, 12, 2000])
            self.op('addi x%d, x%d, %d' % (r, r, k), r)
            off = -k + (1 if self.chance(0.3) else 0)
        else:
            off = k
        self.ctl('jalr x%d, %d(x%d)' % (rd, off, r), rd)
        self.function_text.extend(self.out)
        self.out, self.recent = saved
        return f

    # ------------------------------------------------------------ 组织

    def weights(self, ctx):
        w = {'alu': 20, 'mem': 10, 'raw': 8, 'waw': 3, 'x0': 2, 'load_use': 6,
             'load_dist2': 3, 'load_store': 5, 'alu_store': 3, 'branch': 10, 'jal': 4,
             'upper': 2}
        if ctx.loop and not self.pending and not self.new_pending and self.loops < 3:
            w['loop'] = 3
        if self.rv32i:
            w.update({'jalr_auipc': 3, 'jalr_load': 3, 'shift': 2})
            if ctx.call:
                w['call'] = 3
        if self.has_qmul:
            w['qmul'] = 4
        return w

    def item(self, ctx):
        kind = self.forced
        self.forced = None
        if kind is None:
            w = self.weights(ctx)
            kinds = sorted(w)
            kind = self.rng.choices(kinds, [w[k] for k in kinds])[0]
        getattr(self, 'it_' + kind)(ctx)

    def place(self, everything=False):
        rest = []
        for p in self.pending:
            if p.count <= 0 or everything:
                self.target(p.label)
                if p.chain and not everything:
                    self.forced = 'jump'
            else:
                rest.append(p)
        self.pending = rest

    def block(self, ctx, count=None, budget=None):
        """生成一段代码：count 项，或者直到 pad 变体的字数达到 budget。"""
        saved = (self.pending, self.new_pending, self.forced)
        self.pending, self.new_pending, self.forced = [], [], None
        n = 0
        while (count is not None and n < count) or (budget is not None and self.size < budget):
            self.item(ctx)
            n += 1
            for p in self.pending:
                p.count -= 1
            self.pending += self.new_pending
            self.new_pending = []
            self.place()
        self.place(everything=True)
        self.pending, self.new_pending, self.forced = saved

    def generate(self):
        lines = [
            '// 随机测试：%s，种子 %d。由 scripts/gen_random.py 生成，不要手改。' % (self.isa, self.seed),
            '// 不自检，以 FINISH 0 结束；判定标准是轨迹与参考模型一致。',
            '// MARK 1、2 之间的计数器增量取按第五节规则推算的值（scripts/perf.py）：',
            '// PERF 1-2: model',
            '#include "test.h"',
        ]
        if self.has_qmul:
            lines.append('#include "qmul.h"')
        lines += ['', '    .option norelax', '', 'TEST_BEGIN', '    LA      x%d, rand_data' % BASE,
                  '    PAD_DATA']
        for i, r in enumerate(WORK):
            lines.append('    lw      x%d, %d(x%d)' % (r, 4 * i, BASE))
        lines += ['    ori     x%d, x0, 0' % CNT, '    ori     x%d, x0, 1' % ONE,
                  '    ori     x%d, x0, 0' % TMP, '    PAD_DATA', '    PERF_MARK 1', '']
        self.size = 4 + 1 + len(WORK) + 3 + 2 + 2 * PERF_MARK_WORDS
        self.recent = list(WORK)

        self.block(Ctx(), budget=MAIN_BUDGET)
        lines += self.out
        lines += ['', '    PERF_MARK 2', '    TEST_PASS', '']
        lines += self.function_text

        lines += ['', '    .data', '    .balign 4', 'rand_data:']
        lines += ['    .word   0x%08x' % v for v in self.rw_init]
        lines += ['    .word   rand_data + %d' % (4 * k) for k in self.ptr_init]
        lines += ['    .word   0'] * MAX_FUNCS
        for label, k in self.code_ptrs:
            lines.append('    .word   %s + %d' % (label, k))
        return '\n'.join(lines) + '\n'


def generate(isa, seed):
    return Generator(isa, seed).generate()


def main(argv=None):
    parser = argparse.ArgumentParser(description='generate a random mini-cpu test program')
    parser.add_argument('--isa', required=True, choices=ISAS)
    parser.add_argument('--seed', required=True, type=int)
    parser.add_argument('-o', '--output', help='output .S file (default: stdout)')
    args = parser.parse_args(argv)
    text = generate(args.isa, args.seed)
    if args.output:
        with open(args.output, 'w', newline='\n') as f:
            f.write(text)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
