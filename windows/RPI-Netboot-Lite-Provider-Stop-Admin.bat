@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoExit -NoProfile -ExecutionPolicy Bypass -File \"%~dp0tools\lite-provider.ps1\" stop' -WorkingDirectory '%~dp0' -Verb RunAs"
