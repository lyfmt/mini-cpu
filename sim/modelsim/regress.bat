@echo off
rem ModelSim batch regression.
rem Usage: sim\modelsim\regress.bat [pad^|nopad]      (default: pad)
rem Needs vsim on PATH. Test images and expected traces must already be in
rem build\<variant>\ (generated on Linux). Log: build\modelsim\regress_<variant>.log
setlocal
cd /d "%~dp0..\.."
set VARIANT=%~1
if "%VARIANT%"=="" set VARIANT=pad
if not exist build\modelsim mkdir build\modelsim
vsim -c -l build/modelsim/regress_%VARIANT%.log -do "do sim/modelsim/regress.do %VARIANT%"
set RC=%ERRORLEVEL%
if "%RC%"=="0" (echo REGRESSION PASSED) else (echo REGRESSION FAILED, exit code %RC%)
exit /b %RC%
