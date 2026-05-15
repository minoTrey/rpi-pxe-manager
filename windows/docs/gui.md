# GUI 프로그램

`RPI-Netboot-Manager.exe`는 더블클릭해서 사용하는 한글 Windows GUI 프로그램이다.

일반 exe는 상태 확인과 문서 열기를 일반 권한으로 수행한다. 관리자 권한이 필요한 작업을 누르면 `RPI-Netboot-Manager-Admin.exe`로 다시 열도록 안내한다.

## 화면 구성

- 왼쪽: 작업 단계 버튼
- 상단: 현재 운영 기준 요약
- 중앙: 선택한 작업 설명과 실행 버튼
- 오른쪽: 도움말
- 하단: 실행 로그

## 주요 버튼

- `상태 확인`: D: 저장소, S: SD카드, 이더넷, 공유기, 서비스 포트 상태 확인
- `서버 PC 자동 준비`: 드라이브 문자, 이더넷 IP, D:\ 폴더 구조, lab 설정, generated 파일 정리
- `무료 부팅 서비스 시작`: 내장 DHCP/TFTP 서버와 무료 WinNFSd 시작. haneWIN 없이 테스트할 기본 provider다.
- `무료 부팅 서비스 중지`: 내장 DHCP/TFTP 서버와 WinNFSd 중지
- `haneWIN 평가판 설치`: haneWIN DHCP/TFTP/NFS 설치 시도. 30일 평가판이므로 빠른 비교/검증용으로만 본다.
- `haneWIN 설정 적용`: haneWIN을 이더넷 전용 DHCP, TFTP root, NFS export, Pi 예약 IP로 맞춤
- `SD카드에 EEPROM 쓰기`: S: SD카드에 Pi 4 Network Boot EEPROM 이미지 쓰기
- `첫 Pi 부팅파일 복사`: Raspberry Pi OS boot 파티션 파일을 현재 테스트 Pi의 TFTP 폴더로 복사
- `전체 상태 다시 확인`: 서버/서비스/TFTP 파일 상태 점검. 파일 복사는 하지 않는다.
- `TFTP 파일 복사/검증`: generated TFTP 파일을 D:\tftp로 동기화하고 깨짐 검사
- `부팅 포트 방화벽 열기`: DHCP/TFTP/NFS/iSCSI 포트 허용
- `이더넷을 DHCP로 복구`: 유선 이더넷을 DHCP로 되돌림
- `도움말 문서 열기`: docs 폴더 열기

## 권장 순서

1. `상태 확인`
2. 문제가 있으면 `서버 PC 자동 준비`
3. `무료 부팅 서비스 시작`
4. `SD카드에 EEPROM 쓰기`
5. `첫 Pi 부팅파일 복사`
6. `전체 상태 다시 확인`

첫 Pi의 boot partition 파일과 rootfs 복제는 아직 별도 절차다. 이 부분은 `docs\rpi4-netboot-manager.md`를 따른다.

## Provider 안내 문구 기준

- haneWIN은 “빠른 검증용 provider”로 설명한다.
- haneWIN은 미등록 상태에서 30일 평가판이므로 장기 운영 기본 솔루션처럼 표현하지 않는다.
- 기본 테스트 provider는 `무료 부팅 서비스 시작`으로 설명한다.
- 버튼이나 도움말에서는 “무료 provider 우선, haneWIN은 비교/검증용” 흐름을 유지한다.

## 디자인 기준

UI는 `ui-ux-pro-max` 기준에서 운영 도구에 맞춰 정보 밀도, 상태 가시성, 실수 방지를 우선한다.

- 과한 랜딩 화면 없이 바로 작업 화면 진입
- 버튼은 단계별 작업으로 배치하고, 버튼명은 `동사 + 대상`으로 작성
- 위험 작업은 대상과 결과를 명시한 확인창 표시
- 색상만으로 위험도를 전달하지 않고 `안전`, `주의`, `위험` 문구를 함께 표시
- 좌측 작업 버튼은 키보드 Enter/Space와 포커스 표시 지원
- 주요 버튼 높이는 48px로 통일
- 실행 결과는 하단 로그에 누적
- 색상은 어두운 사이드바, 밝은 본문, 청록색 액션, 주황색 위험 액션으로 구분
- 아이콘은 앱 아이콘과 좌측 작업 아이콘에 적용

## 빌드

GUI 소스:

```text
gui\RpiNetbootManagerGui.cs
```

아이콘:

```text
gui\rpi-netboot.ico
```

다시 빌드:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\gui\build-gui.ps1
```
