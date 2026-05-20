# Project Memory

Last updated: 2026-05-20 17:14 KST

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

Status: EEPROM SD write completed earlier, but the active UI flow now writes Raspberry Pi OS SD instead. Current disk listing shows the SD readers as `RAW 0 B`, so no writable card is currently inserted in Windows.

## Clone Flow

Current required sequence:

1. Use `RPi4 OS SD 작성` to write Raspberry Pi OS Lite 64-bit Trixie to the selected SD.
2. Boot the new RPi4 from that OS SD.
3. From Raspberry Pi OS, confirm serial and MAC.
   - Serial: `cat /proc/cpuinfo | grep Serial`; use last 8 hex chars.
   - MAC: `cat /sys/class/net/eth0/address`.
4. If needed, update EEPROM/network boot order from the booted OS.
5. GUI `새 RPi4 등록/복제`.
6. GUI `부팅 서비스 시작` to reload DHCP reservation.
7. Power off, remove SD, and boot the new RPi4 over Ethernet.

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

1. Insert a real SD card in Windows; current readers show `RAW 0 B`.
2. Use GUI `RPi4 OS SD 작성` and select the physical SD disk.
3. Boot the target RPi4 from the OS SD.
4. Confirm target Pi serial/MAC and EEPROM/network boot order.
5. Register/clone the new RPi4.
6. Restart boot services if reservations changed.
7. Test SD-less netboot.
8. Improve clone dialog to surface unknown MAC candidates from `D:\logs\rpi-boot-lite.log`.

## Operating Rule

After every meaningful attempt:

1. Save raw evidence under `D:\logs\netboot-harness` or `D:\logs`.
2. Update status doc, worklog, Obsidian Current State, Timeline, Hermes.
3. Commit and push.
4. Comment on GitHub PR #1.
5. Comment on Linear `3D-5`.
