# RPI Netboot Windows

Windows PC에서 Raspberry Pi 4 네트워크 부팅 서버를 준비하고 관리하는 자동화 프로젝트입니다.

사용 방식은 단순합니다.

```text
Codex는 자동화 프로그램과 구조를 만든다.
사용자는 RPI-Netboot-Manager.exe를 더블클릭해서 버튼을 누른다.
```

## 시작

한글 GUI 프로그램:

```text
RPI-Netboot-Manager.exe
```

일반 상태 확인과 문서 확인은 이 파일로 바로 실행합니다. 서버 설정, SD카드 쓰기, 방화벽처럼 관리자 권한이 필요한 버튼을 누르면 관리자 모드로 다시 열도록 안내합니다.

관리자 모드가 바로 필요하면 아래 파일을 실행합니다.

```text
RPI-Netboot-Manager-Admin.exe
```

## 처음 사용하는 순서

```text
1. 상태 확인
2. 서버 PC 자동 준비
3. 무료 부팅 서비스 시작
4. SD카드에 EEPROM 쓰기
5. 첫 Pi 부팅파일 복사
6. 전체 상태 다시 확인
```

현재 기본 테스트 provider는 `무료 부팅 서비스 시작`입니다. 이 버튼은 프로젝트 안의 작은 DHCP/TFTP 서버를 빌드하고, 무료 WinNFSd로 `D:\rootfs`를 `/rpi`로 공유합니다.

`haneWIN 평가판 설치` 버튼은 빠른 비교/검증용 provider입니다. haneWIN은 실제 제품이고 미등록 상태에서 30일 평가판으로 동작하므로, 장기 운영 기본 솔루션처럼 보거나 문서화하지 않습니다.

아직 실제 Pi 네트워크 부팅까지는 첫 Pi의 boot files와 rootfs를 채워야 합니다. GUI는 현재 PC/저장소/서비스 준비와 검증을 우선 자동화합니다.

## 현재 운영 기준

```text
서버 PC 이더넷: 10.73.0.10/24
ipTIME/router:  10.73.0.1
저장소 드라이브: rpi (D:)
TFTP root:      D:\tftp
rootfs root:    D:\rootfs
downloads:      D:\downloads
SD 카드:        S:
```

## 주요 화면

```text
상태 확인
서버 PC 자동 준비
무료 부팅 서비스 시작
무료 부팅 서비스 중지
haneWIN 평가판 설치
haneWIN 설정 적용
SD카드에 EEPROM 쓰기
첫 Pi 부팅파일 복사
전체 상태 다시 확인
TFTP 파일 복사/검증
부팅 포트 방화벽 열기
이더넷을 DHCP로 복구
도움말 문서 열기
```

## 문서

- `docs\project-memory.md`: 작업 순서, 현재 상태, 다음 단계 원장
- `docs\worklog\2026-05-15-rpi4-netboot.md`: 2026-05-15 상세 작업 로그
- `docs\decisions\ADR-0001-project-memory-and-tracking.md`: 작업 기억장과 추적 방식 결정 기록
- `docs\project-tracking-recommendation.md`: GitHub/Linear/Notion 기반 프로젝트 추적 추천
- `docs\gui.md`: GUI 프로그램 설명
- `docs\ui-ux-design-system.md`: UI/UX Pro Max 적용 기준
- `docs\automation.md`: 자동화 프로그램 기준
- `docs\progress-and-usage.md`: 현재 진행상황과 사용법
- `docs\sd-card-prep.md`: SD 카드 준비 프로그램
- `docs\rpi4-netboot-manager.md`: 첫 Pi 네트워크 부팅 절차
- `docs\system-scorecard.md`: 준비도와 리스크
- `docs\windows-service-providers.md`: haneWIN/오픈소스/Windows Server provider 비교
