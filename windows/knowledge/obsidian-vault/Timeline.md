# Timeline

## 2026-05-19

- 10:25 - WinNFSd reached NFS root/init read, then failed with `error -14`.
- 10:50 - Linux NFS provider bundle automation added.
- 12:13 - haneWIN portable provider added for A/B testing.
- 13:13 - haneWIN TCP failed with RPC args parsing errors.
- 13:20 - haneWIN UDP first profile failed because Pi rejected `proto=udp`.
- 13:40 - haneWIN UDP corrected profile reached mountd path mapping, then Pi failed with `nfs mount mount: invalid argument`.
- 13:55 - Harness verdict updated to `NFS_MOUNT_INVALID_ARGUMENT`.
- 14:19 - Started haneWIN official-minimal profile attempt `20260519-141926-d80c0b88-hanewin-busybox-static`; waiting for RPi4 power cycle.
- 14:34 - haneWIN minimal reached NFS root and diagnostic BusyBox init; verdict `INIT_EXEC_REACHED_BUSYBOX_RC_MISSING`.
- 14:43 - Restored original systemd init and started `20260519-144335-d80c0b88-hanewin-systemd-explicit`.
- 15:12 - User reported successful RPi4 boot; harness records `BOOT_REACHED_USERSPACE`.
- 15:15 - Added `clone-rpi4-client.ps1` so new RPi4 devices can be registered and cloned from the known-good `d80c0b88` bootfs/rootfs pair.
- 15:45 - Added Device ID based GUI flow. `rpi-001` now becomes hostname plus `/etc/rpi-netboot/client.json` metadata for cloned RPi4 rootfs.
- 16:20 - Cleaned the executable UI to show only operational actions; diagnostic/provider experiment buttons were removed from the WinForms surface.
- 17:20 - Audited `D:\` storage. Pruned the committed lab config from the old 60-device plan down to the proven `d80c0b88` RPi4 and updated status checks to flag stale storage folders instead of recreating iSCSI/backups/templates.

## 2026-05-20

- 11:35 - Reworked the WinForms UI after user feedback: removed `권장 순서` and `자동화 UI 빌드`, improved spacing, button sizing, palette, and Korean font fallback.
- 11:40 - Confirmed the active workspace is `rpi-pxe-manager\windows`; the old `rpi-netboot-windows` launcher exe was removed locally to avoid confusion.
- 11:45 - Confirmed only one executable/batch surface remains across active + legacy workspace: `windows\RPI-Netboot-Manager.exe`.
- 14:05 - Verified Pi 4 Network Boot EEPROM image download and moved the EEPROM cache into `windows\cache\downloads`.
- 14:12 - Confirmed current `S:` is `Disk 3`, USB, 29.72 GB, `bootfs` FAT32. It is safe from boot/system disk checks but will be erased if EEPROM write is run.
- 14:20 - Documented clone order: EEPROM SD is a one-time bootloader update; new RPi4 still needs serial/MAC confirmation before `새 RPi4 등록/복제`.
- 16:03 - Restarted active boot services on `RpiBootServiceLite` plus project-local `WinNFSd`; DHCP/TFTP/NFS ports are owned by the production candidate path.
- 16:24 - Removed haneWIN services and install folders from the PC while preserving proof logs.
- 16:30 - Added and verified GUI physical-disk selection for `RPi4 EEPROM SD`; the flow no longer assumes `S:`.
- 16:32 - Wrote the Pi 4 Network Boot EEPROM image to Disk 3. Post-write state is MBR with one 256 MiB FAT32 XINT13 partition, not boot/system.
- 17:14 - Moved all remaining `D:\downloads` contents into `windows\cache\downloads`, rebuilt the GUI so the default SD flow is `RPi4 OS SD 작성`, and pinned it to Raspberry Pi OS Lite 64-bit Trixie `2026-04-21-raspios-trixie-arm64-lite.img`.
- 17:30 - Scoped `저장소 설정` and `저장소 열기` to the `서버 PC 준비` screen only, removing repeated storage controls from task-specific screens.
- 17:34 - Diagnosed the SD write "error" as the old PowerShell byte-by-byte verifier stalling after the image write. Replaced verification with compiled C# buffer comparison, added `verify-image`, and verified Disk 3 against the pinned OS image.
