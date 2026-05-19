# Project Memory

Last updated: 2026-05-19 13:55 KST

## Goal

Build a Windows version of `rpi-pxe-manager` that manages Raspberry Pi 4 network boot from a Windows server PC.

Important scope rule:

- RPi4: network boot target.
- RPi Zero 2 W: SD boot + USB gadget mode target, separate flow.

## Repository

- GitHub repository: `minoTrey/rpi-pxe-manager`
- Branch: `agent/windows-netboot-manager`
- PR: `https://github.com/minoTrey/rpi-pxe-manager/pull/1`
- Linear primary issue: `3D-5`
- Git author: `minoTrey <39614109+minoTrey@users.noreply.github.com>`

## Lab

| Item | Value |
| --- | --- |
| Server Ethernet | `10.73.0.10/24` |
| Router | `10.73.0.1` |
| Test RPi4 MAC | `88:a2:9e:4f:a9:b1` |
| Test RPi4 serial | `d80c0b88` |
| Test RPi4 IP | `10.73.0.155` |
| TFTP | `D:\tftp\d80c0b88` |
| Rootfs | `D:\rootfs\d80c0b88` |

## Current State

DHCP and TFTP are proven working. RPi4 receives kernel, cmdline, DTB, and initramfs.

Windows NFS provider testing:

- WinNFSd reaches NFS root/init read, then fails with `error -14`.
- haneWIN TCP fails with RPC args parse errors.
- haneWIN UDP reaches mountd path mapping, then fails with `nfs mount mount: invalid argument`.

Current verdict:

```text
NFS_MOUNT_INVALID_ARGUMENT
likelyArea: NFS provider mount protocol/options compatibility
confidence: high
```

## Next Work

1. Stop treating haneWIN as a production option.
2. Use Linux `nfs-kernel-server` as the next A/B provider.
3. Keep Windows DHCP/TFTP.
4. Put bridged Linux VM/helper on `10.73.0.20`.
5. Export `/srv/rpi-root/d80c0b88`.
6. Switch Pi cmdline with `windows\tools\linux-nfs-provider.ps1 start-attempt`.
7. Ask user only to unplug/replug RPi4 power.
8. Finish attempt and update harness verdict.

Note: haneWIN portable NFS was stopped at 2026-05-19 14:10 KST. DHCP/TFTP remain active through `RpiBootServiceLite`; NFS 111/2049 is intentionally free until the Linux NFS helper is ready.

## Tracking Structure

- Current Korean status: `windows/docs/current-test-status-ko.md`
- Daily worklog: `windows/docs/worklog/2026-05-19-netboot-harness.md`
- Obsidian vault: `windows/knowledge/obsidian-vault`
- GBrain graph: `windows/knowledge/gbrain/graph.json`
- Hermes event log: `windows/knowledge/hermes/events.jsonl`

## Operating Rule

After every meaningful attempt:

1. Save raw evidence under `D:\logs\netboot-harness`.
2. Update the status doc and worklog.
3. Commit and push.
4. Comment on GitHub PR #1.
5. Comment on Linear `3D-5`.
