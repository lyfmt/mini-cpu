# rtl/ — 五级流水线 RISC-V CPU

设计依据是设计文档第二至八节；接口细节见实现约定。只用 Verilog-2001，全部逻辑只用时钟上升沿，复位是同步、高有效。

## 模块

| 文件 | 模块 | 作用 |
|---|---|---|
| `defines.vh` | — | opcode、ExtOp、ALUASrc/ALUBSrc、TargetSrc、ALUctr、BrOp、转发选择、I/O 偏移的编码 |
| `cpu_top.v` | `cpu_top` | 顶层：流水线 + 指令存储器 + 数据存储器 + I/O；地址第 31 位选数据存储器或 I/O |
| `cpu_core.v` | `cpu_core` | 五级流水线、四个流水线寄存器、各段选择器；参数 `HAS_QMUL` |
| `control.v` | `control` | 主控制器（ID 段），一次生成全部控制信号；不在 rv32i_qmul 范围内的指令输出气泡；参数 `HAS_QMUL` |
| `extender.v` | `extender` | 扩展器，ExtOp 选 I/S/B/U/J 五种立即数 |
| `regfile.v` | `regfile` | 寄存器堆，两读一写，x0 恒 0，同周期写读内部旁路 |
| `alu.v` | `alu` | ALU：加、减、与、或、异或、三种移位、有符号/无符号比较、直通 B |
| `branch_cmp.v` | `branch_cmp` | 比较单元（EX 段，和 ALU 并列）：按 BrOp 给出六种分支的"条件成立" |
| `qmul_unit.v` | `qmul_unit` | 模乘单元（EX 段，和 ALU 并排）：定制指令 qmul，(rs1[11:0] × rs2[11:0]) mod 3329，单周期 |
| `forward_unit.v` | `forward_unit` | 转发单元：EX 段的 BusAFw、BusBFw，M 段的 DiSrc |
| `hazard_unit.v` | `hazard_unit` | 冒险检测：load-use 停顿（stall）、跳转冲刷（flush） |
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
    │   ├── u_alu  alu
    │   ├── u_cmp  branch_cmp
    │   └── g_qmul/u_qmul  qmul_unit（只在 HAS_QMUL = 1 时存在）
    ├── u_imem     imem
    ├── u_dmem     dmem
    └── u_io       io_regs
```

`cpu_top` 的参数 `IMEM_INIT`、`DMEM_INIT` 供综合指定初始镜像。仿真时留空，由测试平台按 `+IMEM`/`+DMEM` 用 `$readmemh` 直接写进 `u_imem.mem`、`u_dmem.mem`。对外端口只有 `clk`、`rst` 和 FINISH/MARK 的写入（`finish`、`mark`、`io_wdata`），综合时整条数据通路都有负载。

### 去掉模乘单元：HAS_QMUL

`cpu_top` 的参数 `HAS_QMUL`（默认 1）层层传到 `cpu_core` 和 `control`：

| HAS_QMUL | 模乘单元 | qmul 编码 | 支持的指令集 |
|---|---|---|---|
| 1（默认） | 在 EX 段例化（`u_core/g_qmul/u_qmul`） | qmul | rv32i_qmul |
| 0 | 不例化（generate 走 `g_no_qmul` 分支，结果选择器的 qmul 一路是常数 0，综合时被去掉） | 非法指令（气泡） | rv32i |

切换方法：

- Vivado 综合：`synth_design -top cpu_top -generic HAS_QMUL=0 ...`（GUI 里是 Settings → Synthesis → More Options 填 `-generic HAS_QMUL=0`）；
- 测试平台 `tb_top` 也有同名参数，原样传给 `cpu_top`：iverilog 用 `iverilog -Ptb_top.HAS_QMUL=0 ...`，ModelSim 用 `vsim -gHAS_QMUL=0 ...`；
- verilator lint：`verilator --lint-only -Wall -Irtl rtl/*.v --top-module cpu_top -GHAS_QMUL=0`。

两种配置都能通过 lint；HAS_QMUL = 0 时 base9、rv32i 的全部测试照常通过。

## 信号命名

`cpu_core` 里的信号以所在的段为前缀：`if_`、`id_`、`ex_`、`m_`、`wb_`。

- 流水线寄存器的输出以"使用它的段"为前缀：IF/ID 的输出是 `id_*`，ID/EX 是 `ex_*`，EX/M 是 `m_*`，M/WB 是 `wb_*`。所以 `ex_pc` 就是"EX 段那条指令的 PC"。
- 段内的组合信号用同一前缀，例如 `ex_fwdA`、`m_redirect`。
- 控制信号沿用课程名字：`ex_ALUctr`、`m_MemWr`、`wb_RegWr`……

气泡 = 有效位和全部控制信号为 0（其余字段也清 0）。复位时 PC 清 0，所有流水线寄存器都是气泡。

流水线寄存器里的指令字（`id_inst` 由 ID 段译码，之后的 `ex_inst`、`m_inst`、`wb_inst`）只用于调试和测试平台观察；PC 只在 EX 段参与运算（auipc、jal/jalr 的返回地址、分支和 jal 的目标），`m_pc`、`wb_pc` 也只用于调试。EX 段以后要用到的指令字段（寄存器号、立即数、BrOp 等）都由 ID 段译出，作为字段或控制信号随流水线传下去，不再从 `ex_inst`、`m_inst` 里取位段。

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
| ID | `id_ExtOp` `id_ALUASrc` `id_ALUBSrc` `id_ALUctr` `id_TargetSrc` `id_BrOp` `id_Branch` `id_Jump` `id_MemRead` `id_MemWr` `id_MemtoReg` `id_RegWr` | 主控制器输出 |
| ID | `id_UseRs1` `id_UseRs2` | 是否读 rs1/rs2（load-use 检测用） |
| ID/EX | `ex_rs1` `ex_rs2` `ex_rd` `ex_busA` `ex_busB` `ex_imm` 及 `ex_<控制信号>` | |
| EX | `ex_BusAFw` `ex_BusBFw` | 转发选择（00 ID 段读出值，01 WB 写回值，10 EX/M 运算结果） |
| EX | `ex_fwdA` `ex_fwdB` | 转发选择器输出 |
| EX | `ex_alu_a` `ex_alu_b` | ALU 两端（ALUASrc、ALUBSrc 选择之后） |
| EX | `ex_aluout` | ALU 结果 |
| EX | `ex_qmul_y` | 模乘单元输出（HAS_QMUL = 0 时恒为 0） |
| EX | `ex_result` | 结果选择器输出：ALUctr 为 QMUL 时取 `ex_qmul_y`，否则取 `ex_aluout`；存进 EX/M 的 `m_aluout` |
| EX | `ex_BrOp` `ex_cond` | 比较单元的条件（控制信号，随 ID/EX 传来）和"条件成立" |
| EX | `ex_tgt_base` `ex_target` | 目标加法器的基地址（PC 或转发之后的 rs1）、跳转目标（最低位已清零） |
| EX/M | `m_rd` `m_rs2` `m_aluout` `m_target` `m_cond` `m_busB` 及 `m_<控制信号>` | `m_aluout` 是运算结果通路上的值（ALU 或模乘单元）；`m_busB` 是转发之后的 store 数据 |
| M | `m_redirect` | `Branch & 条件成立 \| Jump`，为 1 时 PC 换成 `m_target` |
| M | `m_DiSrc` `m_DataIn` | DiSrc 及修正后的 store 数据 |
| M | `dbus_addr` `dbus_re` `dbus_we` `dbus_wdata` `dbus_rdata` | 数据总线（存储器 + I/O） |
| M/WB | `wb_rd` `wb_aluout` `wb_dout` `wb_MemtoReg` `wb_RegWr` | `wb_dout` 是存储器 / I/O 读出值 |
| WB | `wb_busW` | 最终写回值（MemtoReg 选择之后） |
| 冒险 | `stall` `flush` | 冒险检测单元输出（`stall` 已排除和冲刷同拍的情况） |
| 冒险 | `u_hzd/load_use` | 检测到 load-use（未经冲刷屏蔽） |

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
| ALUctr | 加 0000，左移 0001，slt 0010，sltu 0011，异或 0100，逻辑右移 0101，或 0110，与 0111，减 1000，qmul 1001，算术右移 1101，直通 B 1111 |
| TargetSrc | 0 PC（分支、jal），1 rs1（jalr） |
| BrOp | 即条件分支的 funct3：beq 000，bne 001，blt 100，bge 101，bltu 110，bgeu 111；不是分支时为 000 |
| BusAFw/BusBFw | 00 ID 段读出值，01 WB 写回值，10 EX/M 运算结果 |

ALUctr 的编码就是 `{inst[30], funct3}`：R 型运算和移位立即数直接取它（add/sub、srl/sra、srli/srai 靠第 30 位区分），其余立即数运算取 `{0, funct3}`，因为它们的第 30 位是立即数的一位，addi 没有减法版本。移位量只取 B 端的低 5 位。ALUctr = 1001（QMUL）不是 ALU 的运算，ALU 对它输出 0；EX 段的结果选择器见到它时改取模乘单元的输出。

BrOp 是比较单元的条件，译码器对条件分支把 funct3 原样给出，随 ID/EX 传到 EX 段。

## 各指令的控制信号

"–"表示取什么值都不影响结果，硬件里给的是默认值（ExtOp I、ALUASrc rs1、ALUBSrc rs2、ALUctr 加、TargetSrc PC、BrOp 000）。

| 指令 | ExtOp | ALUASrc | ALUBSrc | ALUctr | TargetSrc | BrOp | Branch | Jump | MemRead | MemWr | MemtoReg | RegWr | UseRs1 | UseRs2 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| add sub sll slt sltu xor srl sra or and | – | rs1 | rs2 | `{inst[30], funct3}` | – | – | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 1 |
| addi slti sltiu xori ori andi | I | rs1 | 立即数 | `{0, funct3}` | – | – | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 0 |
| slli srli srai | I | rs1 | 立即数 | `{inst[30], funct3}` | – | – | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 0 |
| lui | U | – | 立即数 | 直通 B | – | – | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 |
| auipc | U | PC | 立即数 | 加 | – | – | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 |
| lw | I | rs1 | 立即数 | 加 | – | – | 0 | 0 | 1 | 0 | 1 | 1 | 1 | 0 |
| sw | S | rs1 | 立即数 | 加 | – | – | 0 | 0 | 0 | 1 | 0 | 0 | 1 | 1 |
| beq bne blt bge bltu bgeu | B | – | – | – | PC | funct3 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 1 |
| jal | J | PC | 4 | 加 | PC | – | 0 | 1 | 0 | 0 | 0 | 1 | 0 | 0 |
| jalr | I | PC | 4 | 加 | rs1 | – | 0 | 1 | 0 | 0 | 0 | 1 | 1 | 0 |
| qmul（HAS_QMUL = 1） | – | rs1 | rs2 | qmul | – | – | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 1 |
| 非法指令 | I | rs1 | rs2 | 加 | PC | 000 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

- 分支不再占用 ALU：条件由比较单元用转发之后的 rs1、rs2 给出，目标由目标加法器算。ALU 对分支的输出没有用处。
- jal、jalr 的返回地址 PC + 4 都由 ALU 算（A 端 PC，B 端常数 4）；目标由目标加法器算，jalr 的基地址取转发之后的 rs1，结果最低位清零。两者都在 M 段重定向，冲刷 3 条。
- qmul 的控制信号和 R 型运算一样，只是 ALUctr 为 qmul：结果走同一条运算结果通路，所以转发、load-use、冲刷全部照常适用，冒险处理逻辑没有为它改动。
- sw 的 UseRs2 = 1 是字面意思（它确实读 rs2），冒险检测单元另外用 MemWr 把 store 数据排除在 load-use 之外。

非法指令输出气泡的控制信号（有效位照常为 1，所以仍计入 INSTRET）。不在 rv32i_qmul 范围内的编码包括：

- opcode 不是上表几种的：fence、ecall/ebreak、CSR 指令、custom-1/2/3、低两位不是 11 的字、全 0 字；
- custom-0 里 qmul 以外的编码（funct3 ≠ 000 或 funct7 ≠ 0000000）；HAS_QMUL = 0 时 qmul 本身；
- lw、sw 以外的 load/store funct3（lb、lh、lbu、lhu、sb、sh 等）；
- R 型里 funct7 既不是 0000000、也不是"0100000 配 add/srl 的 funct3"的；
- 移位立即数里 inst[31:25] 不合法的（slli 必须是 0000000，srli/srai 必须是 0000000/0100000，所以第 25 位非 0 一定非法）；
- 分支 funct3 为 010、011 的，jalr funct3 不为 000 的。

## I/O 与计数器

基址 0x8000_0000，偏移见实现约定第 3 节。计数器在复位时清 0，每个时钟沿更新；读出的、MARK 和 RESULT 行打印的都是"当拍"的值，即不含当前这一拍：

- CYCLE：复位释放后的第一个周期读到 0；
- INSTRET：此前 WB 段有效位为 1 的周期数；
- STALLS：此前 `stall` 为 1 的周期数，即实际生效的 load-use 停顿。和冲刷同拍、被冲刷覆盖的那一拍不算；
- FLUSHES：此前 `flush` 为 1 的周期数，即跳转成立的次数（每次冲刷只持续一拍）。

## 冒险处理

设计文档第五节的每一项在 RTL 里的位置。扩展指令没有改动冒险逻辑：新指令的结果仍然走 ALU 通路，源寄存器仍是 rs1、rs2，只要 UseRs1/UseRs2 对每条指令给对即可。

| 机制 | 位置 | 做法 |
|---|---|---|
| EX/M 转发（10） | `forward_unit.v` | M 段指令 RegWr=1、不是 load、rd≠0，且 rd 等于 EX 段的 rs1/rs2 |
| WB 转发（01） | `forward_unit.v` | WB 段指令 RegWr=1、rd≠0，且 rd 等于 EX 段的 rs1/rs2；送的是 `wb_busW`（MemtoReg 之后） |
| M 段优先 | `forward_unit.v` | 先判断 M 段，再判断 WB 段 |
| 转发选择器 | `cpu_core.v` EX 段 | `ex_fwdA`、`ex_fwdB`：ALU 两端、比较单元、jalr 的目标基地址、store 数据都用它们 |
| store 数据取转发后的 busB | `cpu_core.v` EX/M | `m_busB <= ex_fwdB`（ALUBSrc 选择器之前） |
| DiSrc | `forward_unit.v` 判断，`cpu_core.v` M 段选择 | M 段是 store、WB 段写的正是它的 rs2：`m_DataIn = wb_busW` |
| 寄存器堆同周期旁路 | `regfile.v` | 写读同一寄存器（非 x0）时读端口直接输出写入值 |
| load-use 停顿 | `hazard_unit.v` | EX 段是 load、rd≠0，且等于 ID 段真正读的源寄存器（UseRs1/UseRs2）；store 的 rs2 不算，store 的 rs1 照样算。分支、jalr 依赖 load 时同样停顿一拍 |
| 停顿的执行 | `cpu_core.v` | PC、IF/ID 保持，ID/EX 写入气泡 |
| 冲刷 | `hazard_unit.v`：`flush = m_redirect`；`cpu_core.v` | 分支成立、jal、jalr 都一样：PC 换成 `m_target`，IF/ID、ID/EX、EX/M 写入气泡 |
| 冲刷优先于停顿 | `hazard_unit.v`：`stall = load_use & ~flush`；`cpu_core.v` 各寄存器先判断 flush | 被冲刷的指令不停顿，PC 换成目标；STALLS 也不计这一拍 |

两处行为需要说明：

- 转发选择只按寄存器号判断，不看 EX 段那条指令是否真的读这个操作数。例如 ori 的 rs2 字段其实是立即数，碰巧匹配时 BusBFw 也会非 0。这时转发来的值不会被用到，不影响结果，但时空图和波形里能看到这种转发。
- "运算后紧跟 store"时，EX/M 转发已经把新值存进了 `m_busB`，到 M 段 DiSrc 也会匹配上，再选一次同样的值。这符合设计文档里 DiSrc 的定义，同样不影响结果。

"M 段的 load 不参与 EX/M 转发"这一条在功能上观察不到：需要 load 结果的指令都会被 load-use 停顿到 load 进入 WB；不停顿的只有 store 数据，而它会在 M 段由 DiSrc 修正。

## 模乘单元

`qmul_unit` 和 ALU 并排放在 EX 段，单周期组合逻辑，输入是 ALU 两端 `ex_alu_a`、`ex_alu_b`（qmul 的 ALUASrc 选 rs1、ALUBSrc 选 rs2，所以是转发之后的 rs1、rs2）。算法与 `scripts/check_barrett.py` 的 `qmul_model()` 逐位一致：

| 步骤 | 信号 | 运算 | 位宽 |
|---|---|---|---|
| 取操作数 | `a` `b` | rs1、rs2 的低 12 位，无符号 | 12 |
| 1 | `p` | a × b | 12 × 12 → 24 |
| 2 | `pm`、`qhat` | p × 5039，取 [36:24]（即右移 24 位）；5039 = ⌊2²⁴ / 3329⌋ | 24 × 13 → 37，qhat 13 位（最大 5036） |
| 3 | `qq`、`r` | qq = qhat × 3329，r = p − qq；r 在 [0, 2q) 内 | 13 × 12 → 24，r 取低 13 位 |
| 4 | `res` | r ≥ 3329 时 r − 3329，否则 r | 12 |
| 输出 | `y` | {20'b0, res} | 32 |

三个乘法都在 DSP48E1 的 25 × 18 之内。`pm` 必须声明成 37 位：直接写 `(p * M) >> 24` 时表达式按 24 位计算，乘积高位会被截掉。

输出 `ex_qmul_y` 和 ALU 输出 `ex_aluout` 由结果选择器按 ALUctr 选出 `ex_result`，存进 EX/M 的 `m_aluout`，之后和 add 的结果走同一条路：EX/M 转发、WB 转发、写回。

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
sim/run_one.sh build/nopad/base9/hazard/load_use +PIPE
```

退出码 0 表示 PASS。

### 单元测试

```
sim/run_unit.sh
```

一条命令跑完 `tb/unit/` 下的全部单元测试，生成物在 `build/unit/`，全部通过时退出码为 0：

| 测试 | 内容 | 工具 |
|---|---|---|
| `tb_qmul.v` | 模乘单元：低 12 位的全部 4096 × 4096 种输入与 (a·b) mod 3329 比较；另抽查 100 万组高位随机的 32 位输入，确认只取低 12 位 | verilator `--binary --timing`（约 15 秒，含编译）；没有 verilator 时用 iverilog |
| `tb_control.v` | 主控制器：opcode × funct3 × funct7 全部 2¹⁷ 种组合，与独立写出的译码表逐个字段对照（合法性、全部控制信号、UseRs1/UseRs2）；HAS_QMUL = 1、0 各一次 | iverilog |
| `illegal.S` | 非法指令程序在整个 CPU 上运行：57 个非法字（字节/半字访存、fence、ecall、CSR、不合法的 funct7/funct3、custom-0 的其他编码等）和 2 条 qmul；HAS_QMUL = 1、0 各一次 | riscv64-elf-gcc、`model/iss.py`、iverilog |

`illegal.S` 由脚本现场构建成三个镜像：CPU 镜像是真正的非法字；两个参考镜像把非法字（HAS_QMUL = 0 时连同 qmul）换成 nop，由参考模型生成期望轨迹。非法指令在 CPU 里是气泡，效果和 nop 相同，所以轨迹必须一致。脚本还检查 STALLS：程序里唯一的 load-use 落在 qmul 上，HAS_QMUL = 1 时为 1，为 0 时 qmul 不读寄存器，应为 0。

### 测试平台参数

| 参数 | 说明 |
|---|---|
| `+IMEM=` `+DMEM=` | 必需，程序镜像 |
| `+EXPECT=` | 可选，期望轨迹；第一处不一致就打印出错周期、PC、期望和实际事件，以 FAIL 结束 |
| `+TRACE=` | 可选，CPU 轨迹输出文件 |
| `+MAXCYCLES=` | 可选，默认 2000000 |
| `+PIPE` | 可选，每周期打印一行时空图 |
| 参数 `HAS_QMUL` | 默认 1；`-Ptb_top.HAS_QMUL=0`（iverilog）或 `-gHAS_QMUL=0`（ModelSim）时 CPU 不带模乘单元 |

时空图每行是一个周期：五级各自的 PC（气泡显示为 `--------`），当拍的 BusAFw、BusBFw、DiSrc、stall、flush，行尾再用标记重复一遍当拍生效的机制：`A<-M`/`A<-WB`、`B<-M`/`B<-WB`（转发来源），`DiSrc`，`STALL`，`FLUSH-><目标>`。下面是 load 后紧跟使用（周期 20 停顿，EX 段空一拍，周期 22 从 WB 转发）：

```
PIPE     20 | IF 00000050 | ID 0000004c | EX 00000048 | M 00000044 | WB 00000040 | FwA 00 FwB 00 DiSrc 0 stall 1 flush 0 | STALL
PIPE     21 | IF 00000050 | ID 0000004c | EX -------- | M 00000048 | WB 00000044 | FwA 00 FwB 00 DiSrc 0 stall 0 flush 0 |
PIPE     22 | IF 00000054 | ID 00000050 | EX 0000004c | M -------- | WB 00000048 | FwA 01 FwB 00 DiSrc 0 stall 0 flush 0 | A<-WB
```

跳转成立时（周期 21 的 beq 在 M 段），下一拍前三级都是气泡，IF 是目标：

```
PIPE     21 | IF 00000054 | ID 00000050 | EX 0000004c | M 00000048 | WB 00000044 | FwA 00 FwB 00 DiSrc 0 stall 0 flush 1 | FLUSH->00000058
PIPE     22 | IF 00000058 | ID -------- | EX -------- | M -------- | WB 00000048 | FwA 00 FwB 00 DiSrc 0 stall 0 flush 0 |
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

脚本在 `sim/modelsim/`，都从仓库根目录运行，路径相对仓库根。程序镜像读随仓库提交的 `prebuilt/`（见 README.md）；工作库、波形、轨迹和日志都写到 `build/modelsim/`，脚本自己创建这个目录，不写 `modelsim.ini`。

| 文件 | 用途 |
|---|---|
| `compile.do` | `vlog -f sim/files.f` 编译到 `build/modelsim/work` |
| `regress.do` | 批量回归：读 `prebuilt/tests.lst`（或参数给的列表），逐个运行，汇总 PASS/FAIL，清单写到 `build/modelsim/regress.txt` |
| `regress.bat` | Windows 入口：`sim\modelsim\regress.bat`，日志在 `build/modelsim/regress.log`，全部通过时退出码为 0 |
| `run_one.do` | 跑单个测试（目录，或 `base9/isa/add` 这样的 id，到 `prebuilt/` 下找）；在 GUI 里自动加载 `wave.do`；轨迹写到 `build/modelsim/run_one.trace` |
| `run_one.bat` | Windows 入口：`sim\modelsim\run_one.bat <测试目录> [plusarg ...]`，打开 GUI |
| `wave.do` | 基本波形布局：各级 PC/指令/有效位，EX 段另有分支条件和跳转目标；模乘单元（输入、p/qhat/r、输出、结果选择器的输出）；冒险信号（BusAFw/BusBFw 及转发后的操作数、DiSrc 及修正前后的 store 数据、stall、flush、跳转目标）；寄存器堆和数据存储器写端口；I/O |
| `demo/<name>.do` | 演示（设计文档第九节演示表）：pipeline、forward、loaduse、storedata、flush、ext、qmul。编译、载入 `prebuilt/<isa>/demo/<name>`（带 `+PIPE`）、加载 `demo/wave_demo.do`、运行到结束，在关键周期放光标并缩放；公共部分在 `demo/start.do` |
| `run_demo.bat` | Windows 入口：`sim\modelsim\run_demo.bat <name>`，打开 GUI |

在 ModelSim 里也可以直接执行：

```
vsim -c -do "do sim/modelsim/regress.do"
vsim -do "do sim/modelsim/run_one.do prebuilt/base9/isa/add"
vsim -do "do sim/modelsim/demo/loaduse.do"
```

回归脚本用 `-onfinish stop` 载入设计，仿真结束后读 `/tb_top/result_status`（1 PASS，2 FAIL）判定结果。演示的周期号即 `/tb_top/cyc`（与 `+PIPE` 的行号、CYCLE 计数器一致）：时钟周期 10 ns，第 N 拍从 25+10N ns 到 35+10N ns，光标放在 30+10N ns。

`.do` 和 `.bat` 只用 ASCII 字符：中文 Windows 上 Tcl 按 GBK 读脚本，UTF-8 中文后面紧跟的 `{`、`}`、`$` 可能被吞掉。
