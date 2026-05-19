@echo off
setlocal
cd /d "%~dp0\.."
powershell -NoProfile -ExecutionPolicy Bypass -File ".\windows\tools\netboot-harness.ps1" collect-latest -Config ".\windows\lab-10.73.json" -Serial d80c0b88 -Mac 88:a2:9e:4f:a9:b1 -PiIp 10.73.0.155 -Provider WinNFSd -InitVariant busybox-static
echo.
pause
