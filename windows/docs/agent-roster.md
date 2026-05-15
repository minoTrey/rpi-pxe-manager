# Agent Roster

Last updated: 2026-05-15

## Roles

| Role | Scope | Status |
| --- | --- | --- |
| 자료조사하는애 | RPi4 EEPROM, DHCP/TFTP/NFS, Windows hosting references | completed |
| RPi4 네트워크부팅관리자 | 첫 Pi netboot 테스트 절차와 위험 요소 점검 | completed |
| 네트워크관리자 | 서버 PC 이더넷, 라우팅, 공유기 reachability 점검 | completed |
| 시스템검사하는애 | 전원 꺼짐 이후 D: 저장소와 프로젝트 상태 점검 | completed |
| 전체시스템평가하고 점수매기는애 | 준비도 점수와 핵심 리스크 평가 | completed |
| 카메라 작동 검사하는애 | Pi 부팅 후 카메라 검증 절차 | main thread handled |
| 진행상황과 사용법을 문서로 작성하는애 | 현재 사용 절차와 복구 절차 정리 | completed |
| 프로젝트 기록관리자 | 인터럽트가 많은 작업 순서와 다음 단계 문서화 | completed |

## Current Main State

- Server PC Ethernet: `10.73.0.10/24`
- ipTIME/router: `10.73.0.1`
- RPi storage: `D:` / label `rpi` / `NTFS`
- SD card: `S:` / removable `FAT32`
- Project config: `lab-10.73.json`
- Operating storage: `D:\`
- TFTP root: `D:\tftp`
- Rootfs root: `D:\rootfs`
- Generated plan: `generated\lab-10.73`
- Clients imported: 60
- Test RPi4 MAC: `88:a2:9e:4f:a9:b1`
- Test RPi4 serial: `d80c0b88`
- Test RPi4 IP: `10.73.0.155`
- Current readiness score: `68 / 100`

## Current Blockers

- DHCP/TFTP already reached the RPi4 kernel boot stage.
- Free Lite provider exists: internal DHCP/TFTP plus WinNFSd.
- First Pi boot files exist in `D:\tftp\d80c0b88`.
- Main blocker: `D:\rootfs\d80c0b88` is empty, so NFS root boot cannot continue.
- Zero 2 W is not a network boot target. It needs a separate SD boot + USB gadget workflow.
