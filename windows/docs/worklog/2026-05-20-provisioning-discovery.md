# 2026-05-20 Provisioning Discovery

## Problem

The first OS SD write booted the new Raspberry Pi far enough to request DHCP, but the manager could not learn the Pi serial. The current service only answered statically registered MAC addresses, so an unregistered Pi needed a manual temporary lease before it could even boot from the OS SD.

## Change

`RpiBootServiceLite` now has a discovery path for new Raspberry Pis:

- Raspberry Pi MAC OUIs can receive temporary discovery leases from `10.73.0.180` to `10.73.0.199`.
- Non-Raspberry Pi MACs remain ignored by default.
- The service also listens on TCP 8088 for `POST /provision/report`.
- Reports are appended to `D:\logs\rpi-provisioning.jsonl`.

The default `RPi4 OS SD 작성` path now writes Raspberry Pi OS Lite 64-bit Trixie and then patches the bootfs cloud-init files:

- `user-data` installs `/usr/local/sbin/rpi-netboot-report.py`.
- `network-config` keeps Ethernet DHCP enabled.
- `meta-data` gets a fresh cloud-init instance id.

On first boot, the Pi reports:

- serial, using the last 8 hex chars from `/proc/cpuinfo`
- Ethernet MAC
- current IP
- model
- EEPROM `BOOT_ORDER`
- short `rpi-eeprom-update` status

The clone dialog reads the newest provisioning report and pre-fills serial, MAC, and IP.

## Verification

- Rebuilt `RpiBootServiceLite.exe`.
- Restarted active services:
  - `RpiBootServiceLite` PID `10076`
  - `WinNFSd` PID `780`
- Confirmed listeners:
  - DHCP UDP 67
  - TFTP UDP 69
  - Provision TCP 8088
  - NFS TCP 2049 on `10.73.0.10`
- Rebuilt `RPI-Netboot-Manager.exe`.
- Parsed these scripts successfully:
  - `windows/tools/rpi-sd-card.ps1`
  - `windows/tools/rpi-netboot-manager.ps1`
  - `windows/tools/lite-provider.ps1`
- Ran GUI status. It now reports Provision TCP 8088 as healthy.

## Current Caveat

The SD already booted by the user was written before the provisioning patch existed. It can get DHCP, but it will not report serial automatically. Re-write the SD through the updated `RPi4 OS SD 작성` flow, then boot the target Pi again.
