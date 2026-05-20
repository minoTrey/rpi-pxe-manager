# Project Memory

Last updated: 2026-05-20 18:10 KST

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
| Project download cache | `windows\cache\downloads` |
| Golden RPi4 MAC | `88:a2:9e:4f:a9:b1` |
| Golden RPi4 serial | `d80c0b88` |
| Golden RPi4 IP | `10.73.0.155` |
| Discovery pool | `10.73.0.180`-`10.73.0.199` for Raspberry Pi MAC OUIs |
| Provision listener | `http://10.73.0.10:8088/provision/report` |
| Provision log | `D:\logs\rpi-provisioning.jsonl` |

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
- haneWIN proved the path but is now removed from this PC and remains proof-only.
- Current boot service path is `RpiBootServiceLite` for DHCP/TFTP plus project-local `WinNFSd` for NFS.

## 2026-05-20 Work Completed

- Cleaned the WinForms GUI after user feedback.
- Added/kept configurable storage root in GUI so storage is not assumed to always be `D:\`.
- Confirmed the active executable surface is `windows\RPI-Netboot-Manager.exe`.
- Restored repository-level `AGENTS.md` from repo memory and Codex GUI traces.
- Added physical-disk selection before SD writes; the GUI no longer assumes `S:`.
- Removed haneWIN services and local install folders from this PC. Proof logs remain in `D:\logs`.
- Restarted boot services on `RpiBootServiceLite` plus project-local `WinNFSd`.
- Wrote the Pi 4 Network Boot EEPROM image to Disk 3 after user confirmation.
- Moved all remaining `D:\downloads` contents into `windows\cache\downloads`; `D:\downloads` is now empty.
- Changed the GUI default SD flow from EEPROM SD writing to Raspberry Pi OS SD writing.
- Pinned the OS SD image to `2026-04-21-raspios-trixie-arm64-lite.img` (Raspberry Pi OS Lite 64-bit Trixie).
- Scoped `저장소 설정` and `저장소 열기` to `서버 PC 준비` only; other task screens now show only their primary task action.
- Fixed the SD verifier performance bug by moving block comparison into a compiled C# helper and adding `verify-image`.
- Verified Disk 3 against `2026-04-21-raspios-trixie-arm64-lite.img` after the GUI write.
- Added first-boot provisioning: OS SD cloud-init now reports serial, MAC, IP, model, EEPROM `BOOT_ORDER`, and short EEPROM status to the Windows manager.
- Extended `RpiBootServiceLite` with Raspberry Pi-only dynamic discovery leases and a TCP 8088 provisioning receiver.
- Updated the clone dialog to read `D:\logs\rpi-provisioning.jsonl` and pre-fill serial, MAC, and IP.

## OS SD Checkpoint

Default GUI SD image:

```text
windows\cache\downloads\2026-04-21-raspios-trixie-arm64-lite.img
Raspberry Pi OS Lite 64-bit Trixie
Image size: 3.01 GB
```

Command verification:

```text
powershell -File tools\rpi-sd-card.ps1 download-rpios-lite-trixie -CacheDir .\windows\cache\downloads
Source: cache
```

Previous EEPROM image remains cached for CLI fallback:

```text
windows\cache\downloads\rpi-boot-eeprom-recovery-2026-01-09-2711-vl805-000138c0-network\rpi-boot-eeprom-recovery-2026-01-09-2711-vl805-000138c0-network.img
SHA256 43639F3D17C53D47C1E54D6B6C9229BB095014A15A93BD948717B45343EA22F7
```

Verified written target:

```text
Disk 3
Generic STORAGE DEVICE
USB
29.72 GB
MBR
Partition 1: FAT32 XINT13, 512 MiB, bootfs
Partition 2: Unknown, 2.5 GiB, Linux rootfs
IsBoot: false
IsSystem: false
```

Status: OS SD write is complete and `verify-image` passed. The earlier GUI-side error/stall was caused by the old byte-by-byte PowerShell verifier, not by a bad image write.

## Clone Flow

Current required sequence:

1. Use `RPi4 OS SD 작성` to write Raspberry Pi OS Lite 64-bit Trixie to the selected SD.
2. Boot the new RPi4 from that OS SD.
3. The manager gives Raspberry Pi MACs a temporary discovery lease and waits for the first-boot report.
4. GUI `새 RPi4 등록/복제`; confirm the pre-filled serial/MAC/IP and choose the device id.
5. GUI `부팅 서비스 시작` to reload DHCP reservation if the clone changed config.
6. Power off, remove SD, and boot the new RPi4 over Ethernet.

Known limitation:

- The SD written before this provisioning change does not contain the reporter. Re-write it with `RPi4 OS SD 작성` before expecting automatic serial discovery.

## Tracking Structure

- Current Korean status: `windows/docs/current-test-status-ko.md`
- Daily worklog: `windows/docs/worklog/2026-05-20-gui-storage-eeprom.md`
- Obsidian vault: `windows/knowledge/obsidian-vault`
- GBrain graph: `windows/knowledge/gbrain/graph.json`
- Hermes event log: `windows/knowledge/hermes/events.jsonl`

## Next Work

1. Re-write the SD with the updated `RPi4 OS SD 작성` flow.
2. Boot the target RPi4 from the updated OS SD and watch for `D:\logs\rpi-provisioning.jsonl`.
3. Register/clone the new RPi4 using the pre-filled values.
4. Restart boot services if reservations changed.
5. Test SD-less netboot.

## Operating Rule

After every meaningful attempt:

1. Save raw evidence under `D:\logs\netboot-harness` or `D:\logs`.
2. Update status doc, worklog, Obsidian Current State, Timeline, Hermes.
3. Commit and push.
4. Comment on GitHub PR #1.
5. Comment on Linear `3D-5`.
