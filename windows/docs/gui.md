# GUI 프로그램

`RPI-Netboot-Manager.exe`는 더블클릭해서 사용하는 한글 Windows GUI 프로그램이다.

상태 확인과 도움말 열기는 일반 권한으로 수행한다. 관리자 권한이 필요한 작업을 누르면 같은 `RPI-Netboot-Manager.exe`가 UAC를 통해 관리자 권한으로 다시 열린다.

## 화면 구성

- 왼쪽: 작업 단계 버튼
- 상단: 현재 운영 기준 요약
- 중앙: 선택한 작업 설명과 실행 버튼
- 오른쪽: 도움말
- 하단: 실행 로그

## 주요 버튼

- `상태 확인`: 설정된 저장소, S: SD카드, 이더넷, 공유기, 서비스 포트 상태 확인
- `서버 PC 준비`: 저장소 폴더 구조, 이더넷 IP, lab 설정 확인
- `부팅 서비스 시작`: RPi4 네트워크 부팅에 필요한 DHCP/TFTP/rootfs 서비스를 시작
- `새 RPi4 등록/복제`: OS SD 첫 부팅 리포트에서 감지된 serial/MAC/IP를 확인해 새 RPi4 bootfs/rootfs 생성
- `RPi4 OS SD 작성`: 선택한 물리 SD 디스크에 Raspberry Pi OS Lite 64-bit Trixie 2026-04-21 이미지와 첫 부팅 자동 등록 리포터 쓰기
- `Zero 2 W Gadget SD`: S: SD카드를 Zero 2 W USB Ethernet gadget 부팅용으로 패치
- `도움말`: 운영 절차와 복제 Runbook 열기

## 작업 흐름

1. `상태 확인`
2. 문제가 있으면 `서버 PC 준비`
3. `부팅 서비스 시작`
4. 필요한 경우 `RPi4 OS SD 작성`
5. OS SD로 새 RPi4를 부팅하고 provisioning report 수신
6. `새 RPi4 등록/복제`
6. 필요한 경우 `Zero 2 W Gadget SD`

진단용 provider와 과거 실패 기록은 `docs/`, `knowledge/`에 보존하지만 실행파일 표면에는 운영자가 눌러야 하는 흐름만 둔다.

## 디자인 기준

UI는 `ui-ux-pro-max` 기준에서 운영 도구에 맞춰 정보 밀도, 상태 가시성, 실수 방지를 우선한다.

- 과한 랜딩 화면 없이 바로 작업 화면 진입
- 왼쪽은 작업 선택만 두고, 내부 설명성 문구는 본문 안내로 이동
- 버튼은 실행 대상이 드러나도록 작성
- 위험 작업은 대상과 결과를 명시한 확인창 표시
- 색상만으로 위험도를 전달하지 않고 `안전`, `주의`, `위험` 문구를 함께 표시
- 좌측 작업 버튼은 키보드 Enter/Space와 포커스 표시 지원
- 주요 버튼 높이는 44px 이상으로 유지
- 실행 결과는 하단 로그에 누적
- 색상은 밝은 사이드바, 밝은 본문, 청록색 액션, 주황색 위험 액션으로 구분
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
