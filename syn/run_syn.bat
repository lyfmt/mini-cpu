@echo off
rem Vivado synthesis of cpu_top, with and without the modular multiplier.
rem Usage: syn\run_syn.bat [qmul^|noqmul]      (default: both)
rem Needs vivado on PATH (e.g. run settings64.bat of the Vivado install first).
rem Reports: syn\out\<config>\ (summary.txt, timing_summary.rpt, utilization.rpt, ...)
rem Log:     syn\out\<config>\vivado.log; lines about latches, multiple drivers,
rem          $readmem and critical warnings are copied to syn\out\<config>\log_check.txt
setlocal
cd /d "%~dp0.."
set CONFIGS=%~1
if "%CONFIGS%"=="" set CONFIGS=qmul noqmul
set RC=0
for %%c in (%CONFIGS%) do call :one %%c
echo.
for %%c in (%CONFIGS%) do (
    echo ==== syn\out\%%c\summary.txt
    if exist syn\out\%%c\summary.txt (type syn\out\%%c\summary.txt) else (echo missing)
    echo ==== syn\out\%%c\log_check.txt
    if exist syn\out\%%c\log_check.txt type syn\out\%%c\log_check.txt
)
exit /b %RC%

:one
if not exist syn\out\%1 mkdir syn\out\%1
call vivado -mode batch -nojournal -log syn/out/%1/vivado.log -source syn/synth.tcl -tclargs %1
if errorlevel 1 set RC=1
findstr /i /c:"latch" /c:"multi-driven" /c:"multiple driver" /c:"readmem" /c:"CRITICAL WARNING" syn\out\%1\vivado.log > syn\out\%1\log_check.txt
exit /b 0
