# Wave layout of the demos (loaded by start.do). Three groups, as in the
# design document (section 9, "demo in ModelSim"):
#   Stages      : PC, instruction and valid bit of IF .. WB (a bubble has valid = 0),
#                 plus the EX result (ALU or modular multiplier)
#   Hazard      : BusAFw, BusBFw, DiSrc, stall, flush; below them the values they
#                 select (forwarded operands, store data before/after DiSrc, jump target)
#   Write ports : register file write port and data memory write port
#   QMUL        : only when demo_qmul is 1
# On top: the testbench cycle number and one divider per line of demo_notes.
# All paths are hierarchical names inside tb_top; see rtl/README.md.

onerror {resume}
quietly set C /tb_top/u_cpu/u_core

foreach demo_n $demo_notes {
    add wave -noupdate -divider $demo_n
}
add wave -noupdate -radix unsigned -label cycle /tb_top/cyc
add wave -noupdate -label clk /tb_top/clk

add wave -noupdate -expand -group Stages -radix hexadecimal -label {IF pc}     $C/if_pc
add wave -noupdate -expand -group Stages -radix hexadecimal -label {IF inst}   $C/if_inst
add wave -noupdate -expand -group Stages -radix hexadecimal -label {ID pc}     $C/id_pc
add wave -noupdate -expand -group Stages -radix hexadecimal -label {ID inst}   $C/id_inst
add wave -noupdate -expand -group Stages                    -label {ID valid}  $C/id_valid
add wave -noupdate -expand -group Stages -radix hexadecimal -label {EX pc}     $C/ex_pc
add wave -noupdate -expand -group Stages -radix hexadecimal -label {EX inst}   $C/ex_inst
add wave -noupdate -expand -group Stages                    -label {EX valid}  $C/ex_valid
add wave -noupdate -expand -group Stages -radix hexadecimal -label {EX result} $C/ex_result
add wave -noupdate -expand -group Stages -radix hexadecimal -label {M pc}      $C/m_pc
add wave -noupdate -expand -group Stages -radix hexadecimal -label {M inst}    $C/m_inst
add wave -noupdate -expand -group Stages                    -label {M valid}   $C/m_valid
add wave -noupdate -expand -group Stages -radix hexadecimal -label {WB pc}     $C/wb_pc
add wave -noupdate -expand -group Stages -radix hexadecimal -label {WB inst}   $C/wb_inst
add wave -noupdate -expand -group Stages                    -label {WB valid}  $C/wb_valid

add wave -noupdate -expand -group Hazard -radix binary      -label BusAFw     $C/ex_BusAFw
add wave -noupdate -expand -group Hazard -radix binary      -label BusBFw     $C/ex_BusBFw
add wave -noupdate -expand -group Hazard                    -label DiSrc      $C/m_DiSrc
add wave -noupdate -expand -group Hazard                    -label stall      $C/stall
add wave -noupdate -expand -group Hazard                    -label flush      $C/flush
add wave -noupdate -expand -group Hazard -radix hexadecimal -label fwdA       $C/ex_fwdA
add wave -noupdate -expand -group Hazard -radix hexadecimal -label fwdB       $C/ex_fwdB
add wave -noupdate -expand -group Hazard -radix hexadecimal -label m_busB     $C/m_busB
add wave -noupdate -expand -group Hazard -radix hexadecimal -label m_DataIn   $C/m_DataIn
add wave -noupdate -expand -group Hazard                    -label {EX cond}  $C/ex_cond
add wave -noupdate -expand -group Hazard -radix hexadecimal -label {M target} $C/m_target

add wave -noupdate -expand -group {Write ports}                    -label {RF we}        $C/u_rf/we
add wave -noupdate -expand -group {Write ports} -radix unsigned    -label {RF wa}        $C/u_rf/wa
add wave -noupdate -expand -group {Write ports} -radix hexadecimal -label {RF wd}        $C/u_rf/wd
add wave -noupdate -expand -group {Write ports}                    -label {DMem we}      /tb_top/u_cpu/u_dmem/we
add wave -noupdate -expand -group {Write ports} -radix hexadecimal -label {DMem addr}    $C/dbus_addr
add wave -noupdate -expand -group {Write ports} -radix hexadecimal -label {DMem wdata}   /tb_top/u_cpu/u_dmem/wdata

if {$demo_qmul} {
    add wave -noupdate -expand -group QMUL -radix unsigned -label {a (rs1)} $C/ex_alu_a
    add wave -noupdate -expand -group QMUL -radix unsigned -label {b (rs2)} $C/ex_alu_b
    add wave -noupdate -expand -group QMUL -radix unsigned -label p         $C/g_qmul/u_qmul/p
    add wave -noupdate -expand -group QMUL -radix unsigned -label qhat      $C/g_qmul/u_qmul/qhat
    add wave -noupdate -expand -group QMUL -radix unsigned -label r         $C/g_qmul/u_qmul/r
    add wave -noupdate -expand -group QMUL -radix unsigned -label y         $C/ex_qmul_y
    add wave -noupdate -expand -group QMUL -radix binary   -label ALUctr    $C/ex_ALUctr
    add wave -noupdate -expand -group QMUL -radix unsigned -label {EX result} $C/ex_result
    add wave -noupdate -expand -group QMUL -radix unsigned -label {m_aluout} $C/m_aluout
}

TreeUpdate [SetDefaultTree]
configure wave -namecolwidth 200
configure wave -valuecolwidth 90
configure wave -signalnamewidth 1
configure wave -timelineunits ns
update
