# haneWIN NFS A/B Test

Last updated: 2026-05-19 13:55 KST

## Purpose

haneWIN was tested only as a diagnostic A/B provider. It is not the preferred production path because it is trialware and the latest tests show protocol compatibility problems with Raspberry Pi NFS root boot.

Windows DHCP/TFTP stayed on `RpiBootServiceLite`; only the NFS provider changed.

## Network

| Item | Value |
| --- | --- |
| Windows server | `10.73.0.10` |
| Test RPi4 | `10.73.0.155` |
| Test RPi4 MAC | `88:a2:9e:4f:a9:b1` |
| Serial | `d80c0b88` |
| Export alias | `/rpi` |
| Export target | `D:\rootfs` |
| Client path | `10.73.0.10:/rpi/d80c0b88` |

## Portable Mode

Service mode needed administrator-controlled files under `C:\Program Files\nfsd`, so the test was converted to portable mode.

Portable files:

```text
D:\tools\rpi-netboot\hanewin-portable\nfsd.exe
D:\tools\rpi-netboot\hanewin-portable\pmapd.exe
```

Portable log:

```text
D:\logs\hanewin-portable.stdout.log
```

## Commands

Start diagnostic attempt:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\tools\hanewin-nfs-provider.ps1 start-attempt -Config .\windows\lab-10.73.json -Serial d80c0b88 -Mac 88:a2:9e:4f:a9:b1 -PiIp 10.73.0.155 -Mode Portable
```

Finish diagnostic attempt:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\tools\hanewin-nfs-provider.ps1 finish-attempt -Config .\windows\lab-10.73.json -Serial d80c0b88 -Mac 88:a2:9e:4f:a9:b1 -PiIp 10.73.0.155 -Mode Portable -ConsoleText "HDMI screen text here"
```

Stop haneWIN portable:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\tools\hanewin-nfs-provider.ps1 stop -Config .\windows\lab-10.73.json -Serial d80c0b88 -Mode Portable
```

## Results

| Profile | Cmdline options | Result |
| --- | --- | --- |
| TCP | `vers=3,tcp` | Fails with `nfs3_getattr/access cannot read args` |
| UDP 1 | `proto=udp,mountproto=udp` | Pi rejects option: `nfs mount bad option proto` |
| UDP 2 | `vers=3,udp,nolock,rsize=4096,wsize=4096` | mountd maps path, then Pi fails: `nfs mount mount: invalid argument` |

Latest evidence:

```text
D:\logs\netboot-harness\20260519-133535-d80c0b88-hanewin-busybox-static
```

Latest verdict:

```text
NFS_MOUNT_INVALID_ARGUMENT
likelyArea: NFS provider mount protocol/options compatibility
confidence: high
```

## Decision

haneWIN does not solve the netboot blocker. The next A/B test should use Linux `nfs-kernel-server` at `10.73.0.20` while Windows keeps DHCP/TFTP.
