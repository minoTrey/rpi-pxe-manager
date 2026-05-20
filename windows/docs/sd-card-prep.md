# SD 카드 준비

현재 GUI의 기본 SD 작업은 EEPROM SD가 아니라 Raspberry Pi OS SD 작성이다.

`RPI-Netboot-Manager.exe`에서 `RPi4 OS SD 작성`을 누르면 물리 디스크 선택 창이 열리고, 선택한 SD 전체에 아래 고정 이미지를 쓴다.

```text
windows\cache\downloads\2026-04-21-raspios-trixie-arm64-lite.img
Raspberry Pi OS Lite 64-bit Trixie
```

## 디스크 목록 확인

```powershell
.\tools\rpi-sd-card.ps1 list
```

## Raspberry Pi OS Lite Trixie SD 만들기

관리자 PowerShell에서 수동 실행할 때:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\rpi-sd-card.ps1 prepare-rpios-lite-trixie -DiskNumber <번호> -IUnderstand
```

이미지는 기본적으로 프로젝트 안의 `cache\downloads`에 저장한다. `D:\downloads`에는 다운로드 파일을 남기지 않는다.

## Pi 4 EEPROM Network Boot SD 만들기

EEPROM SD 작성은 더 이상 GUI 기본 흐름이 아니다. 필요할 때만 CLI 고급 작업으로 실행한다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\rpi-sd-card.ps1 prepare-eeprom-network -Model pi4 -DiskNumber <번호> -IUnderstand
```

## 안전 조건

- `-DriveLetter` 또는 `-DiskNumber`를 명시한다.
- 쓰기 작업에는 `-IUnderstand`가 필요하다.
- Windows boot/system disk에는 쓰지 않는다.
- 기본값은 USB 디스크만 허용한다.
- 기본값은 64GB 이하 디스크만 허용한다.
