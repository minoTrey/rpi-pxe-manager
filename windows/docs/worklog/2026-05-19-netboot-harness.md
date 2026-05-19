# 2026-05-19 Netboot Harness Worklog

## 10:25 최신 장비 로그 재확인

RPi4가 다시 부팅을 시도한 로그가 남아 있었습니다.

- DHCP ACK: `88:a2:9e:4f:a9:b1 -> 10.73.0.155`
- TFTP: `kernel8.img` 9,695,883 bytes 수신
- TFTP: `initramfs8` 16,040,912 bytes 수신
- NFS: `D:\rootfs\d80c0b88` mount
- NFS: `usr\sbin\init` read

`D:\rootfs\d80c0b88\usr\sbin\init`은 Debian arm64 static busybox 진단 init 상태입니다. 즉 최신 로그는 systemd init이 아니라 busybox init을 읽은 시도입니다.

## 하네스 설계

새 하네스의 목표는 실험 하나를 증거 묶음으로 남기는 것입니다.

- `preflight.json`: 네트워크, 볼륨, 포트, 설정
- `tftp-manifest.json`: bootfs 핵심 파일 크기/해시
- `rootfs-exec-inspection.json`: init, loader, shell, busybox 진단 상태
- `rpi-boot-lite.tail.log`: DHCP/TFTP 로그
- `winnfsd.stdout.tail.log`: NFS 로그
- `verdict.json`: 자동 판정

명령:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\tools\netboot-harness.ps1 collect-latest -Config .\windows\lab-10.73.json -Serial d80c0b88 -Mac 88:a2:9e:4f:a9:b1 -PiIp 10.73.0.155 -Provider WinNFSd -InitVariant busybox-static
```

## 첫 하네스 판정

산출물:

```text
D:\logs\netboot-harness\latest-20260519-103453-d80c0b88
```

자동 판정:

```text
category: INIT_EXEC_FAIL_PROBABLE
passed: DHCP, TFTP_STARTED, TFTP_KERNEL, TFTP_CMDLINE, TFTP_DTB, INITRAMFS_TRANSFER, NFS_MOUNT, NFS_ROOT_READ, INIT_READ
diagnostic: BUSYBOX_DIAGNOSTIC_ACTIVE
provider: WinNFSd
initVariant: busybox-static
likelyArea: NFS root ELF execution, provider file representation, rootfs metadata
confidence: medium-high
missingEvidence: Pi HDMI/serial console text
```

## 판단

네트워크부팅 실패는 아직 해결되지 않았습니다. 다만 실패 위치는 훨씬 좁아졌습니다.

현재는 다음 문제가 아닙니다.

- DHCP 실패
- TFTP 파일 누락
- initramfs 누락
- NFS mount 실패
- rootfs 경로 누락

현재 의심 영역은 다음입니다.

- WinNFSd/NTFS가 Linux rootfs 파일을 NFS root의 실행 가능한 ELF로 정확히 표현하지 못함
- rootfs의 Linux metadata/symlink/device-node 표현 손상
- NFS provider별 file handle/read/mmap 동작 차이

## 다음 실험

같은 bootfs와 rootfs를 유지하고 NFS provider만 바꾸는 A/B 테스트를 해야 합니다.

1. Ubuntu 또는 Debian Linux VM을 유선 이더넷에 bridged로 연결합니다.
2. VM에서 `nfs-kernel-server`를 설치합니다.
3. rootfs를 Linux ext4 위 `/srv/rpi-root/d80c0b88`에 복제하거나, 우선 최소 복사본으로 테스트합니다.
4. `cmdline.txt`의 `nfsroot`만 VM IP/export path로 바꿉니다.
5. 하네스 `start-attempt`/`finish-attempt`로 provider `LinuxNFS` 결과를 저장합니다.
