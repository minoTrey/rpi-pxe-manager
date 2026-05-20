# RPi4 Netboot Success

Date: 2026-05-19 15:15 KST

## Result

The first Raspberry Pi 4 reached userspace through network boot.

```text
serial: d80c0b88
mac: 88:a2:9e:4f:a9:b1
ip: 10.73.0.155
attempt: 20260519-144335-d80c0b88-hanewin-systemd-explicit
verdict: BOOT_REACHED_USERSPACE
```

## What This Proves

- EEPROM network boot configuration works.
- The server PC at `10.73.0.10` can serve the Pi through DHCP/TFTP.
- `D:\tftp\d80c0b88` contains a working RPi4 bootfs.
- `D:\rootfs\d80c0b88` contains a bootable rootfs.
- The minimal NFS root command line works for the successful diagnostic provider.

## Production Caveat

haneWIN is not approved for production.
It was useful as a proof provider, but the unregistered version expires after 30 days.

The next production decision is between:

- WinNFSd minimal retest: fastest no-expiry Windows experiment.
- Linux NFS appliance: recommended stable operating architecture.
- iSCSI: possible Windows-only long-term alternative, higher complexity.

## Golden Candidate

Current golden source:

```text
bootfs: D:\tftp\d80c0b88
rootfs: D:\rootfs\d80c0b88
```

Promote this to `D:\templates\golden\rpi4` only after the Pi is shut down cleanly or the rootfs is otherwise quiesced.
