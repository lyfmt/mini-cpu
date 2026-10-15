# rtl/ — 五级流水线 RISC-V CPU

设计依据是设计文档第三、四、五、八节；接口细节见实现约定。只用 Verilog-2001，全部逻辑只用时钟上升沿，复位是同步、高有效。

## 模块

| 文件 | 模块 | 作用 |
|---|---|---|
| `defines.vh` | — | opcode、ExtOp、ALUASrc/ALUBSrc、ALUctr、转发选择、I/O 偏移的编码 |
| `cpu_top.v` | `cpu_top` | 顶层：流水线 + 指令存储器 + 数据存储器 + I/O；地址第 31 位选数据存储器或 I/O |
| `cpu_core.v` | `cpu_core` | 五级流水线、四个流水线寄存器、各段选择器 |
| `control.v` | `control` | 主控制器（ID 段），一次生成全部控制信号；不认识的指令输出气泡 |
| `extender.v` | `extender` | 扩展器，ExtOp 选 I/S/B/U/J 五种立即数 |
| `regfile.v` | `regfile` | 寄存器堆，两读一写，x0 恒 0，同周期写读内部旁路 |
| `alu.v` | `alu` | ALU：加、减、有符号/无符号比较、或、直通 B；zero 给 beq 用 |
| `forward_unit.v` | `forward_unit` | 转发单元（BusAFw、BusBFw、DiSrc）。阶段 1 是桩，输出恒为 00/0 |
| `hazard_unit.v` | `hazard_unit` | 冒险检测（stall、flush）。阶段 1 是桩，输出恒为 0 |
| `imem.v` | `imem` | 指令存储器，4 KB，组合逻辑读出；参数 `INIT_FILE` |
| `dmem.v` | `dmem` | 数据存储器，4 KB，组合逻辑读出、上升沿写入；参数 `INIT_FILE` |
| `io_regs.v` | `io_regs` | I/O 寄存器：FINISH、CYCLE、INSTRET、STALLS、FLUSHES、MARK |

实例层次（测试平台顶层是 `tb_top`）：

```
tb_top
└── u_cpu          cpu_top
    ├── u_core     cpu_core
    │   ├── u_ctrl control
    │   ├── u_rf   regfile
    │   ├── u_ext  extender
    │   ├── u_hzd  hazard_unit
    │   ├── u_fwd  forward_unit
    │   └── u_alu  alu
    ├── u_imem     imem
    ├── u_dmem     dmem
    └── u_io       io_regs
```

`cpu_top` 的参数 `IMEM_INIT`、`DMEM_INIT` 供综合指定初始镜像。仿真时留空，由测试平台按 `+IMEM`/`+DMEM` 用 `$readmemh` 直接写进 `u_imem.mem`、`u_dmem.mem`。对外端口只有 `clk`、`rst` 和 FINISH/MARK 的写入（`finish`、`mark`、`io_wdata`），综合时整条数据通路都有负载。

## 信号命名

`cpu_core` 里的信号以所在的段为前缀：`if_`、`id_`、`ex_`、`m_`、`wb_`。

- 流水线寄存器的输出以"使用它的段"为前缀：IF/ID 的输出是 `id_*`，ID/EX 是 `ex_*`，EX/M 是 `m_*`，M/WB 是 `wb_*`。所以 `ex_pc` 就是"EX 段那条指令的 PC"。
- 段内的组合信号用同一前缀，例如 `ex_fwdA`、`m_redirect`。
- 控制信号沿用课程名字：`ex_ALUctr`、`m_MemWr`、`wb_RegWr`……

气泡 = 有效位和全部控制信号为 0（其余字段也清 0）。复位时 PC 清 0，所有流水线寄存器都是气泡。

下表的路径都在 `/tb_top/u_cpu/u_core/` 之下（ModelSim 写法；iverilog 里用 `tb_top.u_cpu.u_core.`）。

### 各级身份（PC、指令、有效位）

| 段 | PC | 指令 | 有效位 |
|---|---|---|---|
| IF | `if_pc` | `if_inst` | —（IF 总是在取指） |
| ID | `id_pc` | `id_inst` | `id_valid` |
| EX | `ex_pc` | `ex_inst` | `ex_valid` |
| M | `m_pc` | `m_inst` | `m_valid` |
| WB | `wb_pc` | `wb_inst` | `wb_valid` |

### 各段关键信号

| 段 | 信号 | 含义 |
|---|---|---|
| IF | `if_pc_plus4` | PC + 4 |
| ID | `id_rs1` `id_rs2` `id_rd` | 寄存器号（固定取自 inst[19:15]、[24:20]、[11:7]） |
| ID | `id_busA` `id_busB` | 寄存器堆读出（已含同周期旁路） |
| ID | `id_imm` | 扩展器输出 |
| ID | `id_ExtOp` `id_ALUASrc` `id_ALUBSrc` `id_ALUctr` `id_Branch` `id_Jump` `id_MemRead` `id_MemWr` `id_MemtoReg` `id_RegWr` | 主控制器输出 |
| ID | `id_UseRs1` `id_UseRs2` | 是否读 rs1/rs2（load-use 检测用） |
| ID/EX | `ex_rs1` `ex_rs2` `ex_rd` `ex_busA` `ex_busB` `ex_imm` 及 `ex_<控制信号>` | |
| EX | `ex_BusAFw` `ex_BusBFw` | 转发选择（00 ID 段读出值，01 WB 写回值，10 EX/M 运算结果） |
| EX | `ex_fwdA` `ex_fwdB` | 转发选择器输出 |
| EX | `ex_alu_a` `ex_alu_b` | ALU 两端（ALUASrc、ALUBSrc 选择之后） |
| EX | `ex_aluout` `ex_zero` | ALU 结果、Zero |
| EX | `ex_target` | 目标加法器 PC + imm |
| EX | `ex_cond` | 条件成立（基础版本即 Zero） |
| EX/M | `m_rd` `m_rs2` `m_aluout` `m_target` `m_cond` `m_busB` 及 `m_<控制信号>` | `m_busB` 是转发之后的 store 数据 |
| M | `m_redirect` | `Branch & 条件成立 \| Jump`，为 1 时 PC 换成 `m_target` |
| M | `m_DiSrc` `m_DataIn` | DiSrc 及修正后的 store 数据 |
| M | `dbus_addr` `dbus_re` `dbus_we` `dbus_wdata` `dbus_rdata` | 数据总线（存储器 + I/O） |
| M/WB | `wb_rd` `wb_aluout` `wb_dout` `wb_MemtoReg` `wb_RegWr` | `wb_dout` 是存储器 / I/O 读出值 |
| WB | `wb_busW` | 最终写回值（MemtoReg 选择之后） |
| 冒险 | `stall` `flush` | 冒险检测单元输出 |

### 结果落点

| 写端口 | 路径 |
|---|---|
| 寄存器堆 | `/tb_top/u_cpu/u_core/u_rf/we`、`wa`、`wd` |
| 数据存储器 | `/tb_top/u_cpu/u_dmem/we`、`addr`（字地址）、`wdata` |
| I/O 写 | `/tb_top/u_cpu/finish`、`mark`、`io_wdata` |
| 计数器 | `/tb_top/u_cpu/u_io/cycle_cnt`、`instret_cnt`、`stall_cnt`、`flush_cnt` |

## 控制信号编码

| 信号 | 编码 |
|---|---|
| ExtOp | 0 I，1 S，2 B，3 U，4 J |
| ALUASrc | 0 rs1，1 PC |
| ALUBSrc | 00 rs2，01 立即数，10 常数 4 |
| ALUctr | 加 0000，减 1000，slt 0010，sltu 0011，或 0110，直通 B 1111 |
| BusAFw/BusBFw | 00 ID 段读出值，01 WB 写回值，10 EX/M 运算结果 |

ALUctr 对 R 型运算取 `{inst[30], funct3}`，以后扩展整组运算时译码器可以把 funct3 原样交给 ALU。

## I/O 与计数器

基址 0x8000_0000，偏移见实现约定第 3 节。计数器在复位时清 0，每个时钟沿更新；读出的、MARK 和 RESULT 行打印的都是"当拍"的值，即不含当前这一拍：

- CYCLE：复位释放后的第一个周期读到 0；
- INSTRET：此前 WB 段有效位为 1 的周期数；
- STALLS、FLUSHES：此前 `stall`、`flush` 为 1 的周期数。冒险检测单元在阶段 1 恒输出 0，所以这两个计数器恒为 0。

## 阶段 2 要填的地方

结构已经留好，只需往两个桩模块里填逻辑：

- `forward_unit.v`：BusAFw、BusBFw、DiSrc 的判断。转发选择器、DiSrc 选择器，以及"store 数据取转发之后的 busB"都已经接好。
- `hazard_unit.v`：`stall`（load-use）和 `flush`（等于 `m_redirect`）。PC、各级流水线寄存器对 `stall`/`flush` 的响应（冲刷优先于停顿）已经写在 `cpu_core.v` 里，`io_regs` 也已经按它们计数。

## 运行仿真

以下命令都在仓库根目录执行。

### iverilog

```
iverilog -g2001 -s tb_top -o build/sim/cpu.vvp -f sim/files.f
vvp -n build/sim/cpu.vvp +IMEM=<dir>/imem.hex +DMEM=<dir>/dmem.hex +EXPECT=<dir>/expect.trace +TRACE=<dir>/cpu.trace
```

跑单个测试的快捷脚本（必要时自动重新编译；有 `expect.trace` 就自动比对；CPU 轨迹写到 `<dir>/cpu.trace`；其余参数原样传给 vvp）：

```
sim/run_one.sh build/pad/base9/isa/add
sim/run_one.sh build/pad/base9/isa/add +PIPE +MAXCYCLES=1000
```

退出码 0 表示 PASS。

### 测试平台参数

| 参数 | 说明 |
|---|---|
| `+IMEM=` `+DMEM=` | 必需，程序镜像 |
| `+EXPECT=` | 可选，期望轨迹；第一处不一致就打印出错周期、PC、期望和实际事件，以 FAIL 结束 |
| `+TRACE=` | 可选，CPU 轨迹输出文件 |
| `+MAXCYCLES=` | 可选，默认 200000 |
| `+PIPE` | 可选，每周期打印一行时空图 |

时空图每行是一个周期：五级各自的 PC（气泡显示为 `--------`），以及当拍的 BusAFw、BusBFw、DiSrc、stall、flush 和 M 段重定向：

```
PIPE      5 | IF 00000014 | ID 00000010 | EX 0000000c | M 00000008 | WB 00000004 | FwA 00 FwB 00 DiSrc 0 | stall 0 flush 0 redirect 0
```

最后一行固定是 `RESULT: PASS ...` 或 `RESULT: FAIL <原因> ...`。失败原因：

| 原因 | 含义 |
|---|---|
| `mismatch` | 某条事件与期望不一致 |
| `extra_event` | 期望轨迹已用完，CPU 又产生了事件 |
| `missing_event` | 程序已写 FINISH，期望轨迹还没用完 |
| `finish_code=<n>` | FINISH 写入了非 0 |
| `timeout` | 超过 MAXCYCLES |
| `no_imem_plusarg` `no_dmem_plusarg` `cannot_open_*` | 参数缺失或文件打不开 |

### ModelSim

脚本在 `sim/modelsim/`，都从仓库根目录运行，路径相对仓库根。编译库放在 `build/modelsim/work`，按路径引用，不写 `modelsim.ini`。

| 文件 | 用途 |
|---|---|
| `compile.do` | `vlog -f sim/files.f` 编译到 `build/modelsim/work` |
| `regress.do` | 批量回归：读 `build/<变体>/tests.lst`，逐个运行，汇总 PASS/FAIL，清单写到 `build/modelsim/regress_<变体>.txt` |
| `regress.bat` | Windows 入口：`sim\modelsim\regress.bat [pad\|nopad]`，日志在 `build/modelsim/regress_<变体>.log`，全部通过时退出码为 0 |
| `run_one.do` | 跑单个测试；在 GUI 里自动加载 `wave.do` |
| `run_one.bat` | Windows 入口：`sim\modelsim\run_one.bat <测试目录> [plusarg ...]`，打开 GUI |
| `wave.do` | 基本波形布局：各级 PC/指令/有效位、冒险信号、寄存器堆和数据存储器写端口、I/O |

在 ModelSim 里也可以直接执行：

```
vsim -c -do "do sim/modelsim/regress.do pad"
vsim -do "do sim/modelsim/run_one.do build/pad/base9/isa/add"
```

镜像和期望轨迹要事先在 Linux 上生成到 `build/` 下，ModelSim 这边不需要 Python 和 RISC-V 工具链。回归脚本用 `-onfinish stop` 载入设计，仿真结束后读 `/tb_top/result_status`（1 PASS，2 FAIL）判定结果。

`.do` 和 `.bat` 只用 ASCII 字符：中文 Windows 上 Tcl 按 GBK 读脚本，UTF-8 中文后面紧跟的 `{`、`}`、`$` 可能被吞掉。
