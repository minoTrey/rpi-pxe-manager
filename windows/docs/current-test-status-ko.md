# 현재 테스트 상태

마지막 업데이트: 2026-05-15 KST

## 결론

RPi4 네트워크 부팅은 DHCP/TFTP 단계까지 성공했습니다. 커널이 뜬 뒤 NFS rootfs 단계에서 실패하고 있습니다.

현재 가장 중요한 문제는 `D:\rootfs\d80c0b88`가 비어 있다는 점입니다. 이 폴더에 실제 Raspberry Pi OS rootfs가 들어가야 커널 다음 단계로 넘어갑니다.

정책상 네트워크 부팅 대상은 RPi4뿐입니다. Zero 2 W는 SD카드로 부팅하고 USB gadget mode로 붙이는 별도 흐름입니다.

## 장비와 주소

| 항목 | 값 |
| --- | --- |
| 서버 PC 이더넷 | `10.73.0.10/24` |
| ipTIME/router | `10.73.0.1` |
| 서버 PC MAC | `6c:4b:90:3d:08:9b` |
| 테스트 RPi4 MAC | `88:a2:9e:4f:a9:b1` |
| 테스트 RPi4 serial | `d80c0b88` |
| 테스트 RPi4 IP | `10.73.0.155` |
| TFTP 폴더 | `D:\tftp\d80c0b88` |
| rootfs 폴더 | `D:\rootfs\d80c0b88` |

## 화면에서 확인된 사실

RPi4는 서버 PC에서 DHCP 응답을 받았습니다.

```text
IP-Config: Got DHCP answer from 10.73.0.10, my address is 10.73.0.155
bootserver=10.73.0.10, rootserver=10.73.0.10
```

부팅 실패는 다음 메시지로 나타났습니다.

```text
VFS: Unable to mount root fs via NFS
Kernel panic - not syncing: No working init found
```

이 메시지는 부팅 파일 전달보다 뒤 단계의 문제입니다. 즉, DHCP/TFTP는 지나갔고 NFS/rootfs 단계가 현재 관문입니다.

## 마지막으로 확인된 서비스 상태

무료 Lite provider를 관리자 권한으로 시작했을 때 다음 상태까지 확인했습니다.

- 내장 DHCP/TFTP 서버 실행
- WinNFSd 실행
- DHCP UDP `67` 대기
- TFTP UDP `69` 대기
- Portmapper TCP/UDP `111` 대기
- NFS TCP `2049` 대기

주의: 이 서비스들은 Windows 프로세스라서 창을 닫거나 재부팅하면 멈출 수 있습니다. 다음 테스트 전에는 GUI에서 `전체 상태 다시 확인`을 다시 눌러야 합니다.

## 현재 정상인 것

- 서버 PC IP와 공유기 주소가 맞습니다.
- RPi4 EEPROM은 네트워크 부팅을 시도합니다.
- RPi4가 DHCP 응답을 받았습니다.
- RPi4가 TFTP로 커널을 받아 실행했습니다.
- `D:\tftp\d80c0b88`에는 RPi4 부팅 파일이 있습니다.

## 현재 필요한 것

1. `D:\rootfs\d80c0b88`에 실제 Linux rootfs를 채워야 합니다.
2. rootfs 안에 최소한 `sbin\init` 또는 `bin\sh`가 있어야 합니다.
3. rootfs 복제는 Windows 탐색기 복사가 아니라 Pi/Linux helper의 `rsync` 방식으로 하는 것이 안전합니다.
4. rootfs가 준비된 뒤 RPi4를 SD카드 없이 다시 켜서 NFS root 부팅을 확인합니다.
5. rootfs 준비 기능을 GUI 버튼과 상태 점검에 연결해야 합니다.
6. Zero 2 W SD + USB gadget 준비 기능은 RPi4 netboot 흐름과 분리해야 합니다.

## 추적 도구 상태

- GitHub는 기존 `minoTrey/rpi-pxe-manager` repository를 사용합니다.
- Windows판은 해당 repo의 `windows/` 폴더로 분리합니다.
- Linear project `RPI Netboot Windows`를 만들었고, 남은 작업은 `3D-5`부터 `3D-8`까지 이슈로 기록했습니다.
- 이 문서는 그래도 실제 장비 테스트 상태의 기준 원장으로 유지합니다.

## 다음 테스트 순서

1. `RPI-Netboot-Manager-Admin-Update.exe`를 관리자 권한으로 실행합니다.
2. `전체 상태 다시 확인`을 누릅니다.
3. DHCP/TFTP/NFS/Portmapper가 정상인지 봅니다.
4. `D:\rootfs\d80c0b88`가 비어 있는지 봅니다.
5. rootfs 준비 기능을 실행하거나, Linux helper에서 `D:\rootfs\d80c0b88`로 rootfs를 복제합니다.
6. `D:\rootfs\d80c0b88\sbin\init` 또는 `D:\rootfs\d80c0b88\bin\sh`가 생겼는지 확인합니다.
7. RPi4 전원을 껐다 켭니다.
8. Zero 2 W는 이 테스트에 포함하지 말고, 별도 SD + USB gadget 테스트로 진행합니다.

## 헷갈리면 이것만 기억

지금은 “RPi4가 서버를 못 찾는 문제”가 아닙니다. RPi4는 서버를 찾았고 커널도 받았습니다. 남은 일은 서버가 RPi4에게 실제 Linux rootfs를 제공하게 만드는 것입니다.
