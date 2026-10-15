# mini-cpu 顶层入口，用法见 README.md。
#
#   make stage1      阶段 1：base9 测试，pad 变体（带空指令），跑 CPU
#   make stage2      阶段 2：base9 测试，nopad 变体（去掉空指令），跑 CPU
#   make iss-check   全部测试、两个变体，只在参考模型上跑（不需要 RTL）
#   make images      只构建镜像和期望轨迹（给 ModelSim 用），不跑仿真
#   make unit-test   参考模型和脚本的单元测试
#   make clean       删除 build/
#
# 可以加参数，例如：make stage1 ARGS="-k add --pipe"、make images ISA=base9 VARIANT=pad

PYTHON  ?= python3
JOBS    ?= $(shell nproc 2>/dev/null || echo 4)
ISA     ?= rv32i_qmul
VARIANT ?= both
ARGS    ?=

RUN = $(PYTHON) scripts/run_tests.py -j $(JOBS)

.PHONY: help stage1 stage2 stage3 stage4 stage5 iss-check images unit-test clean

help:
	@sed -n '3,12p' Makefile

stage1:
	$(RUN) --isa base9 --variant pad $(ARGS)

stage2:
	$(RUN) --isa base9 --variant nopad $(ARGS)

# 后续阶段的入口：测试写好之后在这里接上
stage3 stage4 stage5:
	@echo "make $@: not implemented yet" >&2; exit 1

iss-check:
	$(RUN) --isa rv32i_qmul --variant both --iss-only $(ARGS)

images:
	$(PYTHON) scripts/build.py -j $(JOBS) --isa $(ISA) --variant $(VARIANT) $(ARGS)

unit-test:
	$(PYTHON) -m unittest discover -s model -p 'test_*.py'
	$(PYTHON) -m unittest discover -s scripts -p 'test_*.py'

clean:
	rm -rf build
