# Vivado non-project synthesis of cpu_top (design document section 9, "synthesis check").
#
# Run from the repository root (syn/run_syn.bat does this for both configurations):
#     vivado -mode batch -source syn/synth.tcl -tclargs qmul
#     vivado -mode batch -source syn/synth.tcl -tclargs noqmul
#
# Argument: configuration
#     qmul    -generic HAS_QMUL=1 (modular multiplier present)
#     noqmul  -generic HAS_QMUL=0 (modular multiplier removed)
# Part xc7z020clg400-2, top cpu_top, clock constraint syn/clock.xdc (10 ns).
#
# To keep synthesis from optimizing the CPU away, the memories are initialized
# with a real program: IMEM_INIT / DMEM_INIT point at the committed image of the
# qmul NTT program, prebuilt/rv32i_qmul/ntt/ntt_qmul/{imem,dmem}.hex (regenerate
# with "make prebuilt" on Linux). Both configurations use the same image so that
# the only difference between them is the modular multiplier. cpu_top's outputs
# finish, mark and io_wdata (store data on the I/O bus) give the data path a load.
#
# Output in syn/out/<config>/:
#     timing_summary.rpt   report_timing_summary
#     utilization.rpt      report_utilization (LUT, LUTRAM, FF, DSP, BRAM)
#     utilization_hier.rpt report_utilization -hierarchical (per module, incl. u_qmul)
#     drc.rpt              report_drc (MDRV-1 = multiple driver nets, among others)
#     summary.txt          WNS, Fmax, LUT/LUTRAM/FF/DSP/BRAM, latch and multi-driver counts
#     post_synth.dcp       checkpoint
# The Vivado log is written by the caller (run_syn.bat: syn/out/<config>/vivado.log).
# In the Vivado GUI Tcl console (fresh session, one configuration):
#     cd <repo>; set argv qmul; source syn/synth.tcl
# Errors are raised with "error" (batch mode then exits with a non-zero code).

set part xc7z020clg400-2
set top  cpu_top
set image_dir prebuilt/rv32i_qmul/ntt/ntt_qmul

if {[llength $argv] < 1} {
    error "usage: vivado -mode batch -source syn/synth.tcl -tclargs qmul|noqmul"
}
set cfg [lindex $argv 0]
switch -- $cfg {
    qmul    { set has_qmul 1 }
    noqmul  { set has_qmul 0 }
    default { error "synth.tcl: unknown configuration '$cfg' (qmul or noqmul)" }
}

set out syn/out/$cfg
file mkdir $out

set imem [file normalize $image_dir/imem.hex]
set dmem [file normalize $image_dir/dmem.hex]
foreach f [list $imem $dmem] {
    if {![file exists $f]} {
        error "synth.tcl: $f not found"
    }
}

# RTL only (no testbench); defines.vh is found through -include_dirs
foreach f [lsort [glob rtl/*.v]] {
    read_verilog $f
}
read_xdc syn/clock.xdc

synth_design -top $top -part $part -include_dirs rtl \
    -generic HAS_QMUL=$has_qmul \
    -generic IMEM_INIT=\"$imem\" \
    -generic DMEM_INIT=\"$dmem\"

write_checkpoint -force $out/post_synth.dcp
report_timing_summary -file $out/timing_summary.rpt
report_utilization -file $out/utilization.rpt
report_utilization -hierarchical -file $out/utilization_hier.rpt
report_drc -name drc_syn -file $out/drc.rpt

# ---- summary -------------------------------------------------------------

proc util_value {text label} {
    # first number (the "Used" column) after "| <label> |"; the label may end in '*'
    set re "\\|\\s*$label\\*?\\s*\\|\\s*(\\d+)"
    if {[regexp $re $text -> v]} {
        return $v
    }
    return n/a
}

set util [report_utilization -return_string]
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set period [get_property PERIOD [get_clocks clk]]
if {$wns eq ""} {
    set fmax n/a
} else {
    set fmax [format "%.1f" [expr {1000.0 / ($period - $wns)}]]
}
set n_latch [llength [all_latches]]
set n_mdrv n/a
catch {
    set n_mdrv [llength [lsearch -all -glob [get_drc_violations -quiet -name drc_syn] MDRV-1*]]
}

set lines [list \
    "config          $cfg (HAS_QMUL=$has_qmul), part $part, top $top" \
    "image           $image_dir" \
    "clock period    $period ns" \
    "WNS (setup)     $wns ns" \
    "Fmax            $fmax MHz   (= 1000 / (period - WNS), post-synthesis estimate)" \
    "Slice LUTs      [util_value $util {Slice LUTs}]" \
    "  LUT as Logic  [util_value $util {LUT as Logic}]" \
    "  LUT as Memory [util_value $util {LUT as Memory}]   (LUTRAM)" \
    "Slice Registers [util_value $util {Slice Registers}]" \
    "DSPs            [util_value $util {DSPs}]" \
    "Block RAM Tile  [util_value $util {Block RAM Tile}]" \
    "latches         $n_latch   (all_latches; must be 0)" \
    "MDRV-1 (DRC)    $n_mdrv   (multiple driver nets; must be 0)"]

set fh [open $out/summary.txt w]
foreach l $lines {
    puts $fh $l
}
close $fh
puts "================================================================"
foreach l $lines {
    puts $l
}
puts "reports: $out/"
puts "================================================================"
