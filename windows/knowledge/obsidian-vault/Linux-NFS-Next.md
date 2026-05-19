# Linux NFS Next

## Goal

Serve the same RPi4 rootfs from a real Linux NFS server and prove whether Windows NFS provider compatibility is the blocker.

## Expected Network

- Windows DHCP/TFTP: `10.73.0.10`
- Linux NFS helper: `10.73.0.20`
- RPi4: `10.73.0.155`

## Windows Preparation

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\tools\linux-nfs-provider.ps1 prepare -Config .\windows\lab-10.73.json -Serial d80c0b88 -LinuxServerIp 10.73.0.20
```

Bundle:

```text
D:\tools\rpi-netboot\linux-nfs-provider
```

## Test Rule

After Linux export is ready, the user should only need to unplug and replug RPi4 power.
