# RPI Netboot Manager 자동화 기준

이 프로젝트의 사용 방식은 다음으로 고정한다.

```text
Codex가 구조와 자동화 프로그램을 만든다.
사용자는 RPI-Netboot-Manager.exe를 더블클릭해서 버튼을 누른다.
반복 작업은 GUI 버튼과 작업 모드로 남긴다.
```

## 실행 파일

한글 GUI 실행파일:

```text
RPI-Netboot-Manager.exe
```

일반 exe는 UAC 없이 열린다. 관리자 권한이 필요한 버튼을 누르면 같은 exe가 UAC로 다시 열린다.

## GUI 작업 버튼

```text
상태 확인
서버 PC 준비
부팅 서비스 시작
새 RPi4 등록/복제
RPi4 OS SD 작성
Zero 2 W Gadget SD
도움말
```

## 권장 실행 순서

1. `RPI-Netboot-Manager.exe` 실행
2. `상태 확인`으로 현재 PC 상태 확인
3. 문제가 있으면 `서버 PC 준비` 버튼으로 Windows 서버 PC 준비
4. `부팅 서비스 시작` 버튼으로 RPi4 부팅 서비스 실행
5. `RPi4 OS SD 작성`으로 새 Pi 첫 부팅 리포터 포함 OS SD 작성
6. 새 RPi4를 OS SD로 부팅해 serial/MAC/IP 자동 수집
7. `새 RPi4 등록/복제`에서 감지된 값을 확인하고 기기 번호 지정
8. SD를 제거한 뒤 새 RPi4 전원을 다시 넣어 네트워크 부팅 확인
9. 필요하면 `Zero 2 W Gadget SD` 실행

## 자동화된 항목

- 설정된 저장소 루트가 존재하고 쓰기 가능한지 확인
- SD카드가 `S:`로 밀려 있는지 확인/복구
- 서버 PC 이더넷을 `10.73.0.10/24`로 설정
- `<저장소>\tftp`, `<저장소>\rootfs`, `<저장소>\downloads` 폴더 확인
- `lab-10.73.json`의 등록 RPi4 확인
- TFTP `cmdline.txt/config.txt` 검사
- Windows 방화벽 규칙 적용
- 프로젝트 캐시의 Raspberry Pi OS Lite 64-bit Trixie 2026-04-21 이미지 확인
- 선택한 SD카드에 OS 이미지 쓰기 및 검증
- 내장 DHCP/TFTP 서버 `RpiBootServiceLite.exe` 빌드
- rootfs 서비스 시작
- 새 RPi4 bootfs/rootfs 복제와 client metadata 생성
- Raspberry Pi MAC OUI discovery lease와 첫 부팅 provisioning report 수신

## 프로그램 작업 모드

메뉴 없이 작업만 실행할 수도 있다.

```powershell
.\tools\rpi-netboot-manager.ps1 -Task status
.\tools\rpi-netboot-manager.ps1 -Task verify
```

관리자 권한 작업은 `RPI-Netboot-Manager.exe`에서 버튼을 누르면 UAC로 다시 열린다.
