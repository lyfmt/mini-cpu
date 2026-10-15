# prebuilt/ — 生成物，不要手改

这里是 ModelSim 回归、ModelSim 演示和 Vivado 综合在 Windows 上直接使用的程序镜像，随仓库提交，
所以 Windows 上不需要 Python、RISC-V 工具链和 `build/`。

- `<isa>/<suite>/<name>/`：`imem.hex`、`dmem.hex`（`$readmemh` 镜像，各 1024 行）、`expect.trace`（参考模型的期望轨迹）；
  `demo` 和 `ntt` 另有 `prog.dump`（反汇编，看波形时对照 PC）。
- `tests.lst`：每行一个测试目录（相对仓库根），ModelSim 回归 `sim/modelsim/regress.do` 读它。
- 内容：nopad 变体的全部手写测试（isa、hazard、perf、prog、ntt、demo）加每层种子 1～30 的随机测试。

源码（`sw/`、`scripts/gen_random.py`、`model/`）改了以后，在 Linux 上重新生成并提交：

```
make prebuilt
```

它构建镜像、清空并重写本目录（本文件除外），然后用 iverilog 只从本目录读文件跑一遍 `tests.lst` 里的全部测试。
