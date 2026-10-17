# mini-cpu demos in the Vivado simulator (xsim), for the evaluation.
#
# Usage, in the Vivado Tcl Console:
#     source D:/2/app/study/Vivado/my-repo/mini-cpu/vivado/demo.tcl
#     mini_cpu_demo loaduse
# Sourcing this file also sources create_project.tcl (opens the project, defines
# mini_cpu_set_test / mini_cpu_set_qmul) when that has not been done yet.
#
# Commands:
#     mini_cpu_demos                 list the demos and their key cycles
#     mini_cpu_demo <name>           select the demo's test (+PIPE), (re)launch the
#                                    behavioral simulation, run to the end, open a
#                                    wave window "demo_<name>" with the signal groups
#                                    below and one marker in the middle of each key cycle
#     mini_cpu_wave [<name>]         only build the wave window, for a simulation that is
#                                    already open (no name: no markers, QMUL group
#                                    included)
#     mini_cpu_run <test> [+PIPE]    any test from prebuilt/tests.lst (e.g.
#                                    base9/hazard/waw_mprio): select it, (re)launch the
#                                    simulation, build the wave window without markers
#     mini_cpu_mark <n> [<label>]    add a marker in the middle of cycle n
#     mini_cpu_cycle <n>             print the time window of cycle n
#
# Cycle numbering is the testbench's: /tb_top/cyc in the wave, "PIPE <n>" in the Tcl
# console and the CYCLE counter all agree. The clock period is 10 ns and cycle n lasts
# from 25+10n ns to 35+10n ns; markers sit at 30+10n ns. A signal's value at a marker is
# its value during that cycle (registers change at the rising edge at the end of it).
#
# Wave groups (xsim names the generate scope of the multiplier "g_qmul.u_qmul"):
#     1 Stages      pc / instruction / valid of IF..WB (valid = 0 is a bubble), EX result
#     2 Hazard      BusAFw, BusBFw, DiSrc, stall, flush, and load_use before the
#                   "flush wins" masking (hazard_unit.v)
#     3 Detect      the register numbers and control bits the hazard and forwarding
#                   units compare
#     4 Operands    busA/busB read in ID, fwdA/fwdB after forwarding, the two forwarding
#                   sources, branch condition, jump decision and target
#     5 Store data  m_busB (EX/M) and m_DataIn (after DiSrc)
#     6 Write ports register file write port, data memory write port
#     7 QMUL        multiplier inputs, intermediate values and output (qmul demo only)
#     8 Counters    CYCLE, INSTRET, STALLS, FLUSHES

set mini_cpu_demo_dir [file dirname [file normalize [info script]]]
if {[info procs mini_cpu_set_test] eq ""} {
    source [file join $mini_cpu_demo_dir create_project.tcl]
}

# name -> {test qmul marks notes [plusargs]}
#   marks: {cycle label} ...; notes: one divider line each, shown on top of the wave;
#   plusargs: passed to mini_cpu_set_test, default +PIPE
set mini_cpu_demo_table {
    pipeline {
        base9/demo/pipeline 0
        {
            {26 {C26 5 stages full: WB lui .. IF sltu}}
            {30 {C30 sw writes DMem 0x10024 <- 0x100}}
            {32 {C32 beq in ID reads x15 via RF bypass}}
            {35 {C35 jal in M: flush=1 target 0x84}}
            {36 {C36 ID/EX/M bubbles}}
        }
        {
            {pipeline: 9 base instructions at 0x58..0x80, no dependences, no stall}
            {C26..C32: all stages valid, RF writes x10..x15 one per cycle}
            {C32: beq (ID) reads x15 while lw (WB) writes it: RF internal bypass, BusAFw=00}
            {C35: jal in M -> flush; C36: ID/EX/M valid=0, IF pc=0x84}
        }
    }
    forward {
        base9/demo/forward 0
        {
            {18 {C18 BusAFw=10 fwdA=0x30 (A<-M)}}
            {20 {C20 RF x6=0x330}}
            {24 {C24 BusBFw=01 fwdB=0x30 (B<-WB)}}
            {26 {C26 RF x8=0x330}}
        }
        {
            {forward: add x5,x1,x2 ; add x6,x5,x3 (distance 1)  |  add x7,x1,x2 ; nop ; add x8,x3,x7 (distance 2)}
            {C18: EX=0x40, m_rd=5=ex_rs1 -> BusAFw=10, busA=0x555 (old) but fwdA=0x30, EX result 0x330}
            {C24: EX=0x58, wb_rd=7=ex_rs2 -> BusBFw=01, busB=0x777 (old) but fwdB=0x30, EX result 0x330}
        }
    }
    loaduse {
        base9/demo/loaduse 0
        {
            {16 {C16 lw in EX, add in ID: stall=1}}
            {17 {C17 PC/IF-ID held, EX bubble}}
            {18 {C18 BusAFw=01 fwdA=0x12345678}}
            {20 {C20 RF x6=0x12345679}}
        }
        {
            {load-use: lw x5,0(x4) at 0x38 ; add x6,x5,x1 at 0x3c}
            {C16: ex_MemRead=1, ex_rd=5 = id_rs1=5 -> stall=1}
            {C17: IF pc 0x40 and ID pc 0x3c unchanged, EX valid=0 (bubble)}
            {C18: add in EX, lw in WB: BusAFw=01, fwdA = loaded 0x12345678; C20 RF x6 = 0x12345679}
        }
    }
    storedata {
        base9/demo/storedata 0
        {
            {20 {C20 DiSrc=1 m_DataIn=0x13579bdf}}
            {25 {C25 sw in EX: BusBFw=01 fwdB=0x300}}
            {26 {C26 m_busB=0x300 DMem <- 0x300}}
        }
        {
            {store data: lw x5 ; sw x5,8(x4) (DiSrc)  |  add x6 ; nop ; sw x6,12(x4) (forwarded busB into EX/M)}
            {C20: sw in M, lw in WB: m_busB=0x555 (old), DiSrc=1, m_DataIn=0x13579bdf, no stall}
            {C25: BusBFw=01, fwdB=0x300 is latched into EX/M; C26: m_busB=0x300, DiSrc=0, DMem 0x10018 <- 0x300}
        }
    }
    flush {
        rv32i/demo/flush 0
        {
            {23 {C23 beq in M: flush=1 target 0x64}}
            {24 {C24 IF=0x64, ID/EX/M bubbles}}
            {27 {C27 jal in M: flush=1 target 0x74}}
            {28 {C28 RF x11=0x68 (link)}}
            {31 {C31 jalr in M: flush=1 target 0x84}}
            {32 {C32 RF x12=0x78 (link)}}
        }
        {
            {flush: beq taken (0x50), jal (0x64), jalr (0x74); each is decided in M}
            {flush cycle: m_redirect=1, PC <- m_target; next cycle ID/EX/M valid=0}
            {wrong-path ori x20/x21/x22 and sw never reach the write ports (RF we / DMem we)}
        }
    }
    flushprio {
        base9/hazard/flush_stall 0
        {
            {27 {C27 flush=1 load_use=1 stall=0}}
            {28 {C28 IF=0x70 target, bubbles}}
            {32 {C32 target add x20 retires}}
        }
        {
            {flush wins over stall: beq x0,x0 (0x60) ; lw x1 (0x64) ; add x2,x1,x1 (0x68) are wrong path}
            {C27: beq in M -> flush=1; lw in EX + add in ID -> load_use=1, but stall = load_use & !flush = 0}
            {C28: PC = 0x70 (not held), ID/EX/M bubbles; x1/x2 never written; C32 RF x20 = 1}
        }
    }
    ext {
        rv32i/demo/ext 0
        {
            {23 {C23 RF x5=0x100 (sll)}}
            {26 {C26 bne taken: flush target 0x68}}
            {30 {C30 blt taken: flush target 0x74}}
            {33 {C33 bge in EX: cond=0}}
            {34 {C34 bge in M: no flush}}
            {36 {C36 jalr flush 0x88, RF x10=0x1078}}
            {37 {C37 RF x11=0x80}}
        }
        {
            {extended: sll/srl/sra/srai x1=0x80000010 ; bne/blt/bge x3=-5 x4=3 ; auipc ; jalr}
            {C23..C26 RF: x5=0x100 x6=0x08000001 x7=0xf8000001 x8=0xffffffff}
            {C26 bne / C30 blt taken -> flush; C33 bge ex_cond=0 -> C34 m_Branch=1 m_cond=0, no flush}
            {C36: auipc x10 = 0x78+0x1000 = 0x1078; jalr flush to 0x88; C37 x11 = 0x80}
        }
    }
    qmul {
        rv32i_qmul/demo/qmul 1
        {
            {18 {C18 qmul in EX: y=829 in 1 cycle}}
            {19 {C19 add: BusAFw=10 fwdA=829}}
            {20 {C20 RF x5=829}}
            {21 {C21 RF x6=1829}}
        }
        {
            {custom instruction: qmul x5,x1,x2 (0x40, x1=1234 x2=2345) ; add x6,x5,x3 (0x44, x3=1000)}
            {C18: ALUctr=1001, p=2893730 qhat=869 r=829 y=829, EX result 829 (0x33d)}
            {C19: BusAFw=10, fwdA=0x33d from EX/M, EX result 1829 (0x725); C20/C21 RF x5=0x33d, x6=0x725}
        }
    }
    ntt {
        rv32i_qmul/ntt/ntt_qmul 1
        {
            {25 {C25 first qmul a2,s5,a1 in EX: B<-WB}}
            {26 {C26 sub t2,t1,a2: A<-WB B<-M}}
            {19616 {C19616 MARK 2 (NTT done)}}
        }
        {
            {qmul inside the real NTT butterfly (sw/ntt/ntt_body.S:70), 0x54 lw a1 ; 0x58 lw t1 ; 0x5c qmul a2,s5,a1 ; 0x60 sub t2,t1,a2}
            {C25: qmul in EX, b = a1 loaded 2 instr. earlier -> BusBFw=01; a=zeta 1729, b=974, y=2901}
            {C26: sub in EX: t1 from WB (A<-WB), a2 = qmul result from EX/M (B<-M); no stall anywhere}
            {cycle counts: Tcl console MARK lines (MARK 2 - MARK 1 = 19600 cycles; ntt_sw: 215602)}
        }
        {}
    }
}

proc mini_cpu_demo_get {name} {
    global mini_cpu_demo_table
    if {![dict exists $mini_cpu_demo_table $name]} {
        error "mini-cpu: no demo '$name'; demos: [dict keys $mini_cpu_demo_table]"
    }
    return [dict get $mini_cpu_demo_table $name]
}

proc mini_cpu_cycle_ns {n} {
    return [expr {30 + 10 * $n}]
}

proc mini_cpu_cycle {n} {
    puts [format "cycle %d: %d ns .. %d ns (marker at %d ns)" \
              $n [expr {25 + 10 * $n}] [expr {35 + 10 * $n}] [mini_cpu_cycle_ns $n]]
}

proc mini_cpu_mark {n {label ""}} {
    if {$label eq ""} {
        set label "C$n"
    }
    add_wave_marker -name $label [mini_cpu_cycle_ns $n] ns
}

proc mini_cpu_demos {} {
    global mini_cpu_demo_table
    dict for {name d} $mini_cpu_demo_table {
        set cycles {}
        foreach m [lindex $d 2] {
            lappend cycles C[lindex $m 0]
        }
        puts [format "  %-10s %-28s %s" $name [lindex $d 0] [join $cycles " "]]
    }
}

# Add one signal to group g: {label path radix}
proc mini_cpu_add {g label path {radix ""}} {
    if {$radix eq ""} {
        add_wave -into $g -name $label $path
    } else {
        add_wave -into $g -name $label -radix $radix $path
    }
}

proc mini_cpu_wave {{name ""}} {
    set C /tb_top/u_cpu/u_core
    if {$name eq ""} {
        set qmul  1
        set marks {}
        set notes {}
        set wname mini_cpu
    } else {
        set d     [mini_cpu_demo_get $name]
        set qmul  [lindex $d 1]
        set marks [lindex $d 2]
        set notes [lindex $d 3]
        set wname demo_$name
    }

    set w [create_wave_config $wname]
    foreach n $notes {
        add_wave_divider -into $w $n
    }
    add_wave -into $w -name cycle -radix unsigned /tb_top/cyc
    add_wave -into $w -name clk /tb_top/clk

    set g [add_wave_group -into $w {1 Stages}]
    mini_cpu_add $g {IF pc}     $C/if_pc       hex
    mini_cpu_add $g {IF inst}   $C/if_inst     hex
    mini_cpu_add $g {ID pc}     $C/id_pc       hex
    mini_cpu_add $g {ID inst}   $C/id_inst     hex
    mini_cpu_add $g {ID valid}  $C/id_valid
    mini_cpu_add $g {EX pc}     $C/ex_pc       hex
    mini_cpu_add $g {EX inst}   $C/ex_inst     hex
    mini_cpu_add $g {EX valid}  $C/ex_valid
    mini_cpu_add $g {EX result} $C/ex_result   hex
    mini_cpu_add $g {M pc}      $C/m_pc        hex
    mini_cpu_add $g {M inst}    $C/m_inst      hex
    mini_cpu_add $g {M valid}   $C/m_valid
    mini_cpu_add $g {WB pc}     $C/wb_pc       hex
    mini_cpu_add $g {WB inst}   $C/wb_inst     hex
    mini_cpu_add $g {WB valid}  $C/wb_valid

    set g [add_wave_group -into $w {2 Hazard}]
    mini_cpu_add $g BusAFw      $C/ex_BusAFw   bin
    mini_cpu_add $g BusBFw      $C/ex_BusBFw   bin
    mini_cpu_add $g DiSrc       $C/m_DiSrc
    mini_cpu_add $g stall       $C/stall
    mini_cpu_add $g flush       $C/flush
    mini_cpu_add $g {load_use (before flush mask)} $C/u_hzd/load_use

    set g [add_wave_group -into $w {3 Detect}]
    mini_cpu_add $g {ID rs1}     $C/id_rs1      unsigned
    mini_cpu_add $g {ID rs2}     $C/id_rs2      unsigned
    mini_cpu_add $g {ID UseRs1}  $C/id_UseRs1
    mini_cpu_add $g {ID UseRs2}  $C/id_UseRs2
    mini_cpu_add $g {ID MemWr}   $C/id_MemWr
    mini_cpu_add $g {EX rs1}     $C/ex_rs1      unsigned
    mini_cpu_add $g {EX rs2}     $C/ex_rs2      unsigned
    mini_cpu_add $g {EX rd}      $C/ex_rd       unsigned
    mini_cpu_add $g {EX MemRead} $C/ex_MemRead
    mini_cpu_add $g {M rd}       $C/m_rd        unsigned
    mini_cpu_add $g {M RegWr}    $C/m_RegWr
    mini_cpu_add $g {M MemRead}  $C/m_MemRead
    mini_cpu_add $g {WB rd}      $C/wb_rd       unsigned
    mini_cpu_add $g {WB RegWr}   $C/wb_RegWr

    set g [add_wave_group -into $w {4 Operands}]
    mini_cpu_add $g {busA (ID read)}  $C/ex_busA   hex
    mini_cpu_add $g fwdA              $C/ex_fwdA   hex
    mini_cpu_add $g {busB (ID read)}  $C/ex_busB   hex
    mini_cpu_add $g fwdB              $C/ex_fwdB   hex
    mini_cpu_add $g {m_aluout (src 10)} $C/m_aluout hex
    mini_cpu_add $g {wb_busW (src 01)}  $C/wb_busW  hex
    mini_cpu_add $g {EX cond}         $C/ex_cond
    mini_cpu_add $g {EX target}       $C/ex_target hex
    mini_cpu_add $g {M Branch}        $C/m_Branch
    mini_cpu_add $g {M cond}          $C/m_cond
    mini_cpu_add $g {M Jump}          $C/m_Jump
    mini_cpu_add $g {M redirect}      $C/m_redirect
    mini_cpu_add $g {M target}        $C/m_target  hex

    set g [add_wave_group -into $w {5 Store data}]
    mini_cpu_add $g {m_busB (EX/M)}      $C/m_busB   hex
    mini_cpu_add $g {m_DataIn (after DiSrc)} $C/m_DataIn hex

    set g [add_wave_group -into $w {6 Write ports}]
    mini_cpu_add $g {RF we}     $C/u_rf/we
    mini_cpu_add $g {RF wa}     $C/u_rf/wa    unsigned
    mini_cpu_add $g {RF wd}     $C/u_rf/wd    hex
    mini_cpu_add $g {DMem we}   /tb_top/u_cpu/u_dmem/we
    mini_cpu_add $g {DMem addr} $C/dbus_addr  hex
    mini_cpu_add $g {DMem wdata} /tb_top/u_cpu/u_dmem/wdata hex

    if {$qmul} {
        set Q $C/g_qmul.u_qmul
        set g [add_wave_group -into $w {7 QMUL}]
        mini_cpu_add $g ALUctr      $C/ex_ALUctr  bin
        mini_cpu_add $g {a (rs1)}   $C/ex_alu_a   unsigned
        mini_cpu_add $g {b (rs2)}   $C/ex_alu_b   unsigned
        mini_cpu_add $g p           $Q/p          unsigned
        mini_cpu_add $g qhat        $Q/qhat       unsigned
        mini_cpu_add $g r           $Q/r          unsigned
        mini_cpu_add $g y           $C/ex_qmul_y  unsigned
        mini_cpu_add $g {EX result} $C/ex_result  unsigned
        mini_cpu_add $g m_aluout    $C/m_aluout   unsigned
    }

    set g [add_wave_group -into $w {8 Counters}]
    mini_cpu_add $g CYCLE   /tb_top/u_cpu/u_io/cycle_cnt   unsigned
    mini_cpu_add $g INSTRET /tb_top/u_cpu/u_io/instret_cnt unsigned
    mini_cpu_add $g STALLS  /tb_top/u_cpu/u_io/stall_cnt   unsigned
    mini_cpu_add $g FLUSHES /tb_top/u_cpu/u_io/flush_cnt   unsigned

    foreach m $marks {
        mini_cpu_mark [lindex $m 0] [lindex $m 1]
    }

    if {$name ne ""} {
        puts "================================================================"
        puts "demo $name ([lindex [mini_cpu_demo_get $name] 0])"
        foreach n $notes {
            puts "  $n"
        }
        foreach m $marks {
            puts [format "  marker %4d ns  %s" [mini_cpu_cycle_ns [lindex $m 0]] [lindex $m 1]]
        }
        puts "  cycle n = /tb_top/cyc = PIPE line n, from 25+10n ns to 35+10n ns"
        puts "================================================================"
    }
    return $w
}

proc mini_cpu_relaunch {} {
    if {[current_sim -quiet] ne ""} {
        catch {close_sim -force}
    }
    launch_simulation
}

proc mini_cpu_demo {name} {
    set d [mini_cpu_demo_get $name]
    # optional 5th field: plusargs (default +PIPE; the long NTT run goes without it)
    set extra +PIPE
    if {[llength $d] > 4} {
        set extra [lindex $d 4]
    }
    mini_cpu_set_test [lindex $d 0] {*}$extra
    mini_cpu_relaunch
    mini_cpu_wave $name
}

# Any test from prebuilt/tests.lst, e.g. "mini_cpu_run base9/hazard/waw_mprio +PIPE":
# select it, (re)launch, build the wave window without markers.
proc mini_cpu_run {test args} {
    mini_cpu_set_test $test {*}$args
    mini_cpu_relaunch
    mini_cpu_wave
}

puts "mini-cpu: demo commands loaded. Demos (key cycles):"
mini_cpu_demos
puts "mini-cpu: run e.g. 'mini_cpu_demo loaduse'"
