# Demo "basic pipeline" (design document section 9, demo table).
# Program: sw/tests/base9/demo/pipeline.S, image: prebuilt/base9/demo/pipeline (disassembly in prog.dump)
# Run from the repository root:
#     do sim/modelsim/demo/pipeline.do
# or from cmd: sim\modelsim\run_demo.bat pipeline
# Each cursor sits in the middle of the cycle named in its label; see start.do
# for the cycle numbering and wave_demo.do for the signals.

quietly set demo_name  pipeline
quietly set demo_dir   prebuilt/base9/demo/pipeline
quietly set demo_qmul  0
quietly set demo_range {24 37}
quietly set demo_marks {
    {26 {C26 five valid instrs: WB lui, M ori, EX add, ID slt, IF sltu}}
    {30 {C30 WB retires one per cycle (C26..C32: lui ori add slt sltu sw lw)}}
    {35 {C35 jal (0x80) in M: flush=1, target 0x84}}
    {36 {C36 ID/EX/M bubbles (valid=0)}}
}
quietly set demo_notes {
    {pipeline: 9 base instructions 0x58..0x80, no forwarding, no stall}
    {C26-C35: all 5 stages valid, RF we=1 each cycle with x10..x15 results}
    {C30: sw writes 0x100 to 0x10024 (DMem we=1); C32: beq reads lw result via RF bypass (BusAFw=00)}
    {C35: jal in M -> flush, C36 three bubbles}
}
do sim/modelsim/demo/start.do
