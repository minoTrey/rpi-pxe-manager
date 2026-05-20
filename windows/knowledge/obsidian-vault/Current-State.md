# Current State

Updated: 2026-05-20 17:34 KST

## Active Workspace

Use this project folder:

```text
C:\Users\test\Documents\workspace\rpi-pxe-manager\windows
```

Use this executable:

```text
C:\Users\test\Documents\workspace\rpi-pxe-manager\windows\RPI-Netboot-Manager.exe
```

Do not use `C:\Users\test\Documents\workspace\rpi-netboot-windows` for active work. It is a legacy snapshot.

## Lab

- Server PC: `10.73.0.10/24`
- Router: `10.73.0.1`
- Current storage root: `D:\`
- TFTP root: `D:\tftp`
- Rootfs root: `D:\rootfs`
- Project download cache: `windows\cache\downloads`
- Known-good RPi4 MAC: `88:a2:9e:4f:a9:b1`
- Known-good RPi4 serial: `d80c0b88`
- Known-good RPi4 IP: `10.73.0.155`
- Golden bootfs: `D:\tftp\d80c0b88`
- Golden rootfs: `D:\rootfs\d80c0b88`

## Latest Stable Verdict

```text
BOOT_REACHED_USERSPACE
provider: haneWIN
confidence: high
attempt: 20260519-144335-d80c0b88-hanewin-systemd-explicit
```

Interpretation:

- The first Raspberry Pi 4 reached userspace from the Windows-hosted bootfs/rootfs pair.
- haneWIN remains proof-only and has been removed from this PC.
- Current production-candidate service path is `RpiBootServiceLite` plus project-local `WinNFSd`.

## 2026-05-20 UI And SD State

- GUI cleanup and physical-disk selection were added.
- `D:\downloads` was emptied into `windows\cache\downloads`.
- GUI default SD flow now writes Raspberry Pi OS, not EEPROM.
- The pinned image is `2026-04-21-raspios-trixie-arm64-lite.img`.
- `저장소 설정` and `저장소 열기` now appear only on `서버 PC 준비`, not on every task screen.
- The old PowerShell byte-by-byte verifier was too slow and looked like an error/stall. It is now replaced with a compiled C# buffer comparer plus `verify-image`.
- Disk 3 was verified against the pinned OS image after the GUI write.

Default GUI SD image:

```text
windows\cache\downloads\2026-04-21-raspios-trixie-arm64-lite.img
Raspberry Pi OS Lite 64-bit Trixie
Image size: 3.01 GB
```

Current written SD state:

```text
Disk 3
Generic STORAGE DEVICE
USB
29.72 GB
MBR
Partition 1: FAT32 XINT13, 512 MiB, bootfs
Partition 2: Unknown, 2.5 GiB, Linux rootfs
not boot/system
```

Previous EEPROM image remains cached for CLI fallback:

```text
windows\cache\downloads\rpi-boot-eeprom-recovery-2026-01-09-2711-vl805-000138c0-network\
SHA256 43639F3D17C53D47C1E54D6B6C9229BB095014A15A93BD948717B45343EA22F7
```

## Provider Cleanup

haneWIN is no longer installed on this PC.

- Removed services: `DHCPservice`, `TFTPService`, `NFSserver`, `PMAPDaemon`
- Removed folders: `C:\Program Files\dhcp`, `C:\Program Files\tftp`, `C:\Program Files\nfsd`, `D:\tools\rpi-netboot\hanewin-portable`
- Cleanup log: `D:\logs\hanewin-cleanup-20260520-1625.log`
- Preserved proof logs: `D:\logs\hanewin-portable.stdout.log`, `D:\logs\hanewin-portable.stderr.log`

Current boot services:

```text
RpiBootServiceLite PID 6696: DHCP/TFTP
WinNFSd PID 11120: NFS 111/2049 on 10.73.0.10
```

## Clone Flow

Recommended operator flow:

1. Use `RPi4 OS SD 작성` to write Raspberry Pi OS Lite 64-bit Trixie to an SD card.
2. Boot the target RPi4 from that OS SD.
3. Confirm serial and MAC from Raspberry Pi OS.
4. Update EEPROM/network boot order from the OS if needed.
5. Run `새 RPi4 등록/복제` in the GUI.
6. Restart boot services if DHCP reservations changed.
7. Remove SD and test Ethernet netboot.

Potential next UX improvement:

- Parse `D:\logs\rpi-boot-lite.log` for `DHCP ignored unknown MAC ...`.
- Show unknown MAC candidates in the clone dialog.
- Serial still needs user confirmation unless a future provisioning helper reports it.

## Next Move

1. Eject Disk 3 cleanly.
2. Boot the target RPi4 from the verified OS SD.
3. Confirm serial/MAC and EEPROM/network boot order.
4. Continue with `새 RPi4 등록/복제`.
