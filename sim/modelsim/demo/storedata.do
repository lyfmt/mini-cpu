# Demo "store data" (design document section 9, demo table).
# Program: sw/tests/base9/demo/storedata.S, image: prebuilt/base9/demo/storedata (disassembly in prog.dump)
# Run from the repository root:
#     do sim/modelsim/demo/storedata.do
# or from cmd: sim\modelsim\run_demo.bat storedata
# Each cursor sits in the middle of the cycle named in its label; see start.do
# for the cycle numbering and wave_demo.do for the signals.

quietly set demo_name  storedata
quietly set demo_dir   prebuilt/base9/demo/storedata
quietly set demo_qmul  0
quietly set demo_range {18 28}
quietly set demo_marks {
    {20 {C20 sw in M, lw in WB: DiSrc=1, m_DataIn=0x13579bdf}}
    {25 {C25 sw in EX, add in WB: BusBFw=01, fwdB=0x300}}
    {26 {C26 sw in M: m_busB=0x300, DiSrc=0, DMem writes 0x300}}
}
quietly set demo_notes {
    {store data: lw x5 ; sw x5 (DiSrc) and add x6 ; nop ; sw x6 (EX forwarding)}
    {C20: m_busB = old x5 0x555, DiSrc=1, m_DataIn = 0x13579bdf, DMem 0x10014 <- 0x13579bdf}
    {C25: BusBFw=01, fwdB = 0x300 goes into EX/M}
    {C26: m_busB = 0x300, DiSrc=0, DMem 0x10018 <- 0x300}
}
do sim/modelsim/demo/start.do
