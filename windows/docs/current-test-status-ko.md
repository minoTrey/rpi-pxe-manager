# 현재 테스트 상태

마지막 업데이트: 2026-05-19 13:55 KST

## 결론

RPi4는 서버 PC를 찾고, DHCP와 TFTP까지 정상 통과합니다. 실패 지점은 이제 NFS provider 호환성으로 좁혀졌습니다.

최신 haneWIN UDP 실험에서 Pi는 `10.73.0.10:/rpi/d80c0b88` export를 찾아 `D:\rootfs\d80c0b88`까지 mount 요청을 보냈지만, HDMI 콘솔에는 다음 오류가 나왔습니다.

```text
nfs mount mount: invalid argument
```

하네스 최신 판정:

```text
category: NFS_MOUNT_INVALID_ARGUMENT
provider: haneWIN
initVariant: busybox-static
passed: DHCP, TFTP_STARTED, TFTP_KERNEL, TFTP_CMDLINE, TFTP_DTB, INITRAMFS_TRANSFER, NFS_MOUNT
likelyArea: NFS provider mount protocol/options compatibility
confidence: high
```

즉, 현재 문제는 공유기/IP/TFTP 파일 누락이 아닙니다. haneWIN/WinNFSd 같은 Windows NFS provider가 Raspberry Pi 커널의 NFS root mount와 완전히 맞지 않는 것이 핵심 가설입니다.

## 장비와 주소

| 항목 | 값 |
| --- | --- |
| 서버 PC Ethernet | `10.73.0.10/24` |
| 공유기 | `10.73.0.1` |
| 서버 PC MAC | `6c:4b:90:3d:08:9b` |
| 테스트 RPi4 MAC | `88:a2:9e:4f:a9:b1` |
| 테스트 RPi4 serial | `d80c0b88` |
| 테스트 RPi4 예약 IP | `10.73.0.155` |
| TFTP 경로 | `D:\tftp\d80c0b88` |
| Windows rootfs 경로 | `D:\rootfs\d80c0b88` |
| 최신 증거 폴더 | `D:\logs\netboot-harness\20260519-133535-d80c0b88-hanewin-busybox-static` |

## 지금까지 통과한 것

- EEPROM 네트워크 부팅 설정은 완료되었습니다.
- SD 카드 제거 상태에서 RPi4가 네트워크 부팅을 시도합니다.
- DHCP ACK가 정상으로 내려갑니다.
- Pi가 `kernel8.img`, `cmdline.txt`, `bcm2711-rpi-4-b.dtb`, `initramfs8`을 TFTP로 받습니다.
- WinNFSd에서는 NFS mount, rootfs read, init read까지 도달했습니다.
- haneWIN UDP에서는 mountd가 `/rpi/d80c0b88`을 `D:\rootfs\d80c0b88`로 매핑하는 것까지 확인했습니다.

## 실패 이력

| Provider | 결과 | 의미 |
| --- | --- | --- |
| WinNFSd | `Requested init /usr/sbin/init failed (error -14)` | NFS mount/rootfs read/init read까지는 되었지만 실행 단계에서 실패 |
| haneWIN TCP | `nfs3_getattr/access cannot read args` | haneWIN이 Pi의 NFS RPC 호출을 제대로 읽지 못함 |
| haneWIN UDP 1차 | `nfs mount bad option proto` | Pi early nfsroot parser가 `proto=udp` 문법을 거부 |
| haneWIN UDP 2차 | `nfs mount mount: invalid argument` | 옵션 문법은 고쳤지만 haneWIN mount negotiation이 최종 실패 |

## 다음 액션

다음 성공 가능성이 가장 높은 테스트는 같은 bootfs/rootfs를 Linux `nfs-kernel-server`에서 내보내는 A/B 테스트입니다.

Windows 쪽 준비는 자동화되어 있습니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\tools\linux-nfs-provider.ps1 prepare -Config .\windows\lab-10.73.json -Serial d80c0b88 -LinuxServerIp 10.73.0.20
```

생성된 bundle:

```text
D:\tools\rpi-netboot\linux-nfs-provider
```

다음에는 Linux VM/helper를 `10.73.0.20`으로 붙이고, 해당 bundle로 `/srv/rpi-root/d80c0b88` export를 만든 뒤 Pi 전원만 다시 뺐다 꽂아 검증합니다.

## 현재 서버 프로세스 상태

2026-05-19 14:10 KST 기준 haneWIN portable NFS는 중지했습니다. 현재 Windows 서버 PC에서는 DHCP/TFTP만 `RpiBootServiceLite`로 열려 있고, NFS 111/2049는 비워 둔 상태입니다.

Linux NFS helper가 준비되기 전에는 RPi4 전원을 다시 넣어도 부팅이 완료되지 않습니다. 다음 전원 재연결은 Linux provider attempt를 시작한 뒤에 진행합니다.

## 진행 중인 추가 확인

2026-05-19 14:19 KST에 haneWIN 공식 가이드에 가까운 최소 profile을 한 번 더 시작했습니다.

```text
attempt: 20260519-141926-d80c0b88-hanewin-busybox-static
cmdline: nfsroot=10.73.0.10:/rpi/d80c0b88,vers=3
```

이 시도는 `udp`, `nolock`, `rsize`, `wsize`, `nfsrootdebug`를 제거해 haneWIN 공식 예시에 더 가깝게 맞춘 것입니다. 사용자가 RPi4 전원을 뺐다 꽂으면 하네스가 이 attempt의 로그를 비교합니다.
