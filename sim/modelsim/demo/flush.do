# Demo "flush" (design document section 9, demo table).
# Program: sw/tests/rv32i/demo/flush.S, image: prebuilt/rv32i/demo/flush (disassembly in prog.dump)
# Run from the repository root:
#     do sim/modelsim/demo/flush.do
# or from cmd: sim\modelsim\run_demo.bat flush
# Each cursor sits in the middle of the cycle named in its label; see start.do
# for the cycle numbering and wave_demo.do for the signals.

quietly set demo_name  flush
quietly set demo_dir   prebuilt/rv32i/demo/flush
quietly set demo_qmul  0
quietly set demo_range {21 37}
quietly set demo_marks {
    {23 {C23 beq (0x50) in M: flush=1, target 0x64}}
    {24 {C24 IF=0x64, ID/EX/M bubbles}}
    {27 {C27 jal (0x64) in M: flush=1, target 0x74}}
    {31 {C31 jalr (0x74) in M: flush=1, target 0x84}}
}
quietly set demo_notes {
    {flush: beq taken, jal, jalr; each redirects from M and flushes IF/ID, ID/EX, EX/M}
    {C23/C27/C31: flush=1, M target = next IF pc; next cycle ID/EX/M valid=0}
    {wrong-path ori x20/x21/x22 and sw never reach the write ports}
    {C28: RF x11 = 0x68 (jal link); C32: RF x12 = 0x78 (jalr link)}
}
do sim/modelsim/demo/start.do
