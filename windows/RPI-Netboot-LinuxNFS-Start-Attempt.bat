@echo off
setlocal
cd /d "%~dp0\.."
echo This switches D:\tftp\d80c0b88\cmdline.txt to Linux NFS server 10.73.0.20.
echo Run this only after the Linux VM NFS export is ready.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File ".\windows\tools\linux-nfs-provider.ps1" start-attempt -Config ".\windows\lab-10.73.json" -Serial d80c0b88 -Mac 88:a2:9e:4f:a9:b1 -PiIp 10.73.0.155 -LinuxServerIp 10.73.0.20
echo.
pause
