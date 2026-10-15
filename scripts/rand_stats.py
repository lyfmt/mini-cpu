#!/usr/bin/env python3
"""统计随机测试里实际出现的指令和冒险组合。

    python3 scripts/rand_stats.py --isa ISA [--count N] [--seed S] [-j N]

构建（nopad 变体）种子 S..S+N-1 的随机测试，在参考模型上逐条执行，按动态执行
顺序统计：每条指令执行了多少次；第五节场景表里的每种冒险组合出现了多少次、
出现在多少个程序里。判定只看实际执行的指令流（和跳转后静态相邻的错误路径
指令），不看生成器的意图。有适用于该 ISA 的类别一次都没出现时，退出码为 1。

"距离 k"指消费者前面第 k 条动态指令是生产者（中间没有别的指令写同一个寄存器）。
"""

import argparse
import os
import sys
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build   # noqa: E402
import iss     # noqa: E402

# (键, 说明, 适用的最低 ISA)
CATEGORIES = [
    ('raw_dist1', '相邻依赖（距离 1）', 'base9'),
    ('raw_dist2', '隔一条依赖（距离 2）', 'base9'),
    ('raw_dist3', '隔两条依赖（距离 3，寄存器堆旁路）', 'base9'),
    ('waw_mprio', '同一寄存器连续写后读（M 段优先）', 'base9'),
    ('x0_write_read', '写 x0 后 1..2 条内读 x0', 'base9'),
    ('load_use', 'load 后紧跟使用（停顿）', 'base9'),
    ('load_dist2', 'load 后隔一条使用', 'base9'),
    ('load_store_data', 'load 后紧跟 store，依赖在数据（DiSrc）', 'base9'),
    ('load_store_addr', 'load 后紧跟 store，依赖在地址（停顿）', 'base9'),
    ('alu_store_dist1', '运算后紧跟 store 它的结果', 'base9'),
    ('alu_store_dist2', '运算后隔一条 store 它的结果', 'base9'),
    ('branch_alu_dep', '分支依赖距离 1..2 的运算结果', 'base9'),
    ('branch_load_dep', '分支依赖紧挨着的 load（停顿）', 'base9'),
    ('jalr_load_dep', 'jalr 依赖紧挨着的 load（停顿）', 'rv32i'),
    ('jalr_alu_dep', 'jalr 依赖距离 1..2 的运算结果', 'rv32i'),
    ('shift_amount_fwd', '寄存器移位量来自距离 1..2 的结果', 'rv32i'),
    ('lui_fwd', 'lui 结果在距离 1..2 被使用', 'base9'),
    ('auipc_fwd', 'auipc 结果在距离 1..2 被使用', 'rv32i'),
    ('link_fwd', 'jal/jalr 写的返回地址在距离 1..2 被使用', 'base9'),
    ('qmul_result_fwd', 'qmul 结果在距离 1..2 被使用', 'rv32i_qmul'),
    ('qmul_operand_fwd', 'qmul 的操作数来自距离 1..2 的结果', 'rv32i_qmul'),
    ('branch_taken', '分支成立（冲刷 3 条）', 'base9'),
    ('branch_not_taken', '分支不成立', 'base9'),
    ('branch_backward_taken', '向后分支成立（循环）', 'base9'),
    ('jal', 'jal（冲刷 3 条）', 'base9'),
    ('jalr', 'jalr（冲刷 3 条）', 'rv32i'),
    ('jump_to_next', '跳转成立且目标是下一条', 'base9'),
    ('jump_then_store', '跳转成立，紧跟的（错误路径）指令是 store', 'base9'),
    ('wrong_path_effects', '跳转成立，后面 3 条错误路径里有写寄存器或 store', 'base9'),
    ('flush_over_stall', '跳转成立，错误路径上紧跟 load-use（冲刷优先）', 'base9'),
    ('jump_chain', '连续跳转：成立的跳转的目标处又是成立的跳转', 'base9'),
    ('jalr_odd_target', 'jalr 的 rs1+imm 为奇数（最低位清零）', 'rv32i'),
    ('jalr_rd_eq_rs1', 'jalr 的 rd = rs1（≠ x0）', 'rv32i'),
    ('jalr_neg_offset', 'jalr 的偏移为负', 'rv32i'),
]


def applicable(isa, level):
    return build.ISA_ORDER.index(level) <= build.ISA_ORDER.index(isa)


def sources(d):
    """(寄存器, 角色) 列表：角色是 rs1 或 rs2。"""
    out = []
    if iss.uses_rs1(d.name):
        out.append((d.rs1, 'rs1'))
    if iss.uses_rs2(d.name):
        out.append((d.rs2, 'rs2'))
    return out


def is_control(name):
    return name in iss.BRANCHES or name in iss.JUMPS


def stalls_on(d, r):
    """d 紧跟在写 r 的 load 后面时是否要停顿（store 的数据不算）。"""
    return any(reg == r and not (d.name == 'sw' and role == 'rs2') for reg, role in sources(d))


def producer(hist, r):
    """最近 3 条动态指令里写 r 的那条：返回 (距离, Decoded)，没有则 (None, None)。"""
    for dist in (1, 2, 3):
        if len(hist) < dist:
            break
        p = hist[-dist][1]
        if iss.writes_rd(p.name) and p.rd == r:
            return dist, p
    return None, None


def branch_taken(name, a, b):
    return {
        'beq': a == b,
        'bne': a != b,
        'blt': iss.to_signed(a) < iss.to_signed(b),
        'bge': iss.to_signed(a) >= iss.to_signed(b),
        'bltu': a < b,
        'bgeu': a >= b,
    }[name]


def analyze(imem, dmem, isa):
    """执行一个程序，返回 (指令计数, 类别计数)。"""
    m = iss.Machine(imem, dmem, isa)
    insts = Counter()
    cats = Counter()
    hist = []                 # 已执行的 (pc, Decoded, taken)

    def static(pc):
        try:
            return iss.decode(m.imem[pc // 4]) if 0 <= pc < iss.MEM_BYTES else None
        except iss.IllegalInstruction:
            return None

    while m.finish_code is None:
        pc = m.pc
        d = iss.decode(m.fetch(pc))
        a, b = m.regs[d.rs1], m.regs[d.rs2]
        m.step()
        name = d.name
        insts[name] += 1
        taken = name in iss.JUMPS or (name in iss.BRANCHES and branch_taken(name, a, b))

        # ---- 数据依赖：每个源寄存器找最近的生产者
        for r, role in sources(d):
            if r == 0:
                continue
            dist, p = producer(hist, r)
            if dist is None:
                continue
            cats['raw_dist%d' % dist] += 1
            is_load = p.name == 'lw'
            if dist == 1 and len(hist) >= 2:
                q = hist[-2][1]
                if iss.writes_rd(q.name) and q.rd == r:
                    cats['waw_mprio'] += 1
            if is_load and dist == 1:
                if name == 'sw' and role == 'rs2' and d.rs1 != r:
                    cats['load_store_data'] += 1
                if name == 'sw' and role == 'rs1':
                    cats['load_store_addr'] += 1
                if stalls_on(d, r):
                    cats['load_use'] += 1
                if name in iss.BRANCHES:
                    cats['branch_load_dep'] += 1
                if name == 'jalr':
                    cats['jalr_load_dep'] += 1
            if is_load and dist == 2:
                cats['load_dist2'] += 1
            if not is_load and dist <= 2:
                if name == 'sw' and role == 'rs2':
                    cats['alu_store_dist%d' % dist] += 1
                if name in iss.BRANCHES:
                    cats['branch_alu_dep'] += 1
                if name == 'jalr':
                    cats['jalr_alu_dep'] += 1
            if dist <= 2:
                if name in ('sll', 'srl', 'sra') and role == 'rs2':
                    cats['shift_amount_fwd'] += 1
                if p.name in ('lui', 'auipc'):
                    cats[p.name + '_fwd'] += 1
                if p.name == 'qmul':
                    cats['qmul_result_fwd'] += 1
                if p.name in iss.JUMPS:
                    cats['link_fwd'] += 1
                if name == 'qmul':
                    cats['qmul_operand_fwd'] += 1

        # ---- 写 x0 后读 x0
        if any(r == 0 for r, _ in sources(d)):
            for dist in (1, 2):
                if len(hist) >= dist:
                    p = hist[-dist][1]
                    if iss.writes_rd(p.name) and p.rd == 0 and p.name not in iss.JUMPS:
                        cats['x0_write_read'] += 1
                        break

        # ---- 控制
        if name in iss.BRANCHES:
            cats['branch_taken' if taken else 'branch_not_taken'] += 1
            if taken and d.imm < 0:
                cats['branch_backward_taken'] += 1
        elif name in iss.JUMPS:
            cats[name] += 1
        if name == 'jalr':
            if (a + d.imm) & 1:
                cats['jalr_odd_target'] += 1
            if d.rd == d.rs1 and d.rd != 0:
                cats['jalr_rd_eq_rs1'] += 1
            if d.imm < 0:
                cats['jalr_neg_offset'] += 1
        if taken:
            if m.pc == pc + 4:
                cats['jump_to_next'] += 1
            wrong = [static(pc + 4 * k) for k in (1, 2, 3)]
            if wrong[0] is not None and wrong[0].name == 'sw':
                cats['jump_then_store'] += 1
            if any(w is not None and ((iss.writes_rd(w.name) and w.rd != 0) or w.name == 'sw')
                   for w in wrong):
                cats['wrong_path_effects'] += 1
            w1, w2 = wrong[0], wrong[1]
            if (w1 is not None and w2 is not None and w1.name == 'lw' and w1.rd != 0
                    and stalls_on(w2, w1.rd)):
                cats['flush_over_stall'] += 1
            if hist and hist[-1][2]:
                cats['jump_chain'] += 1

        hist.append((pc, d, taken))
        del hist[:-4]
    return insts, cats


def analyze_dir(args):
    outdir, isa = args
    imem = iss.load_hex(str(Path(outdir) / 'imem.hex'))
    dmem = iss.load_hex(str(Path(outdir) / 'dmem.hex'))
    return analyze(imem, dmem, isa)


def report(isa, results):
    n = len(results)
    lines = []
    total_i, progs_i = Counter(), Counter()
    total_c, progs_c = Counter(), Counter()
    for insts, cats in results:
        total_i.update(insts)
        progs_i.update(insts.keys())
        total_c.update(cats)
        progs_c.update(cats.keys())

    missing = []
    lines.append('%s: %d programs, %d instructions executed' % (isa, n, sum(total_i.values())))
    lines.append('')
    lines.append('%-8s %10s %9s' % ('INSN', 'EXECUTED', 'PROGRAMS'))
    for name in sorted(iss.ISA_SUBSETS[isa], key=lambda x: (iss.RV32I_QMUL.index(x))):
        lines.append('%-8s %10d %9d' % (name, total_i[name], progs_i[name]))
        if not total_i[name]:
            missing.append(name)
    lines.append('')
    lines.append('%-22s %10s %9s  %s' % ('COMBINATION', 'COUNT', 'PROGRAMS', ''))
    for key, text, level in CATEGORIES:
        if not applicable(isa, level):
            continue
        lines.append('%-22s %10d %9d  %s' % (key, total_c[key], progs_c[key], text))
        if not total_c[key]:
            missing.append(key)
    lines.append('')
    lines.append('never seen: ' + (', '.join(missing) if missing else '(none)'))
    return '\n'.join(lines), missing


def main():
    parser = argparse.ArgumentParser(description='coverage statistics of random tests')
    parser.add_argument('--isa', required=True, choices=build.ISA_ORDER)
    parser.add_argument('--count', type=int, default=1000)
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('-j', dest='jobs', type=int, default=os.cpu_count() or 1)
    args = parser.parse_args()

    tests = build.random_tests([args.isa], args.count, args.seed)
    built = build.build_all(tests, ['nopad'], args.jobs)
    bad = [b for b in built if not b.ok or b.finish_code != 0]
    for b in bad:
        print('== %s: build or reference run failed\n%s' % (b.test.id, b.log))
    with ProcessPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        results = list(pool.map(analyze_dir, [(str(b.test.outdir('nopad')), args.isa)
                                              for b in built if b.ok]))
    text, missing = report(args.isa, results)
    print(text)
    return 1 if bad or missing else 0


if __name__ == '__main__':
    sys.exit(main())
