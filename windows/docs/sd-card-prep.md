# SD 카드 준비 프로그램

이 프로젝트는 Raspberry Pi Imager를 수동으로 누르는 대신, Windows PowerShell 프로그램으로 SD카드를 준비한다.

## 현재 구현된 명령

디스크 목록 확인:

```powershell
cd C:\Users\test\Documents\workspace\rpi-netboot-windows
.\rpi-win-netboot.ps1 sd-list
```

Pi 4 EEPROM Network Boot 이미지만 공식 Raspberry Pi 목록에서 다운로드:

```powershell
.\rpi-win-netboot.ps1 sd-download-eeprom-network -PiModel pi4
```

Pi 4 EEPROM Network Boot SD카드 굽기:

```powershell
.\tools\rpi-sd-card-admin.bat prepare-eeprom-network -Model pi4 -DriveLetter S -IUnderstand
```

직접 받은 OS 이미지 굽기:

```powershell
.\tools\rpi-sd-card-admin.bat write-image -DriveLetter S -Image D:\downloads\raspios.img.xz -IUnderstand
```

## 안전장치

- `-DriveLetter` 또는 `-DiskNumber`를 명시해야 한다.
- `-IUnderstand`가 없으면 쓰지 않는다.
- Windows boot/system disk에는 쓰지 않는다.
- 기본적으로 USB 디스크만 허용한다.
- 기본적으로 64GB보다 큰 디스크에는 쓰지 않는다.
- `D:`의 `rpi` SSD는 119GB라서 기본 안전장치에 걸린다.

## 현재 PC 기준

현재 `sd-list`에서 기대하는 대상은 다음과 같다.

```text
Disk 2: Generic STORAGE DEVICE, USB, about 29.72 GB, S:
```

`D:`는 서버 저장소 SSD이므로 절대 SD 굽기 대상으로 쓰면 안 된다.

## 공식 이미지 출처

프로그램은 Raspberry Pi Imager가 사용하는 공식 목록을 읽는다.

- `https://downloads.raspberrypi.com/os_list_imagingutility_v4.json`
- Pi 4 Network Boot 항목: `Misc utility images > Bootloader (Pi 4 family) > Network Boot`

현재 확인된 Pi 4 network bootloader 이미지는 `2026-01-09` 릴리스다.
