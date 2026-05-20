# SD 카드 준비

`RPI-Netboot-Manager.exe`의 `RPi4 EEPROM SD` 버튼을 우선 사용한다. 수동 실행이 필요할 때만 아래 PowerShell 명령을 사용한다.

## 디스크 목록 확인

```powershell
.\tools\rpi-sd-card.ps1 list
```

## Pi 4 EEPROM Network Boot 이미지 받기

```powershell
.\tools\rpi-sd-card.ps1 download-eeprom-network -Model pi4
```

다운로드 캐시는 기본적으로 프로젝트 안의 `cache\downloads`에 저장한다. `RPI-Netboot-Manager.exe`의 `RPi4 EEPROM SD` 버튼도 같은 위치를 사용한다.

## Pi 4 EEPROM Network Boot SD 만들기

관리자 PowerShell에서 실행한다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\rpi-sd-card.ps1 prepare-eeprom-network -Model pi4 -DriveLetter S -IUnderstand
```

## OS 이미지 직접 쓰기

관리자 PowerShell에서 실행한다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\rpi-sd-card.ps1 write-image -DriveLetter S -Image <저장소>\downloads\raspios.img.xz -IUnderstand
```

## 안전 조건

- `-DriveLetter` 또는 `-DiskNumber`를 명시한다.
- 쓰기 작업에는 `-IUnderstand`가 필요하다.
- Windows boot/system disk에는 쓰지 않는다.
- 기본값은 USB 디스크만 허용한다.
- 기본값은 64GB 이하 디스크만 허용한다.
