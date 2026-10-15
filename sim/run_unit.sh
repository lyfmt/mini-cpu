#!/usr/bin/env bash
# RTL 单元测试，一条命令跑完：
#
#   sim/run_unit.sh
#
#   1. tb_qmul：模乘单元，4096 × 4096 种输入穷举，外加高位随机的 32 位输入抽查
#      （verilator --binary --timing；没有 verilator 时用 iverilog，要几分钟）；
#   2. tb_control：主控制器，opcode × funct3 × funct7 穷举对照译码表，HAS_QMUL = 1、0 各一次；
#   3. illegal：非法指令程序（tb/unit/illegal.S）在整个 CPU 上运行，HAS_QMUL = 1、0 各一次。
#      现场用 riscv64-elf-gcc 构建，用参考模型 model/iss.py 生成期望轨迹，再检查 STALLS。
#
# 生成物放在 build/unit/。全部通过时退出码为 0。
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
out=build/unit
mkdir -p "$out"
prefix=${RISCV_PREFIX:-riscv64-elf-}
fails=0

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; fails=$((fails + 1)); }

# 跑一个单元测试平台：输出里有 "UNIT PASS" 即通过
check_log() {   # 名字 日志
    if grep -q '^UNIT PASS' "$2" && ! grep -q '^UNIT FAIL' "$2"; then pass "$1"; else fail "$1 (see $2)"; fi
}

# ---------------------------------------------------------------- 1. qmul
if command -v verilator >/dev/null 2>&1; then
    if verilator --binary --timing -Wno-fatal -Irtl --top-module tb_qmul -Mdir "$out/obj_qmul" -o tb_qmul \
            tb/unit/tb_qmul.v rtl/qmul_unit.v > "$out/qmul_build.log" 2>&1; then
        "$out/obj_qmul/tb_qmul" > "$out/qmul.log" 2>&1
        check_log "tb_qmul (verilator)" "$out/qmul.log"
    else
        fail "tb_qmul: verilator build failed (see $out/qmul_build.log)"
    fi
else
    iverilog -g2001 -Irtl -s tb_qmul -o "$out/tb_qmul.vvp" tb/unit/tb_qmul.v rtl/qmul_unit.v &&
        vvp -n "$out/tb_qmul.vvp" > "$out/qmul.log" 2>&1
    check_log "tb_qmul (iverilog)" "$out/qmul.log"
fi
grep -E '^qmul ' "$out/qmul.log" 2>/dev/null | sed 's/^/      /'

# ---------------------------------------------------------------- 2. control
for q in 1 0; do
    iverilog -g2001 -Irtl -Ptb_control.HAS_QMUL=$q -s tb_control -o "$out/tb_control_q$q.vvp" \
        tb/unit/tb_control.v rtl/control.v &&
        vvp -n "$out/tb_control_q$q.vvp" > "$out/control_q$q.log" 2>&1
    check_log "tb_control HAS_QMUL=$q" "$out/control_q$q.log"
    grep -E '^control ' "$out/control_q$q.log" 2>/dev/null | sed 's/^/      /'
done

# ---------------------------------------------------------------- 3. illegal
src=tb/unit/illegal.S
d=$out/illegal
mkdir -p "$d/cpu" "$d/ref1" "$d/ref0"
cflags=(-march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -static -I sw/common -T sw/common/link.ld
        -Wl,--no-relax -Wl,--no-warn-rwx-segments)
build_img() {   # 目录 额外参数...
    local dir=$1; shift
    "${prefix}gcc" "${cflags[@]}" "$@" -o "$dir/prog.elf" "$src" &&
        python3 scripts/elf2hex.py "$dir/prog.elf" "$dir/imem.hex" "$dir/dmem.hex" > /dev/null &&
        "${prefix}objdump" -d "$dir/prog.elf" > "$dir/prog.dump"
}
if build_img "$d/cpu" && build_img "$d/ref1" -DREF && build_img "$d/ref0" -DREF -DNO_QMUL &&
   python3 model/iss.py --isa rv32i_qmul --imem "$d/ref1/imem.hex" --dmem "$d/ref1/dmem.hex" \
       --trace "$d/ref1/expect.trace" --check-uninit > "$d/ref1/iss.log" 2>&1 &&
   python3 model/iss.py --isa rv32i --imem "$d/ref0/imem.hex" --dmem "$d/ref0/dmem.hex" \
       --trace "$d/ref0/expect.trace" --check-uninit > "$d/ref0/iss.log" 2>&1; then
    nill=$(diff "$d/cpu/imem.hex" "$d/ref0/imem.hex" | grep -c '^<')
    for q in 1 0; do
        want_stalls=$q    # 唯一的 load-use 在 qmul 上，HAS_QMUL=0 时它是非法指令
        iverilog -g2001 -Ptb_top.HAS_QMUL=$q -s tb_top -o "$out/cpu_q$q.vvp" -f sim/files.f &&
            vvp -n "$out/cpu_q$q.vvp" +IMEM="$d/cpu/imem.hex" +DMEM="$d/cpu/dmem.hex" \
                +EXPECT="$d/ref$q/expect.trace" > "$d/cpu_q$q.log" 2>&1
        res=$(grep '^RESULT' "$d/cpu_q$q.log")
        if [[ $res == "RESULT: PASS"* && $res == *" stalls=$want_stalls "* ]]; then
            pass "illegal HAS_QMUL=$q ($nill words replaced by nop in the HAS_QMUL=0 reference; $res)"
        else
            fail "illegal HAS_QMUL=$q: expected PASS with stalls=$want_stalls, got: $res (see $d/cpu_q$q.log)"
        fi
    done
else
    fail "illegal: cannot build images or expected traces (see $d/*/iss.log)"
fi

echo
if [ $fails -eq 0 ]; then echo "run_unit: all passed"; exit 0; else echo "run_unit: $fails failed"; exit 1; fi
