# Run a single test. In the GUI the basic wave layout (wave.do) is loaded first.
#
# Run from the repository root:
#     do sim/modelsim/run_one.do <test-dir> [plusarg ...]
# e.g.
#     do sim/modelsim/run_one.do build/pad/base9/basic/add
#     do sim/modelsim/run_one.do build/pad/base9/basic/add +PIPE
# From a shell (sim/modelsim/run_one.bat does the same):
#     vsim -do "do sim/modelsim/run_one.do build/pad/base9/basic/add"
#     vsim -c -do "do sim/modelsim/run_one.do build/pad/base9/basic/add; quit -f"
#
# <test-dir> holds imem.hex and dmem.hex; expect.trace is used when present.
# Up to four extra plusargs (+PIPE, +MAXCYCLES=n, ...) are passed through.
# The CPU trace is written to <test-dir>/cpu_msim.trace.

onbreak {resume}

if {$argc < 1} {
    echo "usage: do sim/modelsim/run_one.do <test-dir> \[plusarg ...\]"
} else {
    quietly set run_dir [string trimright $1 "/"]
    quietly set run_args [list +IMEM=$run_dir/imem.hex +DMEM=$run_dir/dmem.hex +TRACE=$run_dir/cpu_msim.trace]
    if {[file exists $run_dir/expect.trace]} {
        lappend run_args +EXPECT=$run_dir/expect.trace
    }
    if {$argc >= 2} { lappend run_args $2 }
    if {$argc >= 3} { lappend run_args $3 }
    if {$argc >= 4} { lappend run_args $4 }
    if {$argc >= 5} { lappend run_args $5 }

    catch {quit -sim}
    do sim/modelsim/compile.do
    if {$compile_ok} {
        eval vsim -t 1ps -onfinish stop -voptargs=+acc \
            -lib build/modelsim/work -wlf build/modelsim/run_one.wlf \
            tb_top $run_args
        if {![batch_mode]} {
            do sim/modelsim/wave.do
        }
        run -all
        if {![batch_mode]} {
            wave zoom full
        }
    }
}
