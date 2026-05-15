# 프로젝트 기억장

마지막 업데이트: 2026-05-15 KST

이 문서는 중간에 전원이 꺼지거나, 여러 작업을 동시에 시키거나, 에이전트가 바뀌어도 바로 이어서 작업할 수 있게 만드는 기준 문서입니다. 다음 세션을 시작할 때는 이 파일을 먼저 읽고, 그 다음 `docs/worklog/`의 최신 파일을 읽습니다.

## 현재 한 줄 상태

RPi4는 DHCP/TFTP로 커널까지 받는 데 성공했습니다. 현재 막힌 지점은 `D:\rootfs\d80c0b88`에 실제 Linux rootfs가 비어 있어서 NFS root 마운트 뒤 init을 찾지 못하는 단계입니다.

## 반드시 기억할 결정

| 항목 | 결정 |
| --- | --- |
| 네트워크 부팅 대상 | Raspberry Pi 4만 네트워크 부팅 대상입니다. |
| Zero 2 W | 네트워크 부팅 대상이 아닙니다. SD 부팅 + USB gadget mode 장치로 준비합니다. |
| OS 계열 | RPi4와 Zero 2 W는 Raspberry Pi OS Lite 계열로 맞춥니다. 기본 후보는 64-bit Trixie입니다. |
| 서버 PC IP | 유선 이더넷은 `10.73.0.10/24`입니다. |
| 공유기 | ipTIME 관리 주소는 `10.73.0.1`입니다. |
| 저장소 | `D:` 드라이브 라벨은 `rpi`, 파일시스템은 NTFS입니다. |
| 폴더 구조 | `D:\tftp`, `D:\rootfs`, `D:\iscsi`, `D:\downloads`가 바로 보여야 합니다. `D:\rpi\rpi\...` 같은 중복 구조는 쓰지 않습니다. |
| 부팅 서비스 | haneWIN은 30일 평가판이라 기본 운영 수단으로 쓰지 않습니다. 기본 방향은 내장 DHCP/TFTP + WinNFSd 조합입니다. |
| 실행 방식 | 사용자는 PowerShell 명령을 외워서 치지 않습니다. GUI에서 더블클릭 후 버튼으로 실행합니다. |
| 문서/로그 | 상태 확인 로그는 무엇을 검사하는지 한글로 친절하게 설명해야 합니다. |
| 추적 도구 | 지금은 저장소 안 Markdown 문서를 원장으로 쓰고, GitHub가 연결되면 Issues/Projects/PR을 운영 원장으로 씁니다. Linear는 GitHub 보조 추적 도구로만 둡니다. |

## 작업 순서 타임라인

| 순서 | 시점 | 요청/상황 | 수행한 일 | 결과/상태 |
| --- | --- | --- | --- | --- |
| 1 | 2026-05-13 | Linux 전용 RPi PXE/netboot 방식을 Windows로 옮길 수 있는지 조사 | 기존 Linux 프로젝트와 인터넷 자료를 기준으로 Windows용 자동화 프로젝트 방향을 잡음 | 새 프로젝트 `rpi-netboot-windows` 시작 |
| 2 | 2026-05-13 | 기존에 만들었던 프로그램이 남아 있는지 확인 | `rpi-pxe-manager` 계열 산출물과 60대 클라이언트 정보를 확인 | 60대 클라이언트 구조를 Windows 프로젝트로 가져오는 방향 확정 |
| 3 | 2026-05-13 | ipTIME 공유기와 서버 PC 서브넷을 `10.73.0.x`로 맞춤 | 서버 PC 유선 이더넷을 `10.73.0.10`, 공유기를 `10.73.0.1` 기준으로 정리 | 서버 PC와 공유기 ping 성공 |
| 4 | 2026-05-13 | `10.73.0.10` 중복 문제 발생 | 주소 충돌 상태를 확인하고 서버 PC 고정 IP 재설정 방향으로 진행 | 최종 서버 PC IP는 `10.73.0.10` |
| 5 | 2026-05-14 | D 드라이브 경로가 `D:\rpi\rpi`처럼 중복되어 마음에 들지 않음 | 운영 루트를 `D:\`로 정리하고 주요 폴더가 바로 보이게 변경 | `D:\tftp`, `D:\rootfs`, `D:\iscsi` 구조 확정 |
| 6 | 2026-05-14 | NTFS가 필요하면 바꾸겠다고 함 | D 드라이브를 RPi 운영 저장소로 쓰기 위해 NTFS/라벨 `rpi` 기준으로 정리 | `D:`가 `rpi` NTFS 고정 디스크로 확인됨 |
| 7 | 2026-05-14 | 매번 PowerShell 명령이 아니라 자동화 프로그램이 필요함 | `tools\rpi-netboot-manager.ps1` 중심 자동화와 더블클릭 실행 파일을 구성 | CLI 자동화에서 GUI 자동화로 전환 |
| 8 | 2026-05-14 | UI가 있어야 하고 한글/도움말/아이콘/디자인 필요 | WinForms GUI `RPI-Netboot-Manager.exe` 제작, UI/UX Pro Max 기준을 적용 | 한글 GUI와 HTML 도움말 문서 추가 |
| 9 | 2026-05-14 | 한글 UI가 잘려 보이고 로그가 불친절함 | 레이아웃과 상태 점검 문구 개선 방향으로 패치 | 추가 개선 필요 항목으로 남김 |
| 10 | 2026-05-14 | haneWIN이 무엇인지, 평가판인지 확인 | haneWIN은 실제 상용 Windows DHCP/TFTP/NFS 제품이며 미등록 30일 평가판임을 확인 | 장기 운영 기본값에서 제외 |
| 11 | 2026-05-15 | haneWIN 없이 Windows에서 부팅 서비스를 제공해야 함 | C# 내장 DHCP/TFTP 서버 `RpiBootServiceLite`와 WinNFSd provider를 추가 | `무료 부팅 서비스 시작` 방향 확정 |
| 12 | 2026-05-15 | EEPROM 준비용 SD카드가 꽂혀 있음 | SD카드 목적을 RPi4 EEPROM 설정용으로 기록 | SD는 OS/rootfs 복사 대상이 아니라 EEPROM 준비 대상 |
| 13 | 2026-05-15 | RPi4에 SD카드로 EEPROM 업데이트 시도 | 초록 화면과 LED 점멸을 확인 | EEPROM 업데이트 동작으로 판단 |
| 14 | 2026-05-15 | SD카드 제거 후 전원 재연결 | RPi4가 네트워크 부팅을 시작 | EEPROM 네트워크 부팅 설정 성공 |
| 15 | 2026-05-15 | RPi4 화면에 DHCP/TFTP 정보 출력 | Pi MAC `88:a2:9e:4f:a9:b1`, serial `d80c0b88`, IP `10.73.0.155` 확인 | DHCP/TFTP 단계 성공 |
| 16 | 2026-05-15 | 커널은 뜨지만 부팅이 멈춤 | 화면 사진에서 `VFS: Unable to mount root fs via NFS`, `No working init found` 확인 | NFS/rootfs 단계가 현재 핵심 문제 |
| 17 | 2026-05-15 | NFS가 없고 haneWIN 평가판이라 불만 | haneWIN 의존을 낮추고 무료 provider를 우선하도록 조정 | 내장 DHCP/TFTP + WinNFSd가 기본 방향 |
| 18 | 2026-05-15 | 네트워크 부팅이 아직 안 됨 | `PMAPDaemon`/`pmapd` 포트 111 충돌을 피하도록 lite provider 정리 | DHCP/TFTP/NFS 리스너는 뜨는 상태까지 진전 |
| 19 | 2026-05-15 | RPi4와 Zero 2 W OS를 통일해야 함 | Zero 2 W는 SD + USB gadget, RPi4만 netboot로 역할 분리 | 문서와 자동화에서 장비 역할을 명확히 나눠야 함 |
| 20 | 2026-05-15 | 여러 작업을 많이 시켜서 순서를 잊지 않게 해야 함 | 이 작업 기억장과 상세 worklog, ADR을 추가 | 다음 세션의 시작점 생성 |
| 21 | 2026-05-15 | GitHub/Linear를 활용해 작업을 추적하고 싶음 | GitHub connector에서 기존 `minoTrey/rpi-pxe-manager` repo를 확인하고, Linear 프로젝트 `RPI Netboot Windows`를 생성 | 작업 추적을 GitHub + Linear + repo 문서 조합으로 전환 |
| 22 | 2026-05-15 | Windows판을 어디에 둘지 결정 | 새 repo를 만들지 않고 기존 `minoTrey/rpi-pxe-manager` 저장소에 `windows/` 폴더로 추가하기로 결정 | Linux판과 Windows판을 같은 repo 안에서 분리 관리 |
| 23 | 2026-05-15 | rootfs/Zero 2 W 자동화 연결 필요 | main manager에 `prepare-rpi4-rootfs`, `prepare-zero2w-gadget-sd`, `prepare-rpi4-eeprom-sd` task 추가 | GUI/CLI에서 RPi4 netboot와 Zero 2 W gadget 흐름 분리 |
| 24 | 2026-05-15 | GitHub에 Windows판 기록을 남김 | branch `agent/windows-netboot-manager`, commit `f4d89e0`, draft PR #1 생성 | PR: `https://github.com/minoTrey/rpi-pxe-manager/pull/1` |

## 현재 확정된 장비 값

| 이름 | 값 |
| --- | --- |
| 서버 PC 유선 IP | `10.73.0.10/24` |
| 공유기/ipTIME | `10.73.0.1` |
| 서버 PC MAC | `6c:4b:90:3d:08:9b` |
| 테스트 RPi4 MAC | `88:a2:9e:4f:a9:b1` |
| 테스트 RPi4 serial/TFTP prefix | `d80c0b88` |
| 테스트 RPi4 예약 IP | `10.73.0.155` |
| TFTP root | `D:\tftp` |
| 테스트 RPi4 TFTP 폴더 | `D:\tftp\d80c0b88` |
| rootfs root | `D:\rootfs` |
| 테스트 RPi4 rootfs 폴더 | `D:\rootfs\d80c0b88` |

## 현재 정상인 것

- RPi4 EEPROM은 네트워크 부팅을 시도하는 상태입니다.
- RPi4가 서버 PC에서 DHCP 응답을 받았습니다.
- RPi4가 TFTP로 커널과 부팅 파일을 받아 커널 로그까지 출력했습니다.
- 서버 PC 유선 IP와 공유기 주소가 맞습니다.
- `D:\tftp\d80c0b88`에는 부팅 파일이 들어 있습니다.
- 무료 provider 방향의 DHCP/TFTP/NFS 서비스 구성이 만들어져 있습니다.

## 현재 막힌 것

가장 중요한 blocker는 `D:\rootfs\d80c0b88`가 비어 있다는 점입니다. 커널이 NFS root를 마운트해도 `/sbin/init`, `/bin/sh`, `/usr`, `/etc` 같은 Linux rootfs 내용이 없으면 부팅할 수 없습니다.

Windows 탐색기로 rootfs를 대충 복사하면 Linux 권한, 소유자, 심볼릭 링크, 특수 파일이 깨질 수 있습니다. rootfs는 Pi 또는 Linux helper에서 `rsync -aHAXx --numeric-ids` 방식으로 채우는 쪽이 안전합니다.

추적 도구는 다음 기준으로 붙였습니다. GitHub는 기존 `minoTrey/rpi-pxe-manager` repository를 사용하고, Windows판은 그 안의 `windows/` 폴더로 분리합니다. Linear에는 `RPI Netboot Windows` 프로젝트를 만들었고 남은 작업을 이슈로 쪼갰습니다. 이 문서는 그래도 세션 복구용 원장으로 계속 유지합니다.

## 다음 작업 순서

1. `RPI-Netboot-Manager-Admin-Update.exe`를 관리자 권한으로 실행합니다.
2. `전체 상태 다시 확인`으로 DHCP/TFTP/NFS 리스너와 rootfs 상태를 확인합니다.
3. rootfs 준비 기능을 GUI에 연결합니다. 현재 후보 스크립트는 `tools\rootfs-helper.ps1`입니다.
4. 테스트 RPi4의 실제 rootfs를 `D:\rootfs\d80c0b88`에 채웁니다.
5. `D:\rootfs\d80c0b88\sbin\init` 또는 `D:\rootfs\d80c0b88\bin\sh`가 있는지 확인합니다.
6. RPi4를 SD카드 없이 다시 전원 재연결해서 NFS root 부팅을 확인합니다.
7. 성공하면 첫 RPi4를 기준 이미지로 삼아 다음 RPi4들을 복제/등록하는 GUI 흐름을 만듭니다.
8. Zero 2 W용 SD + USB gadget 준비 기능은 별도 버튼으로 분리합니다. 네트워크 부팅 흐름에 섞지 않습니다.
9. GitHub `minoTrey/rpi-pxe-manager`의 Windows branch에 변경을 commit/push하고, Linear 이슈에 진행 상황을 남깁니다.

## 에이전트/도구 운영 메모

- 에이전트들이 조사한 결론은 이 파일에 합쳐서 기록합니다.
- 상세 작업 기록은 `docs/worklog/YYYY-MM-DD-주제.md`에 남깁니다.
- 중요한 방향 결정은 `docs/decisions/ADR-번호-주제.md`에 남깁니다.
- GitHub repository: `minoTrey/rpi-pxe-manager`
- Windows판 위치: `windows/`
- GitHub branch: `agent/windows-netboot-manager`
- GitHub draft PR: `https://github.com/minoTrey/rpi-pxe-manager/pull/1`
- First Windows commit: `f4d89e0`
- Linear project: `RPI Netboot Windows`
- Linear issues:
  - `3D-5`: P0 rootfs 채우기
  - `3D-6`: rootfs 준비를 Windows manager/GUI에 연결
  - `3D-7`: Zero 2 W SD boot + USB gadget 흐름 분리
  - `3D-8`: 기존 `rpi-pxe-manager` repo에 Windows판 추가
