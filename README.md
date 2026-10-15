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
  test_compare_trace.py
rtl/ tb/ sim/       硬件、测试平台、仿真脚本（见 rtl/README.md）
build/              生成物（不入库）
```

## 环境

- Python 3（只用标准库）
- RISC-V 工具链 `riscv64-elf-gcc`、`riscv64-elf-objdump`；前缀不同时设置环境变量 `RISCV_PREFIX`，例如 `RISCV_PREFIX=riscv32-unknown-elf-`
- 跑 CPU 仿真需要 Icarus Verilog（`iverilog`、`vvp`）；`--iss-only` 和 `make iss-check` 不需要

## 构建

```
make images                       # 全部测试，pad 和 nopad 两个变体
make images ISA=base9 VARIANT=pad
python3 scripts/build.py --isa base9 --variant both --suite hazard -k 'load_*'
```

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
make stage1         # base9 测试，pad 变体，跑 CPU（阶段 1）
make stage2         # base9 测试，nopad 变体，跑 CPU（阶段 2）
make iss-check      # 全部测试、两个变体，只在参考模型上跑，要求都以 FINISH 0 结束
make unit-test      # 参考模型和 compare_trace 的单元测试
make clean          # 删除 build/
```

`make stage1`、`stage2`、`iss-check` 可以用 `ARGS` 追加 `run_tests.py` 的参数，`JOBS` 指定并行数，例如 `make stage2 ARGS="--suite hazard -C 6"`。stage3～stage5 目前只是占位。

### run_tests.py

```
python3 scripts/run_tests.py [--isa ISA] [--variant pad|nopad|both] [--suite S] [-k PAT]
                             [-j N] [--iss-only] [--max-cycles N] [--pipe] [-C N]
```

| 参数 | 含义 |
|---|---|
| `--isa` | ISA 子集，累积选择：`rv32i` 同时包括 base9 的测试。默认 `rv32i_qmul`（全部） |
| `--variant` | `pad`（默认）、`nopad` 或 `both` |
| `--suite` | 只跑这些 suite（`isa`、`hazard`、`prog`），可重复或用逗号分隔 |
| `-k` | 只跑 id（`isa/suite/name`）或名字匹配通配的测试，可重复 |
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
- qmul 用 `#include "qmul.h"` 后写 `qmul rd, rs1, rs2`。
- 计数器用 `READ_COUNTER rd, IO_CYCLE` 读，`MARK_POINT id` 打点；计数器读出的值不能流进会被比对的写回或 store，只能做不影响轨迹的比较（例如单调性检查后分支）。

## 测试一览

| suite | 测试 | 覆盖 |
|---|---|---|
| base9/isa | add、slt、sltu、ori、lui、lw、sw、beq、jal | 每条指令一个测试：溢出与进位、有符号与无符号比较、ori 立即数符号扩展、lui 低位清零、正负偏移和 ±2 KB 边界、x0 作源和目的、rd 与源相同、远距离（超过 2 KB）的前后跳转、链接地址 |
| base9/hazard | raw_dist1、raw_dist2、raw_dist3、waw_mprio、x0_write、load_use、load_dist2、load_store_data、load_store_addr、alu_store_dist2、branch_alu_dep、branch_load_dep、jump_flush、jump_store、flush_stall、jump_chain | 设计文档第五节冒险场景表中 base9 能表达的各行（jalr 那行放到 rv32i） |
| base9/prog | sum、checksum、counters | 小程序：1 到 100 求和；数组校验和、最大值、负数计数；计数器读数、MARK 打点 |

## 硬件

见 [rtl/README.md](rtl/README.md)。
