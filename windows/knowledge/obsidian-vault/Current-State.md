# Current State

Updated: 2026-05-19 15:15 KST

## Lab

- Server PC: `10.73.0.10/24`
- Router: `10.73.0.1`
- Test RPi4 MAC: `88:a2:9e:4f:a9:b1`
- Test RPi4 serial: `d80c0b88`
- Test RPi4 IP: `10.73.0.155`
- TFTP: `D:\tftp\d80c0b88`
- Rootfs: `D:\rootfs\d80c0b88`

## Latest Verdict

```text
BOOT_REACHED_USERSPACE
provider: haneWIN
confidence: high
attempt: 20260519-144335-d80c0b88-hanewin-systemd-explicit
```

## Interpretation

The first Raspberry Pi 4 reached userspace from the Windows-hosted bootfs/rootfs pair.
This proves the lab network, EEPROM setting, TFTP prefix, bootfs, rootfs, and minimal NFS root command line are coherent.

This does **not** approve haneWIN for production. haneWIN is a proof-only diagnostic provider because the unregistered product expires after 30 days.

## Next Move

1. Preserve `d80c0b88` as the current known-good/golden RPi4.
2. Use `windows/tools/clone-rpi4-client.ps1` to register and clone new RPi4 bootfs/rootfs pairs.
3. Retest the same known-good bootfs/rootfs under a no-expiry provider:
   - first quick candidate: WinNFSd with the minimal `vers=3` profile,
   - stable production candidate: Linux NFS appliance/helper with ext4 + `nfs-kernel-server`.

## Process State

haneWIN portable NFS is currently proof-only. Do not stop the active NFS provider while the Pi is running from the NFS root.
Stop or switch providers only after the Pi is powered off or migrated.

Successful attempt:

```text
20260519-144335-d80c0b88-hanewin-systemd-explicit
cmdline: nfsroot=10.73.0.10:/rpi/d80c0b88,vers=3 init=/usr/sbin/init
verdict: BOOT_REACHED_USERSPACE
evidence: D:\logs\netboot-harness\20260519-144335-d80c0b88-hanewin-systemd-explicit
```

Current clone source:

```text
bootfs: D:\tftp\d80c0b88
rootfs: D:\rootfs\d80c0b88
```
