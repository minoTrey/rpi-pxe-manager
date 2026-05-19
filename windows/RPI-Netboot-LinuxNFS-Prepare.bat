@echo off
setlocal
cd /d "%~dp0\.."
powershell -NoProfile -ExecutionPolicy Bypass -File ".\windows\tools\linux-nfs-provider.ps1" prepare -Config ".\windows\lab-10.73.json" -Serial d80c0b88 -Mac 88:a2:9e:4f:a9:b1 -PiIp 10.73.0.155 -LinuxServerIp 10.73.0.20
echo.
pause
