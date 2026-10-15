# Common part of the demo scripts. sim/modelsim/demo/<name>.do sets the
# variables below and then runs "do sim/modelsim/demo/start.do":
#   demo_name   demo name; run products are build/modelsim/demo_<name>.*
#   demo_dir    image directory, e.g. prebuilt/base9/demo/loaduse
#   demo_qmul   1: also show the modular multiplier (QMUL group)
#   demo_range  {first last}: cycles to zoom to
#   demo_marks  list of {cycle label}: one cursor in the middle of each cycle
#   demo_notes  what to look for; shown as dividers on top of the wave window
#               and printed to the transcript
#
# This script compiles (compile.do), loads tb_top with the demo image and
# +PIPE (the transcript gets one pipeline line per cycle), adds the demo wave
# layout (wave_demo.do), runs to the end, then places the cursors and zooms.
#
# Cycle numbers are the testbench's: /tb_top/cyc in the wave, "PIPE <n>" in the
# transcript and the CYCLE counter all agree. The clock period is 10 ns and
# cycle N lasts from 25+10N ns to 35+10N ns (the rising edge at the end of
# cycle N is at 35+10N ns), so a cursor at 30+10N ns shows cycle N.

onbreak {resume}
quietly set demo_ok 0

proc demo_ns {cyc} {
    return [expr {30 + 10 * $cyc}]
}

if {![file exists $demo_dir/imem.hex]} {
    echo "demo: $demo_dir/imem.hex not found"
} else {
    catch {quit -sim}
    do sim/modelsim/compile.do
    if {$compile_ok} {
        vsim -t 1ps -onfinish stop -voptargs=+acc \
            -lib build/modelsim/work -wlf build/modelsim/demo_$demo_name.wlf \
            tb_top +IMEM=$demo_dir/imem.hex +DMEM=$demo_dir/dmem.hex \
            +EXPECT=$demo_dir/expect.trace +TRACE=build/modelsim/demo_$demo_name.trace +PIPE
        if {![batch_mode]} {
            do sim/modelsim/demo/wave_demo.do
        }
        run -all
        quietly set demo_ok 1
    }
}

if {$demo_ok && ![batch_mode]} {
    foreach demo_m $demo_marks {
        quietly set demo_t [demo_ns [lindex $demo_m 0]]
        if {[catch {wave cursor add -time ${demo_t}ns -name [lindex $demo_m 1] -lock 1}]} {
            catch {wave cursor add -time ${demo_t}ns}
        }
    }
    wave zoom range [expr {[demo_ns [lindex $demo_range 0]] - 5}]ns \
                    [expr {[demo_ns [lindex $demo_range 1]] + 5}]ns
}

if {$demo_ok} {
    echo "================================================================"
    echo "demo $demo_name ($demo_dir), key cycles [lindex $demo_range 0]..[lindex $demo_range 1]"
    foreach demo_n $demo_notes {
        echo "  $demo_n"
    }
    foreach demo_m $demo_marks {
        echo [format "  cursor at %d ns: %s" [demo_ns [lindex $demo_m 0]] [lindex $demo_m 1]]
    }
    echo "  cycle N = /tb_top/cyc = PIPE line N, shown from 25+10N ns to 35+10N ns"
    echo "  source and disassembly: $demo_dir/prog.dump"
    echo "================================================================"
}
