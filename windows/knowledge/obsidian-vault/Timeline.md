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
