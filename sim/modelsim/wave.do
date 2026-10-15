# Basic wave layout, grouped by pipeline stage (loaded by run_one.do in the GUI).
#   - IF .. WB : PC, instruction and valid bit of every stage (a bubble has valid = 0)
#                EX also shows the branch condition (compare unit) and the jump target
#                (PC + imm, or forwarded rs1 + imm for jalr, LSB cleared)
#   - Hazard   : BusAFw/BusBFw with the forwarded operands, DiSrc with the store data
#                before (m_busB) and after (m_DataIn) correction, stall, flush and
#                the jump target (flush = M-stage redirect)
#   - RegFile write / DMem write / IO : where results land
# All paths are hierarchical names inside tb_top; see rtl/README.md.

onerror {resume}
quietly set C /tb_top/u_cpu/u_core

add wave -noupdate -label clk /tb_top/clk
add wave -noupdate -label rst /tb_top/rst

add wave -noupdate -expand -group IF -radix hexadecimal -label pc   $C/if_pc
add wave -noupdate -expand -group IF -radix hexadecimal -label inst $C/if_inst

add wave -noupdate -expand -group ID -radix hexadecimal -label pc    $C/id_pc
add wave -noupdate -expand -group ID -radix hexadecimal -label inst  $C/id_inst
add wave -noupdate -expand -group ID                    -label valid $C/id_valid

add wave -noupdate -expand -group EX -radix hexadecimal -label pc    $C/ex_pc
add wave -noupdate -expand -group EX -radix hexadecimal -label inst  $C/ex_inst
add wave -noupdate -expand -group EX                    -label valid $C/ex_valid
add wave -noupdate -expand -group EX                    -label cond   $C/ex_cond
add wave -noupdate -expand -group EX -radix hexadecimal -label target $C/ex_target

add wave -noupdate -expand -group M  -radix hexadecimal -label pc    $C/m_pc
add wave -noupdate -expand -group M  -radix hexadecimal -label inst  $C/m_inst
add wave -noupdate -expand -group M                     -label valid $C/m_valid

add wave -noupdate -expand -group WB -radix hexadecimal -label pc    $C/wb_pc
add wave -noupdate -expand -group WB -radix hexadecimal -label inst  $C/wb_inst
add wave -noupdate -expand -group WB                    -label valid $C/wb_valid

add wave -noupdate -expand -group Hazard -radix binary      -label BusAFw    $C/ex_BusAFw
add wave -noupdate -expand -group Hazard -radix hexadecimal -label fwdA      $C/ex_fwdA
add wave -noupdate -expand -group Hazard -radix binary      -label BusBFw    $C/ex_BusBFw
add wave -noupdate -expand -group Hazard -radix hexadecimal -label fwdB      $C/ex_fwdB
add wave -noupdate -expand -group Hazard                    -label DiSrc     $C/m_DiSrc
add wave -noupdate -expand -group Hazard -radix hexadecimal -label m_busB    $C/m_busB
add wave -noupdate -expand -group Hazard -radix hexadecimal -label m_DataIn  $C/m_DataIn
add wave -noupdate -expand -group Hazard                    -label stall     $C/stall
add wave -noupdate -expand -group Hazard                    -label flush     $C/flush
add wave -noupdate -expand -group Hazard -radix hexadecimal -label target    $C/m_target

add wave -noupdate -expand -group {RegFile write}                    -label we $C/u_rf/we
add wave -noupdate -expand -group {RegFile write} -radix unsigned    -label wa $C/u_rf/wa
add wave -noupdate -expand -group {RegFile write} -radix hexadecimal -label wd $C/u_rf/wd

add wave -noupdate -expand -group {DMem write}                    -label we        /tb_top/u_cpu/u_dmem/we
add wave -noupdate -expand -group {DMem write} -radix hexadecimal -label byte_addr $C/dbus_addr
add wave -noupdate -expand -group {DMem write} -radix hexadecimal -label word_addr /tb_top/u_cpu/u_dmem/addr
add wave -noupdate -expand -group {DMem write} -radix hexadecimal -label wdata     /tb_top/u_cpu/u_dmem/wdata

add wave -noupdate -group IO                    -label finish   /tb_top/u_cpu/finish
add wave -noupdate -group IO                    -label mark     /tb_top/u_cpu/mark
add wave -noupdate -group IO -radix hexadecimal -label io_wdata /tb_top/u_cpu/io_wdata
add wave -noupdate -group IO -radix unsigned    -label CYCLE    /tb_top/u_cpu/u_io/cycle_cnt
add wave -noupdate -group IO -radix unsigned    -label INSTRET  /tb_top/u_cpu/u_io/instret_cnt

TreeUpdate [SetDefaultTree]
configure wave -namecolwidth 150
configure wave -valuecolwidth 90
configure wave -signalnamewidth 1
configure wave -timelineunits ns
update
