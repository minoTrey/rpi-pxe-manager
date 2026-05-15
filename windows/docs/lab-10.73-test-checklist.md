# 10.73.0.0/24 Lab Test Checklist

This checklist assumes the Windows machine uses the wired adapter named `이더넷`.

## Current State

- The generated config is `lab-10.73.json`.
- The generated plan is `generated/lab-10.73`.
- Server IP is `10.73.0.10`.
- Router/admin IP is `10.73.0.1`.
- Client reservations were imported from the old project and remapped to
  `10.73.0.x`.

## Network Order

1. Connect the Windows PC Ethernet port to the ipTIME LAN side.
2. Connect Raspberry Pi Ethernet to the same ipTIME LAN side.
3. Set ipTIME LAN IP/subnet:
   - LAN IP: `10.73.0.1`
   - Subnet mask: `255.255.255.0`
4. For netboot testing, do not let ipTIME answer DHCP for the Pi.
   - Preferred: turn off ipTIME DHCP after the Windows PC has a static IP.
   - Reason: Raspberry Pi needs DHCP/TFTP boot options; normal consumer DHCP
     usually does not provide them.
5. Set the Windows `이더넷` adapter to static `10.73.0.10/24`.
   - Use `tools/set-ethernet-10.73.ps1` from an elevated PowerShell.
   - The script intentionally does not set an Ethernet default gateway by
     default, so Wi-Fi can keep normal internet routing.

## Windows Boot Services

For the current MVP path, use the `hanewin-nfs` plan as a quick validation path.
haneWIN is a 30-day evaluation provider when unregistered, so it is not the
long-term operating default. Open-source/built-in providers are being prepared
for operation.

Required services:

- DHCP with Raspberry Pi PXE/vendor option support.
- TFTP serving Raspberry Pi boot files.
- NFSv3 serving Linux root filesystems.

Generated references:

- `generated/lab-10.73/windows/hanewin-dhcp-profile.md`
- `generated/lab-10.73/windows/hanewin-nfs-exports.txt`
- `generated/lab-10.73/windows/01-firewall.ps1`

## Boot Files

The generated `tftp/<serial>` folders contain only generated `cmdline.txt` and
`config.txt`. They are not a complete Raspberry Pi boot partition yet.

For the first test, use one Pi only:

1. Pick the Pi serial/MAC from `lab-10.73.json`.
2. Copy the Pi boot partition files into that Pi's generated TFTP folder.
3. Keep or merge the generated `cmdline.txt`.
4. Configure the DHCP/TFTP tool so that the Pi gets that folder as its boot
   prefix, or temporarily test with a flat TFTP root for one Pi.

## Root Filesystem

Do not copy the Linux root filesystem with Windows Explorer. The root filesystem
needs ownership, permissions, symlinks, hardlinks, and special files preserved.

Use a Raspberry Pi or Linux helper machine and the generated script:

```bash
SERVER_IP=10.73.0.10 CLIENT_SERIAL=<serial> ./generated/lab-10.73/pi/materialize-rootfs.sh /mnt/pi-root
```

## Quick Checks

Run from this project:

```powershell
.\tools\check-lab-10.73.ps1
```

Expected before services are installed:

- Router ping to `10.73.0.1` succeeds.
- UDP 67/69 and TCP 2049 are usually empty.

Expected after services are installed:

- DHCP/TFTP tool listens on UDP 67/69.
- NFS listens on TCP/UDP 2049 or, during quick validation, the haneWIN service is visible.
- The Pi receives a `10.73.0.x` address and starts requesting TFTP files.

## Restore Ethernet DHCP

If you want to undo the static IP:

```powershell
.\tools\restore-ethernet-dhcp.ps1
```
