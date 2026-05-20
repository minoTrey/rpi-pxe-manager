# Clone Workflow

## Current Flow

1. Use `RPi4 OS SD 작성` to write Raspberry Pi OS Lite 64-bit Trixie to the selected SD.
2. Boot the target Raspberry Pi 4 from that OS SD.
3. Confirm serial and Ethernet MAC from Raspberry Pi OS:

   ```bash
   cat /proc/cpuinfo | grep Serial
   cat /sys/class/net/eth0/address
   ```

4. If needed, update EEPROM/network boot order from the booted OS.
5. In `RPI-Netboot-Manager.exe`, run `새 RPi4 등록/복제`.
6. Restart `부팅 서비스 시작` if DHCP reservations changed.
7. Remove the SD and test Ethernet netboot.

## Notes

- The GUI default SD action is no longer EEPROM recovery image writing.
- EEPROM image creation remains available from `tools\rpi-sd-card.ps1 prepare-eeprom-network` as a CLI fallback.
- Unknown MAC candidates can be inferred from `D:\logs\rpi-boot-lite.log`; serial still needs explicit confirmation.
