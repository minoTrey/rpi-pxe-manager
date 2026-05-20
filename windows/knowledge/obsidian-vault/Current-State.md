# Current State

Updated: 2026-05-20 14:25 KST

## Active Workspace

Use this project folder:

```text
C:\Users\test\Documents\workspace\rpi-pxe-manager\windows
```

Use this executable:

```text
C:\Users\test\Documents\workspace\rpi-pxe-manager\windows\RPI-Netboot-Manager.exe
```

Do not use `C:\Users\test\Documents\workspace\rpi-netboot-windows` for active work. It is a legacy snapshot. Its old launcher exe was removed locally; the folder is only reference material.

## Lab

- Server PC: `10.73.0.10/24`
- Router: `10.73.0.1`
- Current storage root: `D:\`
- TFTP root: `D:\tftp`
- Rootfs root: `D:\rootfs`
- Downloads/cache for EEPROM images: `windows\cache\downloads`
- Known-good RPi4 MAC: `88:a2:9e:4f:a9:b1`
- Known-good RPi4 serial: `d80c0b88`
- Known-good RPi4 IP: `10.73.0.155`
- Golden bootfs: `D:\tftp\d80c0b88`
- Golden rootfs: `D:\rootfs\d80c0b88`

## Latest Stable Verdict

```text
BOOT_REACHED_USERSPACE
provider: haneWIN
confidence: high
attempt: 20260519-144335-d80c0b88-hanewin-systemd-explicit
```

Interpretation:

- The first Raspberry Pi 4 reached userspace from the Windows-hosted bootfs/rootfs pair.
- This proves the lab network, EEPROM setting, TFTP prefix, bootfs, rootfs, and minimal NFS root command line are coherent.
- haneWIN remains proof-only and must not be treated as the production provider.

## 2026-05-20 UI And Packaging State

The WinForms GUI was cleaned again after user feedback.

- Removed sidebar `권장 순서` and `자동화 UI 빌드`.
- Removed haneWIN/evaluation/provider experiment wording from the executable-facing UI.
- Improved the visual hierarchy, spacing, button sizes, and font fallback.
- Font fallback order is now Pretendard, Noto Sans KR, Noto Sans CJK KR, 맑은 고딕, Malgun Gothic, Segoe UI.
- The GUI exposes storage selection; storage is not assumed to always be `D:\`.
- Help/document buttons were collapsed into one `도움말` action.
- Build output is only `RPI-Netboot-Manager.exe`; admin/bat launcher clutter was removed.

Verification:

- `windows\gui\build-gui.ps1` succeeded.
- Actual GUI screenshot check passed for the clone screen with no obvious text clipping/overlap.
- Recursive executable/batch check across active + legacy workspace found only:
  `C:\Users\test\Documents\workspace\rpi-pxe-manager\windows\RPI-Netboot-Manager.exe`

## EEPROM SD State

The Pi 4 Network Boot EEPROM image is cached inside the project:

```text
windows\cache\downloads\rpi-boot-eeprom-recovery-2026-01-09-2711-vl805-000138c0-network\
```

Image hash:

```text
SHA256 43639F3D17C53D47C1E54D6B6C9229BB095014A15A93BD948717B45343EA22F7
```

Current SD observation before writing:

```text
Disk 3
Generic STORAGE DEVICE
USB
29.72 GB
S: bootfs FAT32, about 504 MB
not boot/system
```

Important: `S:` currently looks like a Raspberry Pi OS bootfs card, not an empty EEPROM card. Running `RPi4 EEPROM SD` will erase the whole 29.72 GB card.

## Clone Flow

Current implementation still needs manual serial and MAC input.

Recommended operator flow:

1. Use `RPi4 EEPROM SD` to write the Pi 4 network boot EEPROM SD.
2. Boot the target RPi4 once from that EEPROM SD.
3. Power off and remove the SD after EEPROM update.
4. Confirm the target Pi serial and MAC.
   - Serial: `cat /proc/cpuinfo | grep Serial`; use the last 8 hex chars.
   - MAC: `cat /sys/class/net/eth0/address`.
   - The DHCP/TFTP log can reveal unknown MACs, but not reliably the serial.
5. In GUI, run `새 RPi4 등록/복제`.
6. Enter device id, serial, MAC, optional IP.
7. Run `부팅 서비스 시작` again so DHCP reservations reload.
8. Boot the new RPi4 with SD removed and Ethernet connected.

Potential next UX improvement:

- Parse `D:\logs\rpi-boot-lite.log` for `DHCP ignored unknown MAC ...`.
- Show unknown MAC candidates in the clone dialog.
- Serial still needs user confirmation unless the Pi reports it through a booted OS or a future provisioning helper.

## Next Move

1. Decide whether the current `S:` 29.72 GB bootfs SD may be erased for EEPROM writing.
2. If yes, run the GUI `RPi4 EEPROM SD` flow and verify byte-for-byte write.
3. Confirm target RPi4 serial/MAC.
4. Register and clone a new RPi4 from golden `d80c0b88`.
5. Restart boot services and test SD-less network boot.
