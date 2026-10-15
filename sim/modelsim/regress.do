# Batch regression in ModelSim.
#
# Run from the repository root:
#     vsim -c -do "do sim/modelsim/regress.do pad"
# or use sim/modelsim/regress.bat [pad|nopad].
#
# Argument 1: image variant, "pad" (default) or "nopad".
# Reads build/<variant>/tests.lst (one test directory per line, relative to the
# repository root), runs every test with +IMEM/+DMEM (+EXPECT when expect.trace
# exists), and prints a PASS/FAIL summary. The summary is also written to
# build/modelsim/regress_<variant>.txt.
# The images and expected traces must have been generated on Linux beforehand;
# this script needs neither Python nor the RISC-V toolchain.
#
# The verdict of each test is read back from /tb_top/result_status
# (1 = PASS, 2 = FAIL), which is why the design is loaded with -onfinish stop.
# In batch mode the script exits with code 0 if everything passed, 1 otherwise,
# 2 on setup errors.

onbreak {resume}

quietly set regress_variant pad
if {$argc >= 1} {
    quietly set regress_variant $1
}

proc regress_exit {code} {
    if {[batch_mode]} {
        quit -f -code $code
    }
}

# Returns {status cycles}; status is PASS, FAIL or ERROR.
proc regress_one {t} {
    set plusargs [list +IMEM=$t/imem.hex +DMEM=$t/dmem.hex +TRACE=$t/cpu_msim.trace]
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

proc regress_main {variant} {
    set lst build/$variant/tests.lst
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
    set summary [format "regress %s: %d tests, %d PASS, %d FAIL" $variant $total $npass $nfail]

    set fh [open build/modelsim/regress_$variant.txt w]
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
    echo "(per-test list: build/modelsim/regress_$variant.txt)"
    echo "================================================================"

    if {$nfail > 0 || $total == 0} {
        return 1
    }
    return 0
}

quietly set regress_rc 2
if {![file exists build/$regress_variant/tests.lst]} {
    echo "regress: build/$regress_variant/tests.lst not found; build the test images on Linux first"
} else {
    do sim/modelsim/compile.do
    if {$compile_ok} {
        quietly set regress_rc [regress_main $regress_variant]
    }
}
regress_exit $regress_rc
