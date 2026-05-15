# 시스템 준비도 점수카드

평가일: 2026-05-15

총점: **68 / 100**

## 요약

전원 꺼짐 이후 꼬였던 드라이브 문자는 복구됐다. 현재 `D:`는 `rpi` 라벨의 NTFS SSD이고, SD카드는 `S:`로 분리되어 있다. 서버 PC 이더넷도 `10.73.0.10/24`로 정상이며 공유기 `10.73.0.1` ping도 성공한다.

무료 Lite provider 실행 파일과 WinNFSd는 준비됐다. 테스트 RPi4는 DHCP/TFTP로 커널까지 받는 데 성공했다. 지금은 NFS/rootfs 단계가 blocker이며, 특히 `D:\rootfs\d80c0b88`가 비어 있어서 커널 이후 부팅이 멈춘다.

## 점수

| 항목 | 점수 | 상태 |
| --- | ---: | --- |
| 네트워크 | 85 | 이더넷 `10.73.0.10`, 공유기 ping 정상, Wi-Fi 인터넷 유지 |
| 저장소 | 80 | `D:\` 루트에 60대분 `tftp/rootfs` 폴더 준비 |
| DHCP/TFTP | 80 | 테스트 RPi4가 DHCP 응답과 TFTP 커널 수신까지 확인됨 |
| NFS/rootfs | 45 | WinNFSd는 준비됐으나 테스트 rootfs 폴더가 비어 있음 |
| RPi4 EEPROM | 75 | SD EEPROM 업데이트 뒤 SD 없이 네트워크 부팅 진입 확인 |
| 문서/자동화 | 78 | GUI, 관리자 재실행, SD 안전장치, 기억장/worklog/ADR까지 정리됨 |
| 카메라 | 25 | Pi 부팅 후 검증 절차만 있음 |

## 가장 큰 리스크

1. `D:\rootfs\d80c0b88`가 비어 있어서 NFS root 부팅이 불가능하다.
2. rootfs를 Windows 탐색기로 복사하면 Linux 권한과 링크가 깨질 수 있다.
3. SD카드나 카드리더기가 드라이브 문자를 다시 가져갈 수 있으므로 전원 복귀 후 GUI의 `상태 확인`으로 `D:`와 `S:`를 먼저 확인해야 한다.

## 다음 최고 영향 작업

1. `D:\rootfs\d80c0b88`에 실제 Raspberry Pi OS rootfs 복제
2. `D:\rootfs\d80c0b88\sbin\init` 또는 `bin\sh` 존재 확인
3. 무료 Lite provider 리스너 재확인
4. Pi 한 대만 전원 투입해서 DHCP -> TFTP -> kernel -> NFS -> init 순서로 검증
5. rootfs 복제 기능을 GUI 버튼과 상태 점검에 연결

운영 전에는 haneWIN 평가판에 의존하지 않도록 무료 Lite provider 또는 오픈소스/내장 provider 준비 상태를 다시 확인한다.
