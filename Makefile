# mini-cpu 顶层入口，用法见 README.md。
#
#   make stage1      阶段 1：base9 测试，pad 变体（带空指令），跑 CPU
#   make stage2      阶段 2：base9 测试，nopad 变体，加 200 个 base9 随机测试
#   make stage3      阶段 3：rv32i（含 base9）测试，nopad，加 500 个 rv32i 随机测试
#   make stage4      阶段 4：rv32i_qmul（含前两层）测试，nopad，加 500 个 rv32i_qmul
#                    随机测试；有 scripts/ntt_report.py 时再跑 NTT 报告
#   make random      只跑随机测试：make random ISA=rv32i N=5000 SEED=1000
#   make iss-check   全部手写测试（两个变体）加每层 30 个随机测试，只在参考模型上跑
#   make images      只构建镜像和期望轨迹（给 ModelSim 用）：所选测试加每层 30 个
#                    固定种子（1..30）的随机测试，写进 build/<变体>/tests.lst
#   make rand-stats  统计随机测试里各类指令和冒险组合的出现次数
#   make unit-test   参考模型和脚本的单元测试
#   make clean       删除 build/
#
# 可以加参数，例如：make stage2 ARGS="--suite hazard -C 6"、make images ISA=base9 VARIANT=pad

PYTHON  ?= python3
JOBS    ?= $(shell nproc 2>/dev/null || echo 4)
ISA     ?= rv32i_qmul
VARIANT ?= both
N       ?= 1000
SEED    ?= 1
ARGS    ?=

RUN = $(PYTHON) scripts/run_tests.py -j $(JOBS)
IMAGE_RANDOM = --random 30 --seed 1 --random-all-isas

.PHONY: help stage1 stage2 stage3 stage4 stage5 random iss-check images rand-stats unit-test clean

help:
	@sed -n '3,18p' Makefile

stage1:
	$(RUN) --isa base9 --variant pad $(ARGS)

stage2:
	$(RUN) --isa base9 --variant nopad --random 200 --seed 1 $(ARGS)

stage3:
	$(RUN) --isa rv32i --variant nopad --random 500 --seed 1 $(ARGS)

stage4:
	$(RUN) --isa rv32i_qmul --variant nopad --random 500 --seed 1 $(ARGS)
	@if [ -f scripts/ntt_report.py ]; then \
		echo "$(PYTHON) scripts/ntt_report.py"; $(PYTHON) scripts/ntt_report.py; \
	else \
		echo "scripts/ntt_report.py not found, skipping the NTT report"; \
	fi

# 阶段 5 是 ModelSim 演示和 Vivado 综合，在 Windows 上进行
stage5:
	@echo "make stage5: not implemented yet" >&2; exit 1

random:
	$(RUN) --isa $(ISA) --variant nopad --suite rand --random $(N) --seed $(SEED) $(ARGS)

iss-check:
	$(RUN) --isa rv32i_qmul --variant both --iss-only $(IMAGE_RANDOM) $(ARGS)

images:
	$(PYTHON) scripts/build.py -j $(JOBS) --isa $(ISA) --variant $(VARIANT) $(IMAGE_RANDOM) $(ARGS)

rand-stats:
	$(PYTHON) scripts/rand_stats.py -j $(JOBS) --isa $(ISA) --count $(N) --seed $(SEED)

unit-test:
	$(PYTHON) -m unittest discover -s model -p 'test_*.py'
	$(PYTHON) -m unittest discover -s scripts -p 'test_*.py'

clean:
	rm -rf build
