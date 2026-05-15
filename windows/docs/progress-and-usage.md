# 진행상황과 사용법

## 현재 기준

- 프로젝트: `C:\Users\test\Documents\workspace\rpi-netboot-windows`
- 운영 저장소: `D:\`
- RPi 저장소 디스크: `D:` / 라벨 `rpi` / `NTFS`
- EEPROM 또는 OS 준비용 SD카드: `S:` 로 두는 것을 기준으로 함
- 서버 PC 유선 IP: `10.73.0.10/24`
- ipTIME 관리 IP: `10.73.0.1`
- Wi-Fi는 인터넷용, 유선 이더넷은 Pi 부팅망 전용
- 등록된 Raspberry Pi 클라이언트: 60대
- 네트워크 부팅 대상: RPi4만 해당
- Zero 2 W 기준: SD 부팅 + USB gadget mode, RPi4 netboot 흐름과 분리

## 만들어진 것

- 기존 Linux 프로젝트 `rpi-pxe-manager`에서 60대 클라이언트 정보를 가져옴
- `lab-10.73.json`을 `10.73.0.0/24`와 `D:\` 기준으로 재생성함
- `generated\lab-10.73` 산출물을 재생성함
- `D:\tftp\<serial>` 60개 생성
- `D:\rootfs\<serial>` 60개 생성
- 전원 꺼짐 뒤 SD카드가 `D:`를 차지하는 문제를 복구하기 위한 스크립트 추가
- Raspberry Pi Imager 대신 쓸 SD 카드 준비 프로그램 추가: `tools\rpi-sd-card.ps1`
- 한글 GUI 자동화 프로그램 추가: `RPI-Netboot-Manager.exe`, `RPI-Netboot-Manager-Admin.exe`
- haneWIN 평가판 의존을 줄이기 위한 무료 Lite provider 추가: 내장 DHCP/TFTP + WinNFSd
- 테스트 RPi4 `d80c0b88`가 DHCP/TFTP로 커널까지 받는 것 확인
- 인터럽트 복구용 작업 기억장 추가: `docs\project-memory.md`
- GitHub 기존 repo `minoTrey/rpi-pxe-manager`에 Windows판을 `windows/` 폴더로 추가하는 방향 확정
- Linear 프로젝트 `RPI Netboot Windows`와 이슈 `3D-5`~`3D-8` 생성
- main manager task 추가: `prepare-rpi4-eeprom-sd`, `prepare-rpi4-rootfs`, `prepare-zero2w-gadget-sd`
- GUI 버튼 추가: `rootfs 상태 확인`, `rootfs 준비 안내 만들기`, `Zero 2 W gadget SD`
- GitHub/Linear 운영 방침 문서화: GitHub Issues/Projects/PR을 주 추적 체계로 쓰고 Linear는 보조로 둠
- GitHub는 기존 `minoTrey/rpi-pxe-manager` repo를 사용하고 Windows판은 `windows/` 폴더로 분리하기로 결정

## 전원 복귀 후 먼저 할 일

`RPI-Netboot-Manager.exe`를 실행하고 `상태 확인` 버튼으로 상태를 본다. 문제가 있으면 `서버 PC 자동 준비` 버튼으로 서버 PC 준비를 다시 실행한다.

정상 기대값:

- `D:`가 `rpi NTFS Fixed`
- SD카드는 `S:` 또는 다른 이동식 드라이브
- 이더넷 IP가 `10.73.0.10`
- `10.73.0.1` ping 성공
- `D:\tftp`, `D:\rootfs`, `D:\iscsi` 존재

## 아직 안 된 것

- 첫 번째 Pi의 rootfs를 `D:\rootfs\d80c0b88`에 복사하기
- rootfs 안에 `sbin\init` 또는 `bin\sh`가 있는지 검증
- rootfs 준비 기능을 GUI 버튼과 상태 점검에 연결한 뒤 실제 장비 복제까지 검증
- 실제 Pi 1대가 NFS rootfs까지 마운트해서 완전 부팅되는지 검증
- Zero 2 W SD + USB gadget 준비 기능을 RPi4 netboot 흐름과 분리해서 정리
- Pi 부팅 후 카메라 검증
- GitHub branch에 Windows판을 commit/push하고 Linear 이슈에 진행 상황 남기기

참고: 기본 테스트 provider는 `무료 부팅 서비스 시작`이다. haneWIN은 빠른 비교/검증용 provider로만 본다. 미등록 상태에서는 30일 평가판이므로 장기 운영 기본 솔루션으로 안내하지 않는다.

## 다음 테스트 순서

1. `RPI-Netboot-Manager.exe`에서 `상태 확인`으로 PC 상태 확인
2. 문제가 있으면 `서버 PC 자동 준비`
3. `무료 부팅 서비스 시작`으로 내장 DHCP/TFTP + WinNFSd provider 실행
4. `SD카드에 EEPROM 쓰기`
5. 첫 Pi를 SD카드로 부팅해서 serial, MAC, EEPROM boot order 확인
6. 첫 Pi의 boot partition 파일을 `D:\tftp\d80c0b88`에 채움
7. 첫 Pi의 rootfs를 `D:\rootfs\d80c0b88`에 Linux helper로 복제
8. `전체 상태 다시 확인`
9. 첫 Pi 한 대만 전원 투입해서 DHCP/TFTP/NFS 순서로 확인

현재 1~6번은 상당 부분 진행됐다. 지금 집중할 일은 7번 rootfs 복제다.

운영 추적은 GitHub `minoTrey/rpi-pxe-manager`, Linear `RPI Netboot Windows`, 그리고 이 저장소 안 문서를 함께 사용한다. 실제 장비 상태는 외부 이슈보다 `docs\current-test-status-ko.md`를 우선한다.

## SD 카드 준비

`RPI-Netboot-Manager.exe`에서 `SD카드에 EEPROM 쓰기` 버튼을 누른다. 확인창에서 대상이 `S:` SD카드인지 확인한다.

## 관리자 팝업이 필요한 작업

다음 작업은 UAC 팝업에서 사용자가 `예`를 눌러야 완료된다.

`RPI-Netboot-Manager.exe`에서 `서버 PC 자동 준비`, `무료 부팅 서비스 시작`, `SD카드에 EEPROM 쓰기`, `부팅 포트 방화벽 열기`, `이더넷을 DHCP로 복구` 버튼을 누른다.

## 주의

Windows Explorer로 Linux rootfs를 복사하면 권한, 소유자, 심볼릭 링크가 깨질 수 있다. rootfs는 Pi 또는 Linux helper에서 `rsync`와 NFS를 통해 복사하는 방식을 우선 사용한다.
