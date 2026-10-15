@echo off
rem Open one test in the ModelSim GUI with the basic wave layout.
rem Usage: sim\modelsim\run_one.bat <test-dir> [plusarg ...]
rem   e.g. sim\modelsim\run_one.bat build/pad/base9/isa/add +PIPE
setlocal
cd /d "%~dp0..\.."
if "%~1"=="" (echo usage: run_one.bat ^<test-dir^> [plusarg ...] & exit /b 2)
if not exist build\modelsim mkdir build\modelsim
vsim -l build/modelsim/run_one.log -do "do sim/modelsim/run_one.do %*"
