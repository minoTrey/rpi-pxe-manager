# ADR-0005: RPi4 Clone Workflow and Provider Policy

Date: 2026-05-19

## Status

Accepted for implementation.

## Context

The first Raspberry Pi 4 reached userspace through network boot with:

```text
attempt: 20260519-144335-d80c0b88-hanewin-systemd-explicit
verdict: BOOT_REACHED_USERSPACE
```

The successful provider was haneWIN, but haneWIN is a 30-day evaluation product when unregistered. It cannot be the operating provider for this project.

The user also requires additional RPi4 devices to be cloned quickly from the server PC SSD with minimal manual commands.

## Decision

1. Treat `d80c0b88` as the first known-good RPi4 and current golden source.
2. Add `windows/tools/clone-rpi4-client.ps1` as the automation core for register/clone/verify.
3. Keep haneWIN as proof-only. Do not present it as production.
4. Use no-expiry provider testing before production:
   - quick no-expiry retest: WinNFSd minimal profile,
   - recommended stable architecture: Linux NFS appliance/helper.

## Consequences

- New RPi4 devices can be registered by serial/MAC and cloned into `D:\tftp\<serial>` and `D:\rootfs\<serial>`.
- The current working Pi is protected; targets are not overwritten unless forced.
- GUI work should wrap the script as a wizard instead of re-implementing clone logic.
- Production provider work remains open until WinNFSd minimal or Linux NFS passes the same boot success criteria.
