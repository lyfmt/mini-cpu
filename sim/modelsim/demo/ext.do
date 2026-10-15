# Demo "extended instructions" (design document section 9, demo table).
# Program: sw/tests/rv32i/demo/ext.S, image: prebuilt/rv32i/demo/ext (disassembly in prog.dump)
# Run from the repository root:
#     do sim/modelsim/demo/ext.do
# or from cmd: sim\modelsim\run_demo.bat ext
# Each cursor sits in the middle of the cycle named in its label; see start.do
# for the cycle numbering and wave_demo.do for the signals.

quietly set demo_name  ext
quietly set demo_dir   prebuilt/rv32i/demo/ext
quietly set demo_qmul  0
quietly set demo_range {20 38}
quietly set demo_marks {
    {23 {C23..C26 RF writes sll/srl/sra/srai results x5..x8}}
    {26 {C26 bne taken in M: flush, target 0x68}}
    {30 {C30 blt taken in M: flush, target 0x74}}
    {33 {C33 bge in EX: cond=0, not taken (no flush at C34)}}
    {36 {C36 jalr in M: flush, target 0x88; RF x10 = 0x1078 (auipc)}}
}
quietly set demo_notes {
    {extended instructions: shifts, bne/blt/bge, auipc, jalr}
    {C23..C26 RF: x5=0x100 x6=0x08000001 x7=0xf8000001 x8=0xffffffff}
    {C26 bne / C30 blt taken (flush); C33 bge cond=0, falls through}
    {C36 auipc x10 = 0x78+0x1000 = 0x1078; jalr flush to 0x88; C37 x11 = 0x80}
}
do sim/modelsim/demo/start.do
