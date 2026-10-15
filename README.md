# mini-cpu

五级流水线 RISC-V 处理器（Verilog，仅仿真）。本文件介绍软件与验证部分：参考模型、测试程序、构建与回归脚本。硬件结构、信号说明和 ModelSim 用法见 [rtl/README.md](rtl/README.md)。

## 目录结构

```
model/              参考模型（指令集模拟器）
  iss.py              执行镜像，生成期望轨迹 expect.trace
  test_iss.py         参考模型的单元测试
sw/common/          测试程序公共文件
  link.ld             链接脚本：.text 在 0x0，数据段在 0x0001_0000
  io.h                地址空间与 I/O 寄存器定义
  pad.h               空指令填充宏 PAD_DATA、PAD_JUMP、SEP
  qmul.h              qmul 指令宏
  test.h              测试骨架宏 TEST_BEGIN、CHECK、TEST_END 等
sw/tests/<isa>/<suite>/<name>.S
                    测试程序；<isa> 是 base9、rv32i、rv32i_qmul
scripts/
  build.py            构建：.S → prog.elf → imem.hex/dmem.hex/prog.dump → expect.trace
  elf2hex.py          ELF → 两个 1024 行的 $readmemh 镜像
  compare_trace.py    比对期望轨迹和 CPU 轨迹
  run_tests.py        回归驱动：构建、iverilog 编译、逐个仿真、汇总
  gen_random.py       随机测试程序生成器
  rand_stats.py       随机测试的指令与冒险组合统计
  test_compare_trace.py
rtl/ tb/ sim/       硬件、测试平台、仿真脚本（见 rtl/README.md）
build/              生成物（不入库）；随机测试的源码生成在 build/src/
```

## 环境

- Python 3（只用标准库）
- RISC-V 工具链 `riscv64-elf-gcc`、`riscv64-elf-objdump`；前缀不同时设置环境变量 `RISCV_PREFIX`，例如 `RISCV_PREFIX=riscv32-unknown-elf-`
- 跑 CPU 仿真需要 Icarus Verilog（`iverilog`、`vvp`）；`--iss-only` 和 `make iss-check` 不需要

## 构建

```
make images                       # 全部测试加每层 30 个随机测试，pad 和 nopad 两个变体
make images ISA=base9 VARIANT=pad
python3 scripts/build.py --isa base9 --variant both --suite hazard -k 'load_*'
python3 scripts/build.py --isa rv32i --variant nopad --random 100 --seed 1
```

`make images` 除了所选 ISA 及以下各层的手写测试，还带上每一层种子 1～30 的随机测试（见下文"随机测试"），所以 ModelSim 回归不需要 Python 也能跑到随机测试。

每个测试构建到 `build/<variant>/<isa>/<suite>/<name>/`：

| 文件 | 内容 |
|---|---|
| `imem.hex`、`dmem.hex` | `$readmemh` 镜像，恰好 1024 行 |
| `expect.trace` | 参考模型生成的期望轨迹 |
| `prog.elf`、`prog.dump` | 调试用；dump 里是反汇编（不用伪指令、寄存器写编号）和数据段内容 |

`build/<variant>/tests.lst` 每行一个测试目录（相对仓库根），内容是这一变体最近一次构建所选的测试。ModelSim 回归读的就是它，所以在 Windows 上跑 ModelSim 之前，先在 Linux 上用 `make images`（或带 `ISA=`、`VARIANT=` 的形式）把要跑的测试构建好，连同 `build/` 一起拷过去。

构建失败时，各步骤的命令行和输出打印在终端上（`-v` 时成功的也打印）。构建时还做这些检查，任何一项不过都算构建失败：

- 可执行段的每个字都能按该测试的 ISA 子集解码；
- 参考模型带 `--check-uninit`：读从未写过的寄存器（x0 除外）报错；
- pad 变体还带 `--check-pad`：每次读寄存器距上次写它至少隔 3 条动态指令，每条执行到的分支、跳转后面紧跟 3 条 `add x0, x0, x0`；
- 参考模型必须在步数上限内写 FINISH。

## 运行

```
make stage1         # 阶段 1：base9 测试，pad 变体，跑 CPU
make stage2         # 阶段 2：base9 测试，nopad 变体，加 200 个 base9 随机测试
make stage3         # 阶段 3：rv32i（含 base9）测试，nopad，加 500 个 rv32i 随机测试
make stage4         # 阶段 4：rv32i_qmul（含前两层）测试，nopad，加 500 个 rv32i_qmul 随机测试，
                    #         然后有 scripts/ntt_report.py 时运行它
make random ISA=rv32i N=5000 SEED=1000   # 只跑随机测试（nopad），种子 SEED..SEED+N-1
make iss-check      # 全部手写测试加每层 30 个随机测试、两个变体，只在参考模型上跑
make rand-stats ISA=rv32i N=1000 SEED=1  # 随机测试的覆盖统计
make unit-test      # 参考模型和 compare_trace 的单元测试
make clean          # 删除 build/
```

各阶段入口的随机测试种子都从 1 开始，结果可以复现。`make stage*`、`random`、`iss-check` 可以用 `ARGS` 追加 `run_tests.py` 的参数，`JOBS` 指定并行数，例如 `make stage2 ARGS="--suite hazard -C 6"`。`make random` 的 `ISA` 默认 `rv32i_qmul`，`N` 默认 1000，`SEED` 默认 1。stage5 目前只是占位。

每次运行都会按这次所选的测试重写 `build/<variant>/tests.lst`；要给 ModelSim 准备测试列表，最后跑一次 `make images`。

### run_tests.py

```
python3 scripts/run_tests.py [--isa ISA] [--variant pad|nopad|both] [--suite S] [-k PAT]
                             [--random N [--seed S] [--random-all-isas]]
                             [-j N] [--iss-only] [--max-cycles N] [--pipe] [-C N]
```

| 参数 | 含义 |
|---|---|
| `--isa` | ISA 子集，累积选择：`rv32i` 同时包括 base9 的测试。默认 `rv32i_qmul`（全部） |
| `--variant` | `pad`（默认）、`nopad` 或 `both` |
| `--suite` | 只跑这些 suite（`isa`、`hazard`、`prog`、`ntt`，随机测试是 `rand`），可重复或用逗号分隔 |
| `-k` | 只跑 id（`isa/suite/name`）或名字匹配通配的测试，可重复 |
| `--random N` | 另加 N 个随机测试，ISA 取 `--isa` 那一层 |
| `--seed S` | 随机测试的起始种子，用种子 S..S+N-1，默认 1 |
| `--random-all-isas` | `--isa` 及以下每一层各加 N 个随机测试 |
| `-j` | 并行数，默认 CPU 个数 |
| `--iss-only` | 不跑 CPU，只看参考模型是否以 FINISH 0 结束 |
| `--max-cycles` | 传给测试平台的 `+MAXCYCLES` |
| `--pipe` | 传 `+PIPE`，每个测试的 `sim.log` 里带流水线图 |
| `-C` | 轨迹不一致时显示的上下文条数，默认 3 |

流程：构建所选测试 → `iverilog` 编译一次（读 `sim/files.f`）→ 每个测试运行一次 `vvp` → 解析测试平台最后的 `RESULT:` 行 → 打印汇总表（结果、周期数、指令数、停顿数、冲刷数）。每个测试的 `sim.log`（vvp 全部输出）和 `cpu.trace` 留在它的构建目录里。脚本会用 `compare_trace` 再独立比对一次轨迹：测试平台报 PASS 但轨迹不一致也算失败。有失败时，汇总表后面打印每个失败测试的 `RESULT` 行和第一处不一致的上下文。任何测试失败时退出码为 1，iverilog 编译失败时为 2。

单个测试也可以直接用 `sim/run_one.sh <测试目录> [plusarg ...]`（见 rtl/README.md）。

### compare_trace.py

```
python3 scripts/compare_trace.py build/nopad/base9/hazard/load_use/expect.trace \
                                 build/nopad/base9/hazard/load_use/cpu.trace [-C N]
```

报告第一处不一致的序号、PC、期望事件和实际事件以及前后上下文。期望里的 X 行（从计数器读数的 load）只要求实际是同一 pc、同一 rd 的 R 行，不比较值。退出码：0 一致，1 不一致，2 文件格式错误。

### iss.py

```
python3 model/iss.py --isa base9 --imem imem.hex --dmem dmem.hex [--trace expect.trace]
                     [--max-steps N] [--check-pad] [--check-uninit]
```

执行到写 FINISH 为止，打印 `FINISH code=<码> instret=<条数>`；每次写 MARK 打印 `MARK <值> instret=<条数>`。instret 包括这条 store 本身。退出码：0 正常写了 FINISH（不论码值），1 执行出错（非法指令、超出子集、越界或不对齐访问、非法 I/O 访问、超过步数上限等，错误信息在标准错误），2 文件读写错误。出错时已执行部分的轨迹照样写出。

参考模型里四个计数器的读数：CYCLE 和 INSTRET 都返回已提交的指令数，STALLS、FLUSHES 返回 0。这些值只用于让程序能继续跑，轨迹里对应的写回记为 X，不参与比对。

## 随机测试

`scripts/gen_random.py` 按 ISA 子集和种子生成一个测试程序，同样的参数总是生成同样的程序：

```
python3 scripts/gen_random.py --isa rv32i --seed 42 [-o out.S]
```

程序不自检，最后写 FINISH 0；通过的标准是 CPU 轨迹和参考模型的期望轨迹一致。随机测试同样构建 pad 和 nopad 两个变体，pad 变体按规则插好空指令（构建时的 `--check-pad` 检查）。

生成方式：

- 只用 x1～x6 作运算寄存器，让依赖足够密集；x7 是数据区基址（只读），x8～x10 用于循环计数和临时值。开头从数据区装入 x1～x6 的随机初值。
- 访存地址都在数据区内且字对齐：基址加常数偏移，或从数据区里的指针表取地址，rv32i 及以上还有把运算结果 `andi` 成字偏移再加基址的形式。
- 控制流只有向前的分支和跳转，外加次数固定（2～5 次）的循环，保证程序一定结束。rv32i 及以上有函数调用（jal/jalr 返回，返回地址可能先存进栈槽再取出），jalr 的目标来自 jal 的返回地址、auipc 加偏移或数据区里的代码指针，偏移有正有负，rs1+imm 可以是奇数。
- 冒险组合按设计文档第五节的场景表成组生成：距离 1/2/3 的依赖、连续写同一寄存器、写 x0 后读、load-use（运算、分支、jalr、store 地址、qmul）、load 后紧跟 store 数据、运算后 store、分支依赖刚算出或刚读出的值、跳转后错误路径上的写寄存器/store/load-use、跳转到下一条、连续跳转等。

随机测试的 id 是 `<isa>/rand/seed<k>`，源码生成在 `build/src/<isa>/rand/seed<k>.S`（内容不变时不重写），构建目录和其他测试一样是 `build/<variant>/<isa>/rand/seed<k>/`。

`scripts/rand_stats.py` 构建一批随机测试（nopad），在参考模型上逐条执行，统计每条指令的执行次数、出现在多少个程序里，以及场景表里每种组合的出现次数。统计按实际执行的指令流判定（"距离 k"指前面第 k 条动态指令写了这个寄存器），不看生成器的意图。适用于该 ISA 的某个指令或组合一次都没出现时，退出码为 1。

```
python3 scripts/rand_stats.py --isa rv32i_qmul --count 1000 --seed 1
```

## 添加测试

1. 在 `sw/tests/<isa>/<suite>/` 下新建 `<name>.S`，放在它最少需要的那个 ISA 子集下。目录存在即被发现，不用登记。
2. 骨架：

```
#include "test.h"

TEST_BEGIN
    LI      x5, 0x7fffffff, x6     // 需要临时寄存器的常数要给第三个参数
    LI      x7, 1
    PAD_DATA
    add     x8, x5, x7
    PAD_DATA
    CHECK   x8, 0x80000000, 1      // 不等就以 FINISH 1 结束
TEST_END
```

3. 跑 `python3 scripts/run_tests.py --variant both --iss-only -k <name>`，两个变体都必须通过，然后再跑 CPU。

规则：

- **期望值手算**，写成常数，不要从参考模型的输出里抄。`CHECK` 的期望值由汇编器放进 `.rodata`，用 `lw` 读出比较，不依赖被测指令；也可以写标号（例如 jal 的返回地址）。
- **失败码**：同一个测试里每个 `CHECK` 用不同的码（1～2047），在文件头注释里列出每个码对应的检查项。`0xbad00000` 表示失败码本身没构造出来（`ori` 坏了）。CPU 有错时，宏本身也跑在同一条流水线上，失败码可能失真，这时以轨迹比对报告为准。
- **x30、x31（t5、t6）归宏使用**，测试代码不要在里面放要保留的值。x2（sp）由 `TEST_BEGIN` 设为 0x0001_1000。
- **注释**用 `//` 或 `/* */`。`.S` 先过 C 预处理器，行首的 `#` 会被当成预处理指令。
- **base9 测试只能用 base9 指令**：没有 addi，`nop`、`li`、`mv`、`la` 都不能用。常数用 `LI`，地址用 `LA`，空指令写 `add x0, x0, x0`（`NOP0`）。宏的用法见 `sw/common/test.h` 文件头。
- **填充**（`sw/common/pad.h`）：同一份源码构建出 pad 和 nopad 两个变体，pad 变体定义 `PAD`。
  - `PAD_DATA`：pad 变体里是 2 条空指令。放在有数据依赖的两条指令之间（相隔不足 3 条时）。
  - `PAD_JUMP`：pad 变体里是 3 条空指令。紧跟在每条分支、跳转之后。
  - `SEP`：两个变体里都是 3 条空指令。用来隔开前后代码，让 nopad 变体里要测的冒险场景前后没有别的依赖。
  - pad 变体的规则由构建时的 `--check-pad` 检查，漏了会构建失败并指出 pc。
- **冒险测试**（`hazard` suite）：每个测试对应设计文档第五节"冒险场景一览"表里的一行，文件头注释写明是哪一行；nopad 变体里该场景必须按原样出现（可以在 `prog.dump` 里核对），pad 变体也要通过。被测目的寄存器事先装上别的值，以免旧值碰巧等于期望值。
- **单指令用例**：`TEST_RR op, a, b, expect, code`、`TEST_RI op, a, imm, expect, code`、`TEST_BR op, a, b, taken, code`，操作数放在 x5、x6，结果写 x10（事先装上 0x5a5a5000），x7 作临时寄存器。详见 `sw/common/test.h`。
- qmul 用 `#include "qmul.h"` 后写 `qmul rd, rs1, rs2`。
- **计数器**用 `READ_COUNTER rd, IO_CYCLE` 读，`MARK_POINT id` 打点。读数以及由它算出的值不能存进存储器、写给 MARK/FINISH 或用作分支条件，读进来的寄存器之后要覆盖掉。要测一段代码的周期数，就在它前后各写一次 MARK，测试平台会打印当时的计数器。

## 测试一览

| suite | 测试 | 覆盖 |
|---|---|---|
| base9/isa | add、slt、sltu、ori、lui、lw、sw、beq、jal | 每条指令一个测试：溢出与进位、有符号与无符号比较、ori 立即数符号扩展、lui 低位清零、正负偏移和 ±2 KB 边界、x0 作源和目的、rd 与源相同、远距离（超过 2 KB）的前后跳转、链接地址 |
| base9/hazard | raw_dist1、raw_dist2、raw_dist3、waw_mprio、x0_write、load_use、load_dist2、load_store_data、load_store_addr、alu_store_dist2、branch_alu_dep、branch_load_dep、jump_flush、jump_store、flush_stall、jump_chain | 设计文档第五节冒险场景表中 base9 能表达的各行（jalr 那行放到 rv32i） |
| base9/prog | sum、checksum、counters | 小程序：1 到 100 求和；数组校验和、最大值、负数计数；计数器读数、MARK 打点 |
| rv32i/isa | sub、and、or、xor、sll、srl、sra、addi、andi、xori、slti、sltiu、slli、srli、srai、bne、blt、bge、bltu、bgeu、jalr、auipc | 每条新指令一个测试：sub 溢出；移位量 0 和 31，寄存器移位只取低 5 位（32、33、-1 等）；srl 与 sra、srli 与 srai（第 30 位）的区别；立即数符号扩展（slti/sltiu 的负立即数）；分支的有符号/无符号边界、相等、向前和向后；auipc 含最高位为 1 的立即数；jalr 的返回地址、最低位清零、负偏移、rd = rs1 时用旧值、rd = x0 |
| rv32i/hazard | jalr_load_dep、jalr_alu_dep、jalr_flush、upper_fwd、shift_fwd、branch_fwd、call_return | jalr 依赖 load（停顿）和依赖刚算出的值（转发，含 M 段优先）；jalr 冲刷 3 条（错误路径上的写、store、load-use）；lui/auipc 结果转发；移位量转发；新分支指令依赖转发值；调用返回时马上使用返回地址寄存器 |
| rv32i/prog | sort、fib、crc32、muldiv | 插入排序（有符号升序）和选择排序（无符号降序）；递归 fib（jal/jalr 和栈）与迭代 fib(47)；按位计算的 CRC-32；软件乘法和恢复余数除法。期望值由独立的 Python 计算 |
| \<isa\>/rand | seed\<k\> | 随机测试，见"随机测试" |

## 硬件

见 [rtl/README.md](rtl/README.md)。
