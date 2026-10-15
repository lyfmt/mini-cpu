# Demo "forwarding" (design document section 9, demo table).
# Program: sw/tests/base9/demo/forward.S, image: prebuilt/base9/demo/forward (disassembly in prog.dump)
# Run from the repository root:
#     do sim/modelsim/demo/forward.do
# or from cmd: sim\modelsim\run_demo.bat forward
# Each cursor sits in the middle of the cycle named in its label; see start.do
# for the cycle numbering and wave_demo.do for the signals.

quietly set demo_name  forward
quietly set demo_dir   prebuilt/base9/demo/forward
quietly set demo_qmul  0
quietly set demo_range {16 26}
quietly set demo_marks {
    {18 {C18 add x6,x5,x3 in EX: BusAFw=10, fwdA=0x30 from M}}
    {24 {C24 add x8,x3,x7 in EX: BusBFw=01, fwdB=0x30 from WB}}
}
quietly set demo_notes {
    {forward: adjacent dependence (EX/M, 10) and distance-2 dependence (WB, 01)}
    {C18: BusAFw=10, fwdA = 0x30 (new x5, old value was 0x555), EX result 0x330}
    {C24: BusBFw=01, fwdB = 0x30 (new x7, old value was 0x777), EX result 0x330}
    {C20 / C26: RF writes x6 = 0x330 / x8 = 0x330}
}
do sim/modelsim/demo/start.do
