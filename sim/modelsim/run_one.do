# Run a single test. In the GUI the basic wave layout (wave.do) is loaded first.
#
# Run from the repository root:
#     do sim/modelsim/run_one.do <test-dir> [plusarg ...]
# e.g.
#     do sim/modelsim/run_one.do prebuilt/base9/isa/add
#     do sim/modelsim/run_one.do base9/hazard/load_use +PIPE
# From a shell (sim/modelsim/run_one.bat does the same):
#     vsim -do "do sim/modelsim/run_one.do prebuilt/base9/isa/add"
#     vsim -c -do "do sim/modelsim/run_one.do prebuilt/base9/isa/add; quit -f"
#
# <test-dir> holds imem.hex and dmem.hex; expect.trace is used when present.
# A test id such as base9/isa/add is looked up under prebuilt/.
# Up to four extra plusargs (+PIPE, +MAXCYCLES=n, ...) are passed through.
# The CPU trace is written to build/modelsim/run_one.trace.

onbreak {resume}

if {$argc < 1} {
    echo "usage: do sim/modelsim/run_one.do <test-dir> \[plusarg ...\]"
} else {
    quietly set run_dir [string trimright $1 "/"]
    if {![file isdirectory $run_dir] && [file isdirectory prebuilt/$run_dir]} {
        quietly set run_dir prebuilt/$run_dir
    }
    file mkdir build/modelsim
    quietly set run_args [list +IMEM=$run_dir/imem.hex +DMEM=$run_dir/dmem.hex +TRACE=build/modelsim/run_one.trace]
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
