# Kyber NTT 评估程序与 qmul 测试

设计文档第七节"定制指令：为 Kyber 的模乘加速"的软件部分：NTT 参考实现、qmul 硬件算法的位级模型、两个版本的 NTT 汇编程序、qmul 的单指令和冒险测试、评估报告脚本。

## 文件

| 文件 | 作用 |
|---|---|
| `scripts/ntt_ref.py` | Kyber 正向 NTT 的 Python 参考实现（FIPS 203 算法 9）；按数学定义交叉验证；生成 `sw/ntt/ntt_data.S` |
| `scripts/check_barrett.py` | qmul 硬件算法（Barrett 约简）的位级模型 `qmul_model()`，对全部 4096 × 4096 种输入穷举验证 |
| `scripts/ntt_report.py` | 评估报告：两个 NTT 版本的周期数、退休指令数、CPI、停顿、冲刷、加速比及其分解 |
| `sw/ntt/ntt_body.S` | NTT 汇编主体，两个版本共用：循环结构、模加、模减、MARK 打点、与期望输出比较。唯一的差异点是宏 `MODMUL` |
| `sw/ntt/ntt_data.S` | 生成的数据：ζ 表、输入多项式、期望输出，全部在 `.data` 段。不要手改 |
| `sw/tests/rv32i/ntt/ntt_sw.S` | 软件模乘版：`MODMUL` 调用子程序 `modmul_sw`（jal 调用、jalr 返回；移位加法求积，移位减法取模） |
| `sw/tests/rv32i_qmul/ntt/ntt_qmul.S` | qmul 版：`MODMUL` 是一条 `qmul` |
| `sw/tests/rv32i_qmul/isa/qmul.S` | qmul 单指令测试 |
| `sw/tests/rv32i_qmul/hazard/qmul_*.S` | qmul 的冒险测试 |

两个 NTT 程序和普通测试一样由 `scripts/build.py` 发现和构建（suite 名为 `ntt`），都会构建出 pad 和 nopad 两个变体。`ntt_body.S` 和 `ntt_data.S` 不在 `sw/tests/` 下，由测试文件用相对路径 `#include` 进来。

## NTT 程序

算法与 `ntt_ref.py` 的 `ntt()` 逐行对应：len 从 128 减半到 2，每组取下一个 ζ，每次蝴蝶做一次模乘、一次模减、一次模加，7 层共 896 次蝴蝶。系数按 32 位字存放（CPU 只有 lw/sw），NTT 在 `ntt_poly` 上原地计算。

- 模加：`add`；`sltu` 判断和 < q；`addi −1` 变成掩码；`and q`；`sub`。5 条，无分支。
- 模减：`sub`；`slt` 判断差 < 0；取负变成掩码；`and q`；`add`。5 条，无分支。
- 软件模乘 `modmul_sw`：乘积循环每轮看乘数的最低位，用掩码决定是否累加被乘数，乘数变成 0 就停（最多 12 轮）；取模循环从 q·2¹¹ 开始，"够减就减"，共 12 轮。两个循环体里都用掩码代替分支，每轮只有一次回跳。要求两个操作数在 [0, q)。
- NTT 前后各写一次 MARK（1 和 2），测试平台打印计数器快照；`ntt_report.py` 取两次之差。
- 算完与 `ntt_expect` 逐项比较：全部相等写 FINISH 0；否则失败码为 k + 1（1..256），k 是第一处不等的系数下标。

存储器占用（两块各 4 KB）：

| | 代码（nopad / pad） | 数据 |
|---|---|---|
| ntt_sw | 340 B / 768 B | 2572 B（ζ 表 512 B、输入 1 KB、期望输出 1 KB、`LA` 用的地址常数 12 B） |
| ntt_qmul | 272 B / 580 B | 2572 B |

## 重新生成数据

```
python3 scripts/ntt_ref.py -o sw/ntt/ntt_data.S
```

不带 `-o` 只做自检。自检包括：17 是模 q 的 256 次本原单位根，ζ 表没有重复，蝴蝶数为 896；对全 0、单位脉冲、全 q−1、数据文件里的输入，以及 200 个随机多项式（`-n` 可改），比较 `ntt()` 与按数学定义算出的结果：输出的第 i 对 (f̂[2i], f̂[2i+1]) 应等于 f mod (X² − ζ^(2·BitRev7(i)+1))。结果：204 个多项式全部逐项相等。

输入多项式用 xorshift32 每次取 12 位、小于 q 的留下，种子固定，与 Python 版本无关，重新生成得到的文件不变。

## 运行

```
# 参考模型上跑：两个 NTT 版本、qmul 的全部测试，pad 和 nopad 两个变体
python3 scripts/run_tests.py --variant both --iss-only -k 'ntt_*' -k 'qmul*'

# 评估报告，只用参考模型
python3 scripts/ntt_report.py --iss-only

# 评估报告，在 CPU 上跑（需要 CPU 支持 rv32i 和 qmul）
python3 scripts/ntt_report.py [--variant nopad|pad] [--max-cycles N]
```

`ntt_report.py` 自己完成构建（不改写 `build/<variant>/tests.lst`），默认用 nopad 变体。

- **CPU 模式**：用 `run_tests.py` 的函数编译 CPU、运行 vvp，要求两个程序都 PASS（FINISH 0 且轨迹与参考模型一致），再从 `sim.log` 的两行 MARK 取 cycles、instret、stalls、flushes 的差值。输出对比表、加速比，并按 cycles = instret + stalls + 3 × flushes + other 把两个版本的周期差拆成"指令变少""停顿变少""冲刷变少"和剩余项。最后把硬件计数器和参考模型推算的值对照，不一致时列出来。
- **`--iss-only`**：退休指令数是参考模型的准确值；停顿、冲刷按第五节的规则从实际执行的指令流推算（load 后紧跟着用它的结果停 1 拍，store 的数据不算；每次跳转成立冲刷一次），周期按上式估算，表里标 `(est.)`。

参考模型上的结果（nopad，两次 MARK 之间，含第二个 MARK 宏本身的 3 条指令）：

| | ntt_sw | ntt_qmul | 比值 |
|---|---|---|---|
| 退休指令数 | 151966 | 16915 | 8.98 |
| 每次蝴蝶的指令数 | 169.6 | 18.9 | |
| 跳转成立次数（推算） | 21212 | 895 | |
| load-use 停顿（推算） | 0 | 0 | |
| 周期数（估算） | 215602 | 19600 | 11.00 |

按估算，省下的周期约 69% 来自指令变少，31% 来自冲刷变少。两个版本在窗口内都没有 load-use 停顿：蝴蝶里先连着读出 b 和 a，再做模乘，两次 load 的结果都隔一条才用到。

## check_barrett 的结论

```
python3 scripts/check_barrett.py
```

位级模型（RTL 的模乘单元按它实现）：

1. p = a × b，a、b 取 rs1、rs2 的低 12 位；
2. qhat = (p × 5039) >> 24，5039 = ⌊2²⁴ / 3329⌋；
3. r = p − qhat × 3329；
4. 结果 = r ≥ q ? r − q : r。

对全部 4096 × 4096 种输入穷举：

- 第 3 步的余数 r 全部落在 [0, 2q) 内（最小 0，最大 5683 < 6658），第 4 步最多减一次 q 足够；约 17.9% 的输入需要这次减法。
- 最终结果全部等于 (a·b) mod 3329。
- 中间量位宽：p 最大 16769025（24 位），p × 5039 最大 37 位，qhat 最大 5036（13 位），r 13 位。
- 三个乘法的操作数位宽都在 DSP48E1 的 25 × 18（有符号，即无符号 24 × 17）之内：

| 乘法 | 操作数位宽 |
|---|---|
| a × b | 12 × 12 |
| p × 5039 | 24 × 13 |
| qhat × 3329 | 13 × 12 |

设计文档第七节的说法全部验证通过。

## qmul 测试

期望值都按定义 (a·b) mod 3329 算出，写成常数，算式写在各文件头注释里。

| 测试 | 覆盖 |
|---|---|
| `isa/qmul` | 0 和 1；(q−1)² = 1；4095 × 4095（输入超出 [0, q)）；q 本身、q+1；只取低 12 位（rs1、rs2、两者高位非零，第 12 位置位）；无符号（0x800 × 0x7ff）；rd = x0；rd = rs1；rd = rs2；rs1 = rs2；rd = rs1 = rs2 |
| `hazard/qmul_dist1` | 相邻依赖：qmul → add（rs1）、qmul → sub（rs2）、qmul → qmul、ALU → qmul（rs1、rs2）、qmul → 分支比较 |
| `hazard/qmul_dist2` | 同上各组，中间隔一条无关指令 |
| `hazard/qmul_load_use` | load 紧跟 qmul（rs1、rs2、两个操作数），以及 load 后隔一条 |
| `hazard/qmul_store` | qmul 结果紧接着被 store；隔一条被 store；load → qmul → store 连在一起 |
| `hazard/qmul_flush` | beq 成立、jal、jalr 之后的 3 条错误路径指令都是 qmul：不写回，也不转发给目标处的指令；其中一条 qmul 的 rd 与 jal 的 rd 相同 |

`isa/qmul` 能区分以下错误实现（把参考模型的 qmul 换成错误版本后跑这个测试，都以非 0 失败码结束）：不截取低 12 位、按有符号数相乘、模数错、漏掉最后一次减 q。
