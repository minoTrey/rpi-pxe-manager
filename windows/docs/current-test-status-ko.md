# 현재 테스트 상태

마지막 업데이트: 2026-05-19 10:35 KST

## 결론

RPi4 네트워크 부팅은 DHCP/TFTP 단계까지 성공했고, 2026-05-15 16:15 KST 기준 `D:\rootfs\d80c0b88`에도 부팅 핵심 rootfs가 들어갔습니다.

SD카드를 제거한 상태에서 RPi4를 다시 켰고, NFS root mount까지는 성공했습니다. 공식 Raspberry Pi OS bootfs로 맞춘 뒤에도 `init` 실행 단계의 `error -14`가 재현됐습니다. static busybox init 진단 모드에서도 2026-05-19 10:25 KST 로그상 init read 뒤 재부팅/실패 패턴이 보입니다.

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

초기 부팅 실패는 다음 메시지로 나타났습니다.

```text
VFS: Unable to mount root fs via NFS
Kernel panic - not syncing: No working init found
```

이 메시지는 부팅 파일 전달보다 뒤 단계의 문제입니다. 즉, DHCP/TFTP는 지나갔고 NFS/rootfs 단계가 현재 관문입니다.

rootfs를 채운 뒤의 최신 실패는 다음 메시지입니다.

```text
VFS: Mounted root (nfs filesystem) on device 0:19.
Starting init: /sbin/init exists but couldn't execute it (error -14)
Starting init: /bin/sh exists but couldn't execute it (error -14)
Kernel panic - not syncing: No working init found.
```

`init=/usr/sbin/init`를 직접 지정하고 symlink를 실제 파일로 바꾼 뒤에도 다음 오류가 재현됐습니다.

```text
Kernel panic - not syncing: Requested init /usr/sbin/init failed (error -14)
```

2026-05-15 17:00 KST에는 공식 Raspberry Pi OS bootfs를 `D:\tftp\d80c0b88`에 동기화한 뒤 다시 부팅했습니다. Pi는 새 `kernel8.img`와 `initramfs8`를 실제로 받아갔지만 같은 오류가 재현됐습니다.

```text
TFTP GET d80c0b88/kernel8.img bytes=9695883
TFTP GET d80c0b88/initramfs8 bytes=16040912
Kernel panic - not syncing: Requested init /usr/sbin/init failed (error -14)
```

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
- `D:\rootfs\d80c0b88`에는 `bin\sh`, `sbin\init`, `usr\lib\systemd\systemd`, `usr\lib\modules`, `etc\fstab`가 있습니다.
- Pi에서 NFS로 `10.73.0.10:/rpi/d80c0b88`를 읽는 테스트가 `ROOTFS_NFS_READ_OK`로 통과했습니다.
- SD 없는 부팅에서도 NFS root mount는 성공했습니다.
- WinNFSd 로그에서 커널이 `systemd`, ELF loader, `dash`를 읽은 것을 확인했습니다.
- 공식 bootfs 동기화 후 Pi가 `kernel8.img` 9,695,883 bytes와 `initramfs8` 16,040,912 bytes를 TFTP로 수신했습니다.
- `D:\rootfs\d80c0b88\usr\sbin\init`은 임시로 Debian arm64 static busybox로 교체됐고, 원래 systemd init은 `init.systemd-before-busybox`에 백업됐습니다.
- 테스트 하네스가 최신 로그를 `INIT_EXEC_FAIL_PROBABLE`로 자동 판정했습니다.

## 현재 필요한 것

1. `error -14`는 Linux errno 기준 `EFAULT`라서 단순 파일 없음, 권한 없음, 포맷 오류보다 ELF loader/NFS 파일 표현 문제 가능성이 큽니다.
2. TFTP boot 파일과 rootfs OS 세트 불일치 가설은 공식 bootfs 재시험으로 가능성이 낮아졌습니다.
3. static busybox init 테스트로 systemd/동적 linker 단독 문제 가능성은 낮아졌습니다.
4. 같은 rootfs를 Linux NFS server에서 내보내 provider 문제를 확정해야 합니다.
5. rootfs 준비 기능과 bootfs 동기화 기능을 GUI 버튼과 상태 점검에 더 친절하게 연결해야 합니다.
6. Zero 2 W SD + USB gadget 준비 기능은 RPi4 netboot 흐름과 분리해야 합니다.

## 추적 도구 상태

- GitHub는 기존 `minoTrey/rpi-pxe-manager` repository를 사용합니다.
- Windows판은 해당 repo의 `windows/` 폴더로 분리합니다.
- GitHub draft PR: `https://github.com/minoTrey/rpi-pxe-manager/pull/1`
- Linear project `RPI Netboot Windows`를 만들었고, 남은 작업은 `3D-5`부터 `3D-8`까지 이슈로 기록했습니다.
- 이 문서는 그래도 실제 장비 테스트 상태의 기준 원장으로 유지합니다.

## 다음 테스트 순서

1. `RPI-Netboot-Manager-Admin-Update.exe`를 관리자 권한으로 실행합니다.
2. `전체 상태 다시 확인`을 누릅니다.
3. DHCP/TFTP/NFS/Portmapper가 정상인지 봅니다.
4. `D:\rootfs\d80c0b88`에 `bin\sh`, `sbin\init`, `usr\lib\systemd\systemd`가 있는지 봅니다.
5. `D:\tftp\d80c0b88`가 공식 bootfs인지 확인합니다. 현재 기준 `kernel8.img`는 9,695,883 bytes입니다.
6. SD 없이 RPi4 전원을 다시 넣어 static busybox init 결과를 확인합니다.
7. 화면에서 `error -14`가 사라지는지 확인합니다.
8. Zero 2 W는 이 테스트에 포함하지 말고, 별도 SD + USB gadget 테스트로 진행합니다.

하네스 최신 판정:

```text
category: INIT_EXEC_FAIL_PROBABLE
passed: DHCP, TFTP_STARTED, TFTP_KERNEL, TFTP_CMDLINE, TFTP_DTB, INITRAMFS_TRANSFER, NFS_MOUNT, NFS_ROOT_READ, INIT_READ
diagnostic: BUSYBOX_DIAGNOSTIC_ACTIVE
provider: WinNFSd
initVariant: busybox-static
likelyArea: NFS root ELF execution, provider file representation, rootfs metadata
confidence: medium-high
```

진단이 끝난 뒤 systemd init으로 되돌리는 명령:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\tools\init-diagnostic.ps1 -Command restore -Config .\windows\lab-10.73.json -Serial d80c0b88
```

## 헷갈리면 이것만 기억

지금은 “RPi4가 서버를 못 찾는 문제”가 아닙니다. RPi4는 서버를 찾았고 커널도 받았고 NFS root도 마운트했습니다. 남은 일은 `init` 실행 실패 `error -14`를 해결하는 것입니다.
