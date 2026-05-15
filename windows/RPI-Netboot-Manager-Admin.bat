@echo off
setlocal
cd /d "%~dp0"
net session >nul 2>&1
if not "%errorlevel%"=="0" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -Verb RunAs -FilePath '%~f0' -ArgumentList '%*'"
  exit /b
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\rpi-netboot-manager.ps1" %*
