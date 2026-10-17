@echo off
rem Full regression with the Vivado simulator (xsim) in batch mode, no ModelSim needed.
rem Compiles rtl/ + tb/tb_top.v once, then runs every test in prebuilt/tests.lst
rem (or the list given as the argument) against its expected trace.
rem Usage (cmd, from anywhere):
rem     vivado\regress_xsim.bat                      all 175 tests
rem     vivado\regress_xsim.bat my_list.lst          one test id per line, e.g. prebuilt/base9/hazard/load_use
rem                                                  (path relative to the repository root)
rem Needs the Vivado bin directory on PATH; if xvlog is not found, VIVADO_BIN below is used.
rem Output: build\xsim_regress\regress.txt (one line per test: status, id, RESULT line),
rem         build\xsim_regress\logs\<n>.log (full xsim log of test n).
setlocal enabledelayedexpansion
set VIVADO_BIN=D:\2\app\study\Vivado\2025.2\Vivado\bin
where xvlog >nul 2>&1 || set "PATH=%VIVADO_BIN%;%PATH%"

cd /d "%~dp0.."
set ROOT=%CD%
set ROOTF=%ROOT:\=/%
set LIST=%~1
if "%LIST%"=="" set LIST=prebuilt\tests.lst
set OUT=build\xsim_regress
if not exist %OUT%\logs mkdir %OUT%\logs
if exist %OUT%\regress.txt del %OUT%\regress.txt
cd /d %OUT%

echo ==== compile
set SRC=
for %%f in (control extender alu branch_cmp qmul_unit regfile forward_unit hazard_unit imem dmem io_regs cpu_core cpu_top) do set SRC=!SRC! "%ROOT%\rtl\%%f.v"
call xvlog -i "%ROOT%\rtl" !SRC! "%ROOT%\tb\tb_top.v" -log xvlog.log >nul
if errorlevel 1 (echo xvlog failed, see %OUT%\xvlog.log & exit /b 1)
call xelab -s tb_regress tb_top -log xelab.log >nul
if errorlevel 1 (echo xelab failed, see %OUT%\xelab.log & exit /b 1)
> run.tcl echo run all

set N=0
set NPASS=0
set NFAIL=0
for /f "usebackq eol=# tokens=*" %%t in ("%ROOT%\%LIST%") do call :one %%t
echo.
echo regress %LIST%: !N! tests, !NPASS! PASS, !NFAIL! FAIL
echo per-test results: %OUT%\regress.txt
if !NFAIL! neq 0 (
    echo REGRESSION FAILED
    findstr /b FAIL regress.txt
    exit /b 1
)
echo REGRESSION PASSED
exit /b 0

:one
set T=%~1
set TB=%T:/=\%
set /a N+=1
rem xsim.bat splits arguments at '=', so the plusargs go through an options file
> cur.opt echo -testplusarg IMEM=%ROOTF%/%T%/imem.hex -testplusarg DMEM=%ROOTF%/%T%/dmem.hex
if exist "%ROOT%\%TB%\expect.trace" >> cur.opt echo -testplusarg EXPECT=%ROOTF%/%T%/expect.trace
call xsim tb_regress -tclbatch run.tcl -log logs\!N!.log -f cur.opt >nul 2>&1
set RES=no RESULT line
for /f "tokens=*" %%r in ('findstr /b /c:"RESULT:" logs\!N!.log') do set RES=%%r
echo !RES! | findstr /b /c:"RESULT: PASS" >nul
if errorlevel 1 (
    set /a NFAIL+=1
    >> regress.txt echo FAIL %T%  !RES!  [logs\!N!.log]
    echo FAIL %T%  !RES!
) else (
    set /a NPASS+=1
    >> regress.txt echo PASS %T%  !RES!
    echo PASS %T%
)
exit /b 0
