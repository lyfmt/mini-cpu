# mini-cpu Vivado GUI project: behavioral simulation (xsim) + synthesis.
#
# Usage: in the Vivado Tcl Console
#     source D:/2/app/study/Vivado/my-repo/mini-cpu/vivado/create_project.tcl
# The first time it creates vivado/mini_cpu/mini_cpu.xpr. Sourcing it again opens the
# existing project and (re)defines the two helper commands below (they live only in
# the current Vivado session).
#
# Helper commands:
#     mini_cpu_set_test <test id or dir> [+PIPE] [+MAXCYCLES=n]
#         Choose the test for simulation (an id under prebuilt/, e.g. base9/demo/pipeline,
#         rv32i_qmul/ntt/ntt_qmul; see prebuilt/tests.lst). Then re-run
#         Run Simulation -> Run Behavioral Simulation.
#     mini_cpu_set_qmul 1|0
#         1 = with modular multiplier (default), 0 = without. Applies to synthesis and
#         simulation. Then Reset Runs and Run Synthesis again.
#
# Part xc7z020clg400-2, synthesis top cpu_top, simulation top tb_top, clock syn/clock.xdc
# (10 ns). Memory init for synthesis is the same as syn/synth.tcl:
# prebuilt/rv32i_qmul/ntt/ntt_qmul/{imem,dmem}.hex. Source files are referenced in place
# (not copied), so edits in rtl/ show up in the project directly.

set mini_cpu_repo  [file normalize [file join [file dirname [file normalize [info script]]] ..]]
set mini_cpu_proj  [file join $mini_cpu_repo vivado mini_cpu]
set mini_cpu_image [file join $mini_cpu_repo prebuilt rv32i_qmul ntt ntt_qmul]

if {[regexp {\s} $mini_cpu_repo]} {
    error "repository path '$mini_cpu_repo' contains spaces; move it to a path without spaces or Chinese characters"
}

# ---- choose the simulation test -------------------------------------------------
proc mini_cpu_set_test {id args} {
    global mini_cpu_repo
    set dir [string trimright $id "/"]
    if {![file isdirectory $dir]} {
        set dir [file join $mini_cpu_repo prebuilt $dir]
    }
    set dir [file normalize $dir]
    if {![file exists $dir/imem.hex] || ![file exists $dir/dmem.hex]} {
        error "mini_cpu_set_test: no imem.hex / dmem.hex in $dir (test ids are listed in prebuilt/tests.lst)"
    }
    set opts "-testplusarg IMEM=$dir/imem.hex -testplusarg DMEM=$dir/dmem.hex"
    if {[file exists $dir/expect.trace]} {
        append opts " -testplusarg EXPECT=$dir/expect.trace"
    }
    foreach a $args {
        append opts " -testplusarg [string trimleft $a +]"
    }
    set_property -name {xsim.simulate.xsim.more_options} -value $opts -objects [get_filesets sim_1]
    puts "mini-cpu: simulation test = $dir"
    puts "mini-cpu: re-run Run Simulation -> Run Behavioral Simulation to use it"
}

# ---- with / without the modular multiplier ------------------------------------
proc mini_cpu_set_qmul {on} {
    global mini_cpu_image
    if {$on ne "0" && $on ne "1"} {
        error "mini_cpu_set_qmul: argument must be 1 or 0"
    }
    set imem [file normalize $mini_cpu_image/imem.hex]
    set dmem [file normalize $mini_cpu_image/dmem.hex]
    set_property generic "HAS_QMUL=$on IMEM_INIT=\"$imem\" DMEM_INIT=\"$dmem\"" [get_filesets sources_1]
    set_property generic "HAS_QMUL=$on" [get_filesets sim_1]
    puts "mini-cpu: HAS_QMUL = $on (if already synthesized: Reset Runs, then Run Synthesis)"
}

# ---- create or open the project -----------------------------------------------
set mini_cpu_xpr [file join $mini_cpu_proj mini_cpu.xpr]

if {[current_project -quiet] ne ""} {
    puts "mini-cpu: project [current_project] is already open; helper commands defined"
} elseif {[file exists $mini_cpu_xpr]} {
    open_project $mini_cpu_xpr
    puts "mini-cpu: opened $mini_cpu_xpr"
} else {
    create_project mini_cpu $mini_cpu_proj -part xc7z020clg400-2
    set_property target_language Verilog [current_project]
    set_property simulator_language Verilog [current_project]

    # design sources: rtl/*.v and defines.vh
    add_files -norecurse -fileset sources_1 [lsort [glob $mini_cpu_repo/rtl/*.v]]
    add_files -norecurse -fileset sources_1 $mini_cpu_repo/rtl/defines.vh
    set_property file_type {Verilog Header} [get_files defines.vh]
    set_property include_dirs [list $mini_cpu_repo/rtl] [get_filesets sources_1]
    set_property top cpu_top [get_filesets sources_1]

    # constraints
    add_files -norecurse -fileset constrs_1 $mini_cpu_repo/syn/clock.xdc

    # simulation sources: testbench
    add_files -norecurse -fileset sim_1 $mini_cpu_repo/tb/tb_top.v
    set_property include_dirs [list $mini_cpu_repo/rtl] [get_filesets sim_1]
    set_property top tb_top [get_filesets sim_1]
    set_property top_lib xil_defaultlib [get_filesets sim_1]

    # run until the testbench calls $finish; log every signal so any internal
    # signal can be dragged into the wave window after the run
    set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]
    set_property -name {xsim.simulate.log_all_signals} -value {true} -objects [get_filesets sim_1]

    update_compile_order -fileset sources_1
    update_compile_order -fileset sim_1

    mini_cpu_set_qmul 1
    mini_cpu_set_test base9/demo/pipeline

    puts "mini-cpu: created $mini_cpu_xpr"
}
