# Current State

Updated: 2026-05-19 13:55 KST

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
NFS_MOUNT_INVALID_ARGUMENT
provider: haneWIN
confidence: high
```

## Interpretation

The Pi is not blocked at DHCP or TFTP. It reaches NFS mount negotiation. Windows NFS providers are now the main suspect.

## Next Move

Use Linux `nfs-kernel-server` on a bridged Linux VM/helper at `10.73.0.20`, while keeping Windows DHCP/TFTP.

## Process State

haneWIN portable NFS was stopped at 2026-05-19 14:10 KST. DHCP/TFTP remain active; Windows NFS ports are intentionally free for the next provider decision.

At 2026-05-19 14:19 KST, haneWIN was started again for one final official-minimal profile attempt:

```text
20260519-141926-d80c0b88-hanewin-busybox-static
nfsroot=10.73.0.10:/rpi/d80c0b88,vers=3
```

That attempt reached the diagnostic BusyBox init. The original systemd init has been restored. Active attempt:

```text
20260519-144335-d80c0b88-hanewin-systemd-explicit
```
