# Round: haneWIN Minimal Profile

Started: 2026-05-19 14:19 KST

## State

```text
attempt: 20260519-141926-d80c0b88-hanewin-busybox-static
provider: haneWIN portable
dhcp/tftp: RpiBootServiceLite
nfs: haneWIN nfsd.exe PID 13856
cmdline: nfsroot=10.73.0.10:/rpi/d80c0b88,vers=3
device: RPi4 d80c0b88 / 88:a2:9e:4f:a9:b1 / 10.73.0.155
```

## Question

Does the haneWIN failure come from the previous extra NFS options, or from haneWIN provider compatibility itself?

## Expected Evidence After Power Cycle

- `D:\logs\rpi-boot-lite.log` delta for DHCP/TFTP.
- `D:\logs\hanewin-portable.stdout.log` delta for mount/rootfs reads.
- HDMI console text from user.
- `verdict.json` under `D:\logs\netboot-harness\20260519-141926-d80c0b88-hanewin-busybox-static`.

## Decision Threshold

| Outcome | Decision |
| --- | --- |
| Rootfs read and init read happen | Compare against WinNFSd `error -14` and continue init/rootfs diagnosis |
| NFS mount fails again | Reject haneWIN as provider path |
| Same `invalid argument` | Escalate immediately to Linux `nfs-kernel-server` |
| No DHCP/TFTP delta | Do not blame NFS; check physical power/link and active attempt state |

## Pending Agent Inputs

Round-1 proposals were received from all six agents.

## Result

The haneWIN official-minimal profile reached NFS root mount and executed the diagnostic BusyBox init.

```text
verdict: INIT_EXEC_REACHED_BUSYBOX_RC_MISSING
evidence: D:\logs\netboot-harness\20260519-141926-d80c0b88-hanewin-busybox-static
```

## Council Decision

The previous haneWIN `invalid argument` failure was caused by the richer UDP/options profile, not by all haneWIN NFS usage. The next valid test is the same haneWIN minimal profile with the original systemd init restored.

## Next Attempt

```text
attempt: 20260519-144335-d80c0b88-hanewin-systemd-explicit
cmdline: nfsroot=10.73.0.10:/rpi/d80c0b88,vers=3 init=/usr/sbin/init
```

Decision threshold:

- If systemd boots or reaches meaningful userspace logs, haneWIN minimal is a viable diagnostic provider.
- If systemd fails again with `error -14`, escalate to Linux `nfs-kernel-server`.
- If NFS mount fails again, keep haneWIN rejected for production and escalate to Linux helper.
