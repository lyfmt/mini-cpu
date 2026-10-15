# Demo "custom instruction qmul" (design document section 9, demo table).
# Program: sw/tests/rv32i_qmul/demo/qmul.S, image: prebuilt/rv32i_qmul/demo/qmul (disassembly in prog.dump)
# Run from the repository root:
#     do sim/modelsim/demo/qmul.do
# or from cmd: sim\modelsim\run_demo.bat qmul
# Each cursor sits in the middle of the cycle named in its label; see start.do
# for the cycle numbering and wave_demo.do for the signals.

quietly set demo_name  qmul
quietly set demo_dir   prebuilt/rv32i_qmul/demo/qmul
quietly set demo_qmul  1
quietly set demo_range {16 22}
quietly set demo_marks {
    {18 {C18 qmul in EX: a=1234 b=2345, y=829}}
    {19 {C19 add x6,x5,x3 in EX: BusAFw=10, fwdA=829}}
    {20 {C20 RF writes x5=829}}
    {21 {C21 RF writes x6=1829}}
}
quietly set demo_notes {
    {custom instruction: qmul x5,x1,x2 at 0x40 ; add x6,x5,x3 at 0x44}
    {C18 QMUL: p=2893730 qhat=869 r=829 y=829, ALUctr=1001, EX result = 829 (one cycle)}
    {C19: BusAFw=10, fwdA = 829 from EX/M (m_aluout), EX result 1829}
    {C20/C21: RF x5 = 829 (0x33d), x6 = 1829 (0x725)}
}
do sim/modelsim/demo/start.do
