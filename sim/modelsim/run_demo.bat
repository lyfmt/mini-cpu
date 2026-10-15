@echo off
rem Open one demo in the ModelSim GUI: compile, load the demo image from
rem prebuilt/, add the demo wave layout, run to the end, zoom to the key cycles.
rem Usage: sim\modelsim\run_demo.bat <name>
rem   <name>: pipeline forward loaduse storedata flush ext qmul
setlocal
cd /d "%~dp0..\.."
if "%~1"=="" (echo usage: run_demo.bat ^<pipeline^|forward^|loaduse^|storedata^|flush^|ext^|qmul^> & exit /b 2)
if not exist sim\modelsim\demo\%~1.do (echo run_demo.bat: no demo named %~1 & exit /b 2)
if not exist build\modelsim mkdir build\modelsim
vsim -l build/modelsim/demo_%~1.log -do "do sim/modelsim/demo/%~1.do"
