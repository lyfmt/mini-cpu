# Compile RTL + testbench (file list: sim/files.f) into build/modelsim/work.
# Run from the repository root:
#     do sim/modelsim/compile.do
# regress.do and run_one.do call this script; afterwards $compile_ok is 1 on success.
# The library is referenced by path (no vmap), so no modelsim.ini is written.

quietly set compile_ok 0
file mkdir build/modelsim
if {![file exists build/modelsim/work/_info]} {
    vlib build/modelsim/work
}
if {[catch {vlog -quiet -work build/modelsim/work -f sim/files.f} compile_msg]} {
    echo "compile.do: vlog failed: $compile_msg"
} else {
    quietly set compile_ok 1
}
