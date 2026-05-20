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

일반 상태 확인과 문서 확인은 이 파일로 바로 실행합니다. 서버 설정, SD카드 쓰기, 방화벽처럼 관리자 권한이 필요한 버튼을 누르면 같은 실행파일이 관리자 권한으로 다시 열립니다.

## 처음 사용하는 순서

```text
1. 상태 확인
2. 서버 PC 준비
3. 부팅 서비스 시작
4. RPi4 OS SD 작성
5. 새 RPi4 등록/복제
6. Zero 2 W Gadget SD
7. 도움말
```

첫 RPi4는 네트워크 부팅 성공 상태까지 검증되었습니다. 새 장비는 `RPi4 OS SD 작성`으로 만든 첫 부팅 리포터 포함 OS SD에서 serial/MAC/IP를 자동 수집한 뒤, `새 RPi4 등록/복제` 흐름으로 bootfs/rootfs와 내부 설정을 만듭니다.

## 현재 운영 기준

```text
서버 PC 이더넷: 10.73.0.10/24
ipTIME/router:  10.73.0.1
저장소 루트:     GUI의 저장소 설정에서 선택
TFTP root:      <저장소>\tftp
rootfs root:    <저장소>\rootfs
downloads:      windows\cache\downloads
SD 카드:        물리 디스크 선택
```

## 주요 화면

```text
상태 확인
서버 PC 준비
부팅 서비스 시작
새 RPi4 등록/복제
RPi4 OS SD 작성
Zero 2 W Gadget SD
도움말
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
- `docs\windows-service-providers.md`: provider 비교와 진단 기록
