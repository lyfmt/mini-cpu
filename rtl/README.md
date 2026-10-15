# rtl/ — 五级流水线 RISC-V CPU

设计依据是设计文档第二至六节和第八节；接口细节见实现约定。只用 Verilog-2001，全部逻辑只用时钟上升沿，复位是同步、高有效。

## 模块

| 文件 | 模块 | 作用 |
|---|---|---|
| `defines.vh` | — | opcode、ExtOp、ALUASrc/ALUBSrc、TargetSrc、ALUctr、分支条件、转发选择、I/O 偏移的编码 |
| `cpu_top.v` | `cpu_top` | 顶层：流水线 + 指令存储器 + 数据存储器 + I/O；地址第 31 位选数据存储器或 I/O |
| `cpu_core.v` | `cpu_core` | 五级流水线、四个流水线寄存器、各段选择器 |
| `control.v` | `control` | 主控制器（ID 段），一次生成全部控制信号；不在 rv32i 范围内的指令输出气泡 |
| `extender.v` | `extender` | 扩展器，ExtOp 选 I/S/B/U/J 五种立即数 |
| `regfile.v` | `regfile` | 寄存器堆，两读一写，x0 恒 0，同周期写读内部旁路 |
| `alu.v` | `alu` | ALU：加、减、与、或、异或、三种移位、有符号/无符号比较、直通 B |
| `branch_cmp.v` | `branch_cmp` | 比较单元（EX 段，和 ALU 并列）：按 funct3 给出六种分支的"条件成立" |
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
    │   └── u_cmp  branch_cmp
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
| ID | `id_ExtOp` `id_ALUASrc` `id_ALUBSrc` `id_ALUctr` `id_TargetSrc` `id_Branch` `id_Jump` `id_MemRead` `id_MemWr` `id_MemtoReg` `id_RegWr` | 主控制器输出 |
| ID | `id_UseRs1` `id_UseRs2` | 是否读 rs1/rs2（load-use 检测用） |
| ID/EX | `ex_rs1` `ex_rs2` `ex_rd` `ex_busA` `ex_busB` `ex_imm` 及 `ex_<控制信号>` | |
| EX | `ex_BusAFw` `ex_BusBFw` | 转发选择（00 ID 段读出值，01 WB 写回值，10 EX/M 运算结果） |
| EX | `ex_fwdA` `ex_fwdB` | 转发选择器输出 |
| EX | `ex_alu_a` `ex_alu_b` | ALU 两端（ALUASrc、ALUBSrc 选择之后） |
| EX | `ex_aluout` | ALU 结果 |
| EX | `ex_funct3` `ex_cond` | 比较单元的条件选择（即 `ex_inst[14:12]`）和"条件成立" |
| EX | `ex_tgt_base` `ex_target` | 目标加法器的基地址（PC 或转发之后的 rs1）、跳转目标（最低位已清零） |
| EX/M | `m_rd` `m_rs2` `m_aluout` `m_target` `m_cond` `m_busB` 及 `m_<控制信号>` | `m_busB` 是转发之后的 store 数据 |
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
| ALUctr | 加 0000，左移 0001，slt 0010，sltu 0011，异或 0100，逻辑右移 0101，或 0110，与 0111，减 1000，算术右移 1101，直通 B 1111 |
| TargetSrc | 0 PC（分支、jal），1 rs1（jalr） |
| 分支条件（funct3） | beq 000，bne 001，blt 100，bge 101，bltu 110，bgeu 111 |
| BusAFw/BusBFw | 00 ID 段读出值，01 WB 写回值，10 EX/M 运算结果 |

ALUctr 的编码就是 `{inst[30], funct3}`：R 型运算和移位立即数直接取它（add/sub、srl/sra、srli/srai 靠第 30 位区分），其余立即数运算取 `{0, funct3}`，因为它们的第 30 位是立即数的一位，addi 没有减法版本。移位量只取 B 端的低 5 位。比较单元直接用 EX 段指令的 funct3，不另设控制信号。

## 各指令的控制信号

"–"表示取什么值都不影响结果，硬件里给的是默认值（ExtOp I、ALUASrc rs1、ALUBSrc rs2、ALUctr 加、TargetSrc PC）。

| 指令 | ExtOp | ALUASrc | ALUBSrc | ALUctr | TargetSrc | Branch | Jump | MemRead | MemWr | MemtoReg | RegWr | UseRs1 | UseRs2 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| add sub sll slt sltu xor srl sra or and | – | rs1 | rs2 | `{inst[30], funct3}` | – | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 1 |
| addi slti sltiu xori ori andi | I | rs1 | 立即数 | `{0, funct3}` | – | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 0 |
| slli srli srai | I | rs1 | 立即数 | `{inst[30], funct3}` | – | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 0 |
| lui | U | – | 立即数 | 直通 B | – | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 |
| auipc | U | PC | 立即数 | 加 | – | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 |
| lw | I | rs1 | 立即数 | 加 | – | 0 | 0 | 1 | 0 | 1 | 1 | 1 | 0 |
| sw | S | rs1 | 立即数 | 加 | – | 0 | 0 | 0 | 1 | 0 | 0 | 1 | 1 |
| beq bne blt bge bltu bgeu | B | – | – | – | PC | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 1 |
| jal | J | PC | 4 | 加 | PC | 0 | 1 | 0 | 0 | 0 | 1 | 0 | 0 |
| jalr | I | PC | 4 | 加 | rs1 | 0 | 1 | 0 | 0 | 0 | 1 | 1 | 0 |
| 非法指令 | I | rs1 | rs2 | 加 | PC | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

- 分支不再占用 ALU：条件由比较单元用转发之后的 rs1、rs2 给出，目标由目标加法器算。ALU 对分支的输出没有用处。
- jal、jalr 的返回地址 PC + 4 都由 ALU 算（A 端 PC，B 端常数 4）；目标由目标加法器算，jalr 的基地址取转发之后的 rs1，结果最低位清零。两者都在 M 段重定向，冲刷 3 条。
- sw 的 UseRs2 = 1 是字面意思（它确实读 rs2），冒险检测单元另外用 MemWr 把 store 数据排除在 load-use 之外。

非法指令输出气泡的控制信号（有效位照常为 1，所以仍计入 INSTRET）。不在 rv32i 范围内的编码包括：

- opcode 不是上表几种的：fence、ecall/ebreak、CSR 指令、custom-0（qmul 在阶段 4 才加）、低两位不是 11 的字、全 0 字；
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

### 测试平台参数

| 参数 | 说明 |
|---|---|
| `+IMEM=` `+DMEM=` | 必需，程序镜像 |
| `+EXPECT=` | 可选，期望轨迹；第一处不一致就打印出错周期、PC、期望和实际事件，以 FAIL 结束 |
| `+TRACE=` | 可选，CPU 轨迹输出文件 |
| `+MAXCYCLES=` | 可选，默认 2000000 |
| `+PIPE` | 可选，每周期打印一行时空图 |

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

脚本在 `sim/modelsim/`，都从仓库根目录运行，路径相对仓库根。编译库放在 `build/modelsim/work`，按路径引用，不写 `modelsim.ini`。

| 文件 | 用途 |
|---|---|
| `compile.do` | `vlog -f sim/files.f` 编译到 `build/modelsim/work` |
| `regress.do` | 批量回归：读 `build/<变体>/tests.lst`，逐个运行，汇总 PASS/FAIL，清单写到 `build/modelsim/regress_<变体>.txt` |
| `regress.bat` | Windows 入口：`sim\modelsim\regress.bat [pad\|nopad]`，日志在 `build/modelsim/regress_<变体>.log`，全部通过时退出码为 0 |
| `run_one.do` | 跑单个测试；在 GUI 里自动加载 `wave.do` |
| `run_one.bat` | Windows 入口：`sim\modelsim\run_one.bat <测试目录> [plusarg ...]`，打开 GUI |
| `wave.do` | 基本波形布局：各级 PC/指令/有效位，EX 段另有分支条件和跳转目标；冒险信号（BusAFw/BusBFw 及转发后的操作数、DiSrc 及修正前后的 store 数据、stall、flush、跳转目标）；寄存器堆和数据存储器写端口；I/O |

在 ModelSim 里也可以直接执行：

```
vsim -c -do "do sim/modelsim/regress.do pad"
vsim -do "do sim/modelsim/run_one.do build/pad/base9/isa/add"
```

镜像和期望轨迹要事先在 Linux 上生成到 `build/` 下，ModelSim 这边不需要 Python 和 RISC-V 工具链。回归脚本用 `-onfinish stop` 载入设计，仿真结束后读 `/tb_top/result_status`（1 PASS，2 FAIL）判定结果。

`.do` 和 `.bat` 只用 ASCII 字符：中文 Windows 上 Tcl 按 GBK 读脚本，UTF-8 中文后面紧跟的 `{`、`}`、`$` 可能被吞掉。
