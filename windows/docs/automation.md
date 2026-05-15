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

관리자 권한이 필요한 작업을 바로 시작할 때 쓰는 GUI:

```text
RPI-Netboot-Manager-Admin.exe
```

일반 exe는 UAC 없이 열린다. 관리자 권한이 필요한 버튼을 누르면 관리자 exe로 다시 열도록 안내한다.

## GUI 작업 버튼

```text
상태 확인
서버 PC 자동 준비
무료 부팅 서비스 시작
무료 부팅 서비스 중지
haneWIN 평가판 설치
SD카드에 EEPROM 쓰기
전체 상태 다시 확인
TFTP 파일 복사/검증
부팅 포트 방화벽 열기
이더넷을 DHCP로 복구
도움말 문서 열기
```

## 권장 실행 순서

1. `RPI-Netboot-Manager.exe` 실행
2. `상태 확인`으로 현재 PC 상태 확인
3. 문제가 있으면 `서버 PC 자동 준비` 버튼으로 Windows 서버 PC 준비
4. `무료 부팅 서비스 시작` 버튼으로 내장 DHCP/TFTP + WinNFSd provider 실행
5. `SD카드에 EEPROM 쓰기` 버튼으로 Raspberry Pi 4 Network Boot EEPROM SD카드 준비
6. SD카드로 첫 Pi를 부팅해 EEPROM, serial, MAC 확인
7. 첫 Pi의 boot partition 파일을 `D:\tftp\<serial>`에 채움
8. 첫 Pi의 rootfs를 `D:\rootfs\<serial>`에 채움
9. `전체 상태 다시 확인` 버튼으로 서비스와 파일 상태 검증
10. Pi 한 대만 네트워크 부팅 테스트

## 자동화된 항목

- `D:`가 `rpi` NTFS 저장소인지 확인
- SD카드가 `S:`로 밀려 있는지 확인/복구
- 서버 PC 이더넷을 `10.73.0.10/24`로 설정
- `D:\tftp`, `D:\rootfs`, `D:\iscsi`, `D:\downloads` 폴더 생성
- 기존 Linux `clients_backup.json`에서 60대 클라이언트 가져오기
- `lab-10.73.json` 재생성
- `generated\lab-10.73` 재생성
- `D:\tftp`로 generated TFTP 파일 동기화
- TFTP `cmdline.txt/config.txt` 깨짐 검사. `전체 상태 다시 확인`은 복사 없이 읽기 검증만 수행한다.
- Windows 방화벽 규칙 적용
- Raspberry Pi 공식 목록에서 Pi 4 Network Boot EEPROM 이미지 다운로드
- SD카드에 EEPROM 이미지 쓰기 및 검증
- 내장 DHCP/TFTP 서버 `RpiBootServiceLite.exe` 빌드
- WinNFSd 다운로드 및 `D:\rootfs` -> `/rpi` 공유 시작
- haneWIN DHCP/TFTP/NFS 서버 도구 winget 설치 시도. haneWIN은 빠른 검증용이다.

## 아직 프로그램화가 더 필요한 항목

현재 기본 테스트 provider는 무료 Lite provider다. haneWIN은 미등록 상태에서 30일 평가판으로 동작하므로 장기 운영 기본값으로 고정하지 않는다.

사용자에게는 다음처럼 안내한다. “기본 테스트는 무료 부팅 서비스 시작으로 진행합니다. haneWIN은 DHCP/TFTP/NFS 흐름을 비교 확인하기 위한 30일 평가판 provider입니다.”

- DHCP/TFTP 설정 참고: `generated\lab-10.73\windows\hanewin-dhcp-profile.md`
- NFS export 설정: `generated\lab-10.73\windows\hanewin-nfs-exports.txt`
- provider 후보 정리: `docs\windows-service-providers.md`

다음 개발 목표는 무료 Lite provider를 서비스화하고, Open DHCP Server + Tftpd64 + WinNFSd 조합과 Windows 내장/서버 provider를 선택형으로 다듬는 것이다.

## 프로그램 작업 모드

메뉴 없이 작업만 실행할 수도 있다.

```powershell
.\tools\rpi-netboot-manager.ps1 -Task status
.\tools\rpi-netboot-manager.ps1 -Task verify
.\tools\rpi-netboot-manager.ps1 -Task sync-tftp
```

관리자 권한 작업은 `RPI-Netboot-Manager-Admin.exe`에서 메뉴로 실행하는 것을 기본으로 한다.
