@echo off
setlocal
set "GODOT=%GODOT_PATH%"
if not defined GODOT set "GODOT=%~dp0.runtime\godot\Godot_v4.7.2-stable_win64.exe"
if not defined GODOT_PATH if not exist "%GODOT%" (
  call "%~dp0Setup.cmd"
  if errorlevel 1 exit /b 1
)
if not exist "%GODOT%" (
  echo Godot was not found at "%GODOT%".
  echo Run Setup.cmd or set GODOT_PATH to an existing Godot executable.
  exit /b 1
)
start "" /wait "%GODOT%" --headless --editor --path "%~dp0." --import
if errorlevel 1 exit /b 1
start "" "%GODOT%" --path "%~dp0." %*
