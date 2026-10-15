#!/usr/bin/env bash
# 用 iverilog 快速跑单个测试。
#
#   sim/run_one.sh <测试目录> [plusargs ...]
#
# 测试目录里要有 imem.hex、dmem.hex；有 expect.trace 时自动在线比对。
# CPU 轨迹写到 <测试目录>/cpu.trace。其余参数原样传给 vvp，例如 +PIPE、+MAXCYCLES=1000。
# 例：sim/run_one.sh build/pad/base9/basic/add +PIPE
# 退出码：PASS 为 0，否则为 1。
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "usage: $0 <test-dir> [plusargs ...]" >&2
    exit 2
fi

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

dir=${1%/}
shift

vvp_file=build/sim/run_one.vvp
mkdir -p build/sim

# 只在源文件比上次编译结果新时重新编译
need=0
if [ ! -f "$vvp_file" ]; then
    need=1
else
    for f in sim/files.f rtl/*.v rtl/*.vh tb/*.v; do
        if [ "$f" -nt "$vvp_file" ]; then need=1; break; fi
    done
fi
if [ $need -eq 1 ]; then
    iverilog -g2001 -s tb_top -o "$vvp_file" -f sim/files.f
fi

args=("+IMEM=$dir/imem.hex" "+DMEM=$dir/dmem.hex" "+TRACE=$dir/cpu.trace")
if [ -f "$dir/expect.trace" ]; then
    args+=("+EXPECT=$dir/expect.trace")
fi

log=$(mktemp)
trap 'rm -f "$log"' EXIT
vvp -n "$vvp_file" "${args[@]}" "$@" | tee "$log"
grep -q '^RESULT: PASS' "$log"
