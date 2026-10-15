# Batch regression in ModelSim.
#
# Run from the repository root:
#     vsim -c -do "do sim/modelsim/regress.do"
# or use sim/modelsim/regress.bat.
#
# Argument 1 (optional): test list, default prebuilt/tests.lst.
# The list has one test directory per line (relative to the repository root).
# Every test is run with +IMEM/+DMEM (+EXPECT when expect.trace exists) and a
# PASS/FAIL summary is printed. The images in prebuilt/ are committed to the
# repository, so this script needs neither Python nor the RISC-V toolchain.
# Run products (work library, wlf, summary) go to build/modelsim/; the summary
# is written to build/modelsim/regress.txt.
#
# The verdict of each test is read back from /tb_top/result_status
# (1 = PASS, 2 = FAIL), which is why the design is loaded with -onfinish stop.
# In batch mode the script exits with code 0 if everything passed, 1 otherwise,
# 2 on setup errors.

onbreak {resume}

quietly set regress_list prebuilt/tests.lst
if {$argc >= 1} {
    quietly set regress_list $1
}

proc regress_exit {code} {
    if {[batch_mode]} {
        quit -f -code $code
    }
}

# Returns {status cycles}; status is PASS, FAIL or ERROR.
proc regress_one {t} {
    set plusargs [list +IMEM=$t/imem.hex +DMEM=$t/dmem.hex]
    if {[file exists $t/expect.trace]} {
        lappend plusargs +EXPECT=$t/expect.trace
    }
    if {[catch {eval vsim -quiet -t 1ps -onfinish stop -voptargs=+acc \
                     -lib build/modelsim/work -wlf build/modelsim/regress.wlf \
                     tb_top $plusargs} msg]} {
        echo "regress: cannot load $t: $msg"
        return [list ERROR 0]
    }
    set st 0
    set cy 0
    if {[catch {
        run -all
        set st [examine -radix unsigned /tb_top/result_status]
        set cy [examine -radix unsigned /tb_top/hw_cycles]
    } msg]} {
        echo "regress: error while running $t: $msg"
    }
    catch {quit -sim}
    regexp {(\d+)\s*$} $st -> st
    regexp {(\d+)\s*$} $cy -> cy
    if {$st eq "1"} {
        return [list PASS $cy]
    }
    return [list FAIL $cy]
}

proc regress_main {lst} {
    set tests {}
    set fh [open $lst r]
    while {[gets $fh line] >= 0} {
        set line [string trim $line]
        if {$line eq "" || [string index $line 0] eq "#"} {
            continue
        }
        lappend tests [string trimright $line "/"]
    }
    close $fh

    catch {quit -sim}

    set npass 0
    set nfail 0
    set report {}
    foreach t $tests {
        echo "======== $t"
        set r [regress_one $t]
        set status [lindex $r 0]
        set cycles [lindex $r 1]
        if {$status eq "PASS"} {
            incr npass
        } else {
            incr nfail
        }
        lappend report [format "%-4s %8s  %s" $status $cycles $t]
    }

    set total [llength $tests]
    set summary [format "regress %s: %d tests, %d PASS, %d FAIL" $lst $total $npass $nfail]

    set fh [open build/modelsim/regress.txt w]
    foreach line $report {
        puts $fh $line
    }
    puts $fh $summary
    close $fh

    echo "================================================================"
    foreach line $report {
        if {[string match "PASS*" $line]} {
            continue
        }
        echo $line
    }
    echo $summary
    echo "(per-test list: build/modelsim/regress.txt)"
    echo "================================================================"

    if {$nfail > 0 || $total == 0} {
        return 1
    }
    return 0
}

quietly set regress_rc 2
if {![file exists $regress_list]} {
    echo "regress: $regress_list not found"
} else {
    do sim/modelsim/compile.do
    if {$compile_ok} {
        quietly set regress_rc [regress_main $regress_list]
    }
}
regress_exit $regress_rc
