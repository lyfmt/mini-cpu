@echo off
rem ModelSim batch regression over prebuilt/tests.lst (committed images).
rem Usage: sim\modelsim\regress.bat [test-list]      (default: prebuilt/tests.lst)
rem Needs vsim on PATH. Log: build\modelsim\regress.log,
rem per-test list: build\modelsim\regress.txt
setlocal
cd /d "%~dp0..\.."
set LIST=%~1
if "%LIST%"=="" set LIST=prebuilt/tests.lst
if not exist build\modelsim mkdir build\modelsim
vsim -c -l build/modelsim/regress.log -do "do sim/modelsim/regress.do %LIST%"
set RC=%ERRORLEVEL%
if "%RC%"=="0" (echo REGRESSION PASSED) else (echo REGRESSION FAILED, exit code %RC%)
exit /b %RC%
