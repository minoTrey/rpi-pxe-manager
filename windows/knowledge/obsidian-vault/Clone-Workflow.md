# Clone Workflow

## Current Flow

1. Use `RPi4 OS SD 작성` to write Raspberry Pi OS Lite 64-bit Trixie to the selected SD.
2. Boot the target Raspberry Pi 4 from that OS SD.
3. `RpiBootServiceLite` assigns a temporary discovery lease to Raspberry Pi MAC OUIs from `10.73.0.180`-`10.73.0.199`.
4. The OS SD cloud-init reporter posts serial, Ethernet MAC, IP, model, EEPROM `BOOT_ORDER`, and short EEPROM status to `http://10.73.0.10:8088/provision/report`.
5. In `RPI-Netboot-Manager.exe`, run `새 RPi4 등록/복제`. The newest report from `D:\logs\rpi-provisioning.jsonl` pre-fills serial, MAC, and IP.
6. Confirm the values, choose the device id, and run the clone.
7. Restart `부팅 서비스 시작` if DHCP reservations changed.
8. Remove the SD and test Ethernet netboot.

## Notes

- The GUI default SD action is no longer EEPROM recovery image writing.
- EEPROM image creation remains available from `tools\rpi-sd-card.ps1 prepare-eeprom-network` as a CLI fallback.
- Current SD cards written before the provisioning change must be re-written before they can report serial automatically.
