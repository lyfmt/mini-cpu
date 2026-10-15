# Demo "load-use" (design document section 9, demo table).
# Program: sw/tests/base9/demo/loaduse.S, image: prebuilt/base9/demo/loaduse (disassembly in prog.dump)
# Run from the repository root:
#     do sim/modelsim/demo/loaduse.do
# or from cmd: sim\modelsim\run_demo.bat loaduse
# Each cursor sits in the middle of the cycle named in its label; see start.do
# for the cycle numbering and wave_demo.do for the signals.

quietly set demo_name  loaduse
quietly set demo_dir   prebuilt/base9/demo/loaduse
quietly set demo_qmul  0
quietly set demo_range {14 21}
quietly set demo_marks {
    {16 {C16 lw in EX, add in ID: stall=1}}
    {17 {C17 IF/ID held (IF 0x40, ID 0x3c), EX bubble}}
    {18 {C18 add in EX: BusAFw=01, fwdA=0x12345678 from WB}}
    {20 {C20 RF writes x6=0x12345679}}
}
quietly set demo_notes {
    {load-use: lw x5,0(x4) at 0x38 ; add x6,x5,x1 at 0x3c}
    {C16: stall=1; C17: IF pc and ID pc unchanged, EX valid=0 (bubble)}
    {C18: BusAFw=01, fwdA = loaded value 0x12345678}
    {C20: RF wa=6 wd=0x12345679}
}
do sim/modelsim/demo/start.do
