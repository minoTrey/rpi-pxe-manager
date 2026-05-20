# 2026-05-20 GUI, workspace, storage, EEPROM handoff

## Summary

User reported the Codex GUI had been unstable and wanted the CLI session to continue, clean the app surface, remove duplicate executables, improve UI/UX, clarify workspace usage, and verify the Pi 4 EEPROM SD flow.

## Active workspace decision

Use:

```text
C:\Users\test\Documents\workspace\rpi-pxe-manager\windows
```

Do not use:

```text
C:\Users\test\Documents\workspace\rpi-netboot-windows
```

`rpi-netboot-windows` is a legacy snapshot. Its local launcher exe was removed to prevent accidental use.

## Packaging cleanup

The active project now exposes one executable:

```text
windows\RPI-Netboot-Manager.exe
```

Removed from the active repo surface:

- admin/normal BAT launchers
- old provider attempt BAT files
- SD helper BAT wrappers
- restore/sync/check BAT wrappers

The GUI now self-elevates the same executable when a task requires administrator rights.

## GUI/UX cleanup

User rejected the first UI cleanup as visually poor. The second pass changed:

- removed sidebar `권장 순서`
- removed footer `자동화 UI 빌드`
- removed duplicate help/document action wording
- removed haneWIN/evaluation/provider experiment wording from the executable-facing UI
- improved button sizes, spacing, card layout, log area, and status strip
- changed font fallback to Korean-friendly families
- kept the operational actions only:
  - `상태 확인`
  - `서버 PC 준비`
  - `부팅 서비스 시작`
  - `새 RPi4 등록/복제`
  - `RPi4 EEPROM SD`
  - `Zero 2 W Gadget SD`
  - `도움말`

Validation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\gui\build-gui.ps1
```

Build succeeded. A real WinForms screenshot of the clone screen was checked for obvious clipping/overlap.

## Configurable storage

The GUI can now choose a storage root instead of assuming `D:\`.

Storage setting updates:

- `project_root`
- `tftp_root`
- `nfs_root`
- `iscsi_root`

Current lab storage remains `D:\`, but this is no longer hardcoded as the only option.

## EEPROM image cache

Problem: Pi 4 EEPROM image had been downloaded to `D:\downloads`, which made the storage root messy.

Change:

- `rpi-sd-card.ps1` default cache is now project-local:

  ```text
  windows\cache\downloads
  ```

- `rpi-netboot-manager.ps1` uses that project cache for EEPROM SD preparation.
- `.gitignore` ignores `windows/cache/`.
- Existing EEPROM zip/img/os-list files were moved from `D:\downloads` into the project cache.

Current image:

```text
windows\cache\downloads\rpi-boot-eeprom-recovery-2026-01-09-2711-vl805-000138c0-network\rpi-boot-eeprom-recovery-2026-01-09-2711-vl805-000138c0-network.img
```

SHA256:

```text
43639F3D17C53D47C1E54D6B6C9229BB095014A15A93BD948717B45343EA22F7
```

## Current SD status

Read-only check found:

```text
Disk 3
Generic STORAGE DEVICE
USB
29.72 GB
S: bootfs FAT32, about 504 MB
IsBoot false
IsSystem false
```

This is a valid non-system USB target, but it looks like an existing Raspberry Pi OS bootfs SD. Running `RPi4 EEPROM SD` will erase the full 29.72 GB card.

Next session must ask user if that SD may be erased before running the write.

## Clone flow clarification

EEPROM SD is a one-time bootloader update, not the clone itself.

New RPi4 clone flow:

1. Write Pi 4 EEPROM SD.
2. Boot target RPi4 once from the EEPROM SD.
3. Power off and remove SD.
4. Confirm serial and MAC.
5. Run GUI `새 RPi4 등록/복제`.
6. Restart `부팅 서비스 시작`.
7. Boot target RPi4 with no SD card.

Current implementation requires manual serial/MAC input.

Helpful commands on a Pi OS boot:

```bash
cat /proc/cpuinfo | grep Serial
cat /sys/class/net/eth0/address
```

If serial is `10000000d80c0b88`, enter the last 8 hex characters: `d80c0b88`.

Logs can reveal unknown MACs:

```text
D:\logs\rpi-boot-lite.log
DHCP ignored unknown MAC ...
```

Future UX improvement: parse unknown MAC candidates from that log and show them in the clone dialog. Serial should remain a required confirmation until a reliable reporting helper exists.

## Next actions

1. Boot the target RPi4 once from the completed EEPROM SD.
2. Power off and remove the SD.
3. Confirm serial/MAC for the new RPi4.
4. Clone/register the new RPi4.
5. Restart boot services if reservations changed.
6. Test SD-less boot.
7. Update GitHub PR #1 and Linear `3D-5` after the next verdict.

## 16:35 update

Completed after the initial handoff:

- Restored root `AGENTS.md` from repo-backed memory, Obsidian, Hermes, GitHub/Linear state, and Codex GUI traces.
- Removed haneWIN services and install folders from this PC:
  - `DHCPservice`
  - `TFTPService`
  - `NFSserver`
  - `PMAPDaemon`
  - `C:\Program Files\dhcp`
  - `C:\Program Files\tftp`
  - `C:\Program Files\nfsd`
  - `D:\tools\rpi-netboot\hanewin-portable`
- Preserved haneWIN proof logs under `D:\logs`.
- Restarted active boot services on:
  - `D:\tools\rpi-netboot\bin\RpiBootServiceLite.exe`
  - `D:\tools\rpi-netboot\winnfsd\WinNFSd.exe`
- Added GUI physical-disk selection for `RPi4 EEPROM SD`; the write flow no longer assumes `S:`.
- Verified the selector window appears before writing.
- Wrote the Pi 4 Network Boot EEPROM image to Disk 3 after user confirmation.

Post-write Disk 3 state:

```text
Disk 3
Generic STORAGE DEVICE
USB
29.72 GB
MBR
Partition 1: FAT32 XINT13, 256 MiB
IsBoot false
IsSystem false
```

Validation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\gui\build-gui.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\tools\rpi-sd-card.ps1 list -CacheDir .\windows\cache\downloads
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\tools\lite-provider.ps1 status -Config .\windows\lab-10.73.json
```

Cleanup evidence:

```text
D:\logs\hanewin-cleanup-20260520-1625.log
```
