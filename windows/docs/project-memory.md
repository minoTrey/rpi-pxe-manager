# Project Memory

Last updated: 2026-05-20 14:25 KST

## Goal

Build a Windows version of `rpi-pxe-manager` that manages Raspberry Pi 4 network boot from a Windows server PC.

Important scope rule:

- RPi4: Ethernet network boot target.
- RPi Zero 2 W: SD boot + USB gadget mode target, separate flow.

## Repository

- GitHub repository: `minoTrey/rpi-pxe-manager`
- Branch: `agent/windows-netboot-manager`
- PR: `https://github.com/minoTrey/rpi-pxe-manager/pull/1`
- Linear primary issue: `3D-5`
- Linear project: `RPI Netboot Windows`

## Active Workspace

Use:

```text
C:\Users\test\Documents\workspace\rpi-pxe-manager\windows
```

Active executable:

```text
C:\Users\test\Documents\workspace\rpi-pxe-manager\windows\RPI-Netboot-Manager.exe
```

Do not continue active work from:

```text
C:\Users\test\Documents\workspace\rpi-netboot-windows
```

That folder is a legacy snapshot. Its old launcher exe was removed locally.

## Lab

| Item | Value |
| --- | --- |
| Server Ethernet | `10.73.0.10/24` |
| Router | `10.73.0.1` |
| Config | `windows\lab-10.73.json` |
| Current storage root | `D:\` |
| TFTP root | `D:\tftp` |
| Rootfs root | `D:\rootfs` |
| Logs | `D:\logs` |
| EEPROM cache | `windows\cache\downloads` |
| Golden RPi4 MAC | `88:a2:9e:4f:a9:b1` |
| Golden RPi4 serial | `d80c0b88` |
| Golden RPi4 IP | `10.73.0.155` |

## Current State

Known-good boot result:

```text
verdict: BOOT_REACHED_USERSPACE
attempt: 20260519-144335-d80c0b88-hanewin-systemd-explicit
provider: haneWIN
cmdline: nfsroot=10.73.0.10:/rpi/d80c0b88,vers=3 init=/usr/sbin/init
```

Meaning:

- DHCP/TFTP/network path are proven.
- Golden bootfs/rootfs pair is proven for `d80c0b88`.
- haneWIN proved the path but remains proof-only, not production.
- The no-expiry provider path still needs WinNFSd minimal or Linux NFS helper validation.

## 2026-05-20 Work Completed

- Cleaned the WinForms GUI after user feedback.
- Removed `권장 순서`, `자동화 UI 빌드`, haneWIN/provider experiment wording from the executable-facing UI.
- Improved layout, spacing, button sizing, colors, and Korean font fallback.
- Added/kept configurable storage root in GUI so storage is not assumed to always be `D:\`.
- Removed admin/bat launcher clutter from the active project.
- Confirmed there is only one executable/batch surface across active + legacy workspace: `windows\RPI-Netboot-Manager.exe`.
- Moved Pi 4 EEPROM download cache from `D:\downloads` to project-local ignored cache `windows\cache\downloads`.
- Updated SD card docs and status wording from `권장 순서` to `작업 흐름`.
- Confirmed current `S:` is a 29.72 GB USB SD (`bootfs` FAT32); EEPROM write would erase it.
- Documented that new RPi4 clone flow still needs manual serial and MAC input.

## EEPROM SD Checkpoint

Image:

```text
windows\cache\downloads\rpi-boot-eeprom-recovery-2026-01-09-2711-vl805-000138c0-network\rpi-boot-eeprom-recovery-2026-01-09-2711-vl805-000138c0-network.img
```

Hash:

```text
SHA256 43639F3D17C53D47C1E54D6B6C9229BB095014A15A93BD948717B45343EA22F7
```

Current target candidate:

```text
Disk 3
Generic STORAGE DEVICE
USB
29.72 GB
S: bootfs FAT32
IsBoot: false
IsSystem: false
```

Warning: this is currently a Raspberry Pi OS bootfs-style SD. Do not run `RPi4 EEPROM SD` unless the user confirms it can be erased.

## Clone Flow

Current required sequence:

1. Write Pi 4 EEPROM SD.
2. Boot the new RPi4 once from that SD.
3. Power off and remove SD.
4. Confirm serial and MAC.
   - Serial: `cat /proc/cpuinfo | grep Serial`; use last 8 hex chars.
   - MAC: `cat /sys/class/net/eth0/address`.
5. GUI `새 RPi4 등록/복제`.
6. GUI `부팅 서비스 시작` to reload DHCP reservation.
7. Boot the new RPi4 SD-less over Ethernet.

Known limitation:

- The service log can show unknown MACs, for example `DHCP ignored unknown MAC ...`.
- It does not reliably provide the RPi4 serial yet.
- Next UX improvement should parse unknown MAC candidates for the clone dialog while keeping serial as explicit input.

## Tracking Structure

- Current Korean status: `windows/docs/current-test-status-ko.md`
- Daily worklog: `windows/docs/worklog/2026-05-20-gui-storage-eeprom.md`
- Obsidian vault: `windows/knowledge/obsidian-vault`
- GBrain graph: `windows/knowledge/gbrain/graph.json`
- Hermes event log: `windows/knowledge/hermes/events.jsonl`

## Next Work

1. Ask whether the current `S:` SD may be erased.
2. If yes, run `RPi4 EEPROM SD` and verify write.
3. Confirm target Pi serial/MAC.
4. Register/clone the new RPi4.
5. Restart boot services.
6. Test SD-less netboot.
7. Improve clone dialog to surface unknown MAC candidates from `D:\logs\rpi-boot-lite.log`.

## Operating Rule

After every meaningful attempt:

1. Save raw evidence under `D:\logs\netboot-harness` or `D:\logs`.
2. Update status doc, worklog, Obsidian Current State, Timeline, Hermes.
3. Commit and push.
4. Comment on GitHub PR #1.
5. Comment on Linear `3D-5`.
