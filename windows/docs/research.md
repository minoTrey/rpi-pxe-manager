# Research: Raspberry Pi Netboot From Windows

## Conclusion

Windows can host Raspberry Pi network boot. The host must provide the same boot
services normally provided by Linux: DHCP, TFTP, and a Linux-compatible root
filesystem backend such as NFSv3 or iSCSI.

The fastest Windows Desktop validation route is haneWIN DHCP/NFS plus TFTP, but
haneWIN should be treated as a short-term evaluation provider, not the default
long-term operating stack. The long-term Windows Desktop direction is an
open-source provider stack such as Open DHCP Server, Tftpd64, and WinNFSd. The
most Windows Server-native route is Windows Server DHCP plus iSCSI Target, with
a third-party or carefully configured TFTP service.

## Key Sources

- Raspberry Pi network boot flow and bootloader notes:
  https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#network-booting
- Raspberry Pi bootloader TFTP prefix and PXE option settings:
  https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#raspberry-pi-bootloader-configuration
- haneWIN guide for booting Raspberry Pi from Windows:
  https://hanewin.net/rpi/remote-rpi-boot.htm
- haneWIN Raspberry Pi OS from Windows follow-up:
  https://hanewin.net/rpi/remote-rpi-boot2.htm
- Microsoft Windows Server NFS:
  https://learn.microsoft.com/en-us/windows-server/storage/nfs/deploy-nfs
- Microsoft Windows Server iSCSI Target:
  https://learn.microsoft.com/en-us/windows-server/storage/iscsi/iscsi-target-server
- Tftpd64 project:
  https://github.com/PJO2/tftpd64
- WinNFSd NFSv3 server:
  https://github.com/winnfsd/winnfsd

## Design Implications

- Do not port the old Linux tool line-by-line. It depends on `dnsmasq`,
  `nfs-kernel-server`, `/etc/exports`, `systemctl`, `netplan`, `sudo`, and POSIX
  file metadata.
- Generate Windows setup plans first. Applying DHCP/NFS/iSCSI changes should be
  an explicit later feature because a bad DHCP setup can disrupt the LAN.
- Keep haneWIN wording scoped to quick validation. It is a 30-day evaluation
  path when unregistered, while open-source/built-in providers are the planned
  operating path.
- Keep NFS and iSCSI as separate backends. NFS is closest to the old Linux flow;
  iSCSI is often cleaner on Windows Server because the Pi sees a block device.
- Root filesystem materialization must preserve Linux ownership, permissions,
  symlinks, hardlinks, and special files. Ordinary Windows extraction of an ext4
  image is not enough.
