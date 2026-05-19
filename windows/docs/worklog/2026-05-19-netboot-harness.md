# 2026-05-19 Netboot Harness Worklog

## 10:25 - WinNFSd 상태 재확인

RPi4가 SD 없이 네트워크 부팅을 시도했고 다음 단계가 확인되었습니다.

- DHCP ACK: `88:a2:9e:4f:a9:b1 -> 10.73.0.155`
- TFTP: `kernel8.img` 수신
- TFTP: `initramfs8` 수신
- NFS: `D:\rootfs\d80c0b88` mount
- NFS: `usr\sbin\init` read

하네스 판정:

```text
category: INIT_EXEC_FAIL_PROBABLE
provider: WinNFSd
initVariant: busybox-static
likelyArea: NFS root ELF execution, provider file representation, rootfs metadata
```

의미: DHCP/TFTP/rootfs 경로 문제가 아니라 Windows NFS provider 또는 Windows/NTFS 위 rootfs 표현 문제일 가능성이 커졌습니다.

## 10:50 - Linux NFS provider 자동화 추가

Windows PC 안에서는 VirtualBox, Docker, Hyper-V 관리 도구가 확인되지 않았고 WSL도 바로 쓸 수 있는 Linux 배포판 상태가 아니었습니다.

그래서 별도 bridged Linux VM/helper를 `10.73.0.20`으로 두고, Windows DHCP/TFTP는 유지한 채 NFS만 Linux `nfs-kernel-server`로 바꾸는 A/B 구조를 추가했습니다.

관련 파일:

- `windows\tools\linux-nfs-provider.ps1`
- `D:\tools\rpi-netboot\linux-nfs-provider\setup-linux-nfs-provider.sh`
- `D:\tools\rpi-netboot\linux-nfs-provider\verify-linux-nfs-provider.sh`
- `D:\tools\rpi-netboot\linux-nfs-provider\README.md`

## 12:13 - haneWIN portable NFS A/B provider 추가

haneWIN은 장기 운영 provider가 아니라 Windows NFS provider 차이를 확인하기 위한 진단용 A/B provider로 추가했습니다.

서비스 모드가 권한 문제로 막혀서, `nfsd.exe`와 `pmapd.exe`를 `D:\tools\rpi-netboot\hanewin-portable`로 복사해 portable debug 모드로 실행하도록 바꿨습니다.

관련 파일:

- `windows\tools\hanewin-nfs-provider.ps1`
- `windows\RPI-Netboot-HaneWIN-NFS-Start-Attempt-Admin.bat`
- `windows\RPI-Netboot-HaneWIN-NFS-Status-Admin.bat`
- `windows\docs\hanewin-nfs-ab-test.md`

## 13:13 - haneWIN TCP profile 실패

Attempt:

```text
20260519-121333-d80c0b88-hanewin-busybox-static
```

결과:

- DHCP/TFTP 통과
- haneWIN NFS TCP 연결 발생
- haneWIN 로그에 `nfs3_getattr: cannot read args`, `nfs3_access: cannot read args` 반복
- rootfs read/init read 단계까지 가지 못함

판단: haneWIN TCP는 Pi의 NFS RPC 요청과 맞지 않습니다.

## 13:20 - haneWIN UDP profile 1차 실패

Attempt:

```text
20260519-132057-d80c0b88-hanewin-busybox-static
```

초기 cmdline은 다음 문법을 사용했습니다.

```text
nfsroot=10.73.0.10:/rpi/d80c0b88,proto=udp,mountproto=udp,...
```

Pi 콘솔:

```text
nfs mount bad option proto
```

조치: `proto=`/`mountproto=` 문법을 제거하고 Pi early nfsroot parser가 받는 형태로 바꿨습니다.

```text
vers=3,udp,nolock,rsize=4096,wsize=4096
```

## 13:40 - haneWIN UDP profile 2차 실패

Attempt:

```text
20260519-133535-d80c0b88-hanewin-busybox-static
```

cmdline:

```text
console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=10.73.0.10:/rpi/d80c0b88,vers=3,udp,nolock,rsize=4096,wsize=4096 rw ip=dhcp rootwait elevator=deadline init=/usr/sbin/init nfsrootdebug
```

haneWIN 로그:

```text
mount3 request from 10.73.0.155
mountd: name rpi/d80c0b88 --> /d/rootfs/d80c0b88
mount3 10.73.0.155 d:\rootfs\d80c0b88
unmount 10.73.0.155 d:\rootfs\d80c0b88
```

Pi 콘솔:

```text
nfs mount mount: invalid argument
```

하네스 재판정:

```text
category: NFS_MOUNT_INVALID_ARGUMENT
provider: haneWIN
likelyArea: NFS provider mount protocol/options compatibility
confidence: high
```

## 다음 결정

haneWIN은 WinNFSd와 다른 지점에서 실패했지만, 둘 다 장기 provider로 채택하기 어렵습니다. 다음 테스트는 Linux `nfs-kernel-server` provider A/B입니다.

사용자의 물리 작업은 RPi4 전원 뺐다 꽂기까지만 유지합니다. 나머지 작업은 자동화 스크립트와 하네스가 기록해야 합니다.

## 14:19 - haneWIN official-minimal profile 시작

haneWIN 공식 Windows netboot 예시는 `nfsroot=... ,vers=3`에 가까운 최소 옵션을 사용합니다. Linux helper를 준비하기 전, 옵션 과잉으로 인한 실패 가능성을 분리하기 위해 최소 profile을 한 번 더 시작했습니다.

Attempt:

```text
20260519-141926-d80c0b88-hanewin-busybox-static
```

cmdline:

```text
console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=10.73.0.10:/rpi/d80c0b88,vers=3 rw ip=dhcp rootwait elevator=deadline init=/usr/sbin/init
```

현재 상태:

- haneWIN portable NFS PID `13856`
- DHCP/TFTP는 `RpiBootServiceLite`
- 사용자 RPi4 전원 재연결 대기

## 14:34 - haneWIN minimal + BusyBox 진단 성공

화면 증거:

```text
NFS root mounted
Mounting root file system ... done
can't run '/etc/init.d/rcS': No such file or directory
Please press Enter to activate this console.
```

처음 하네스가 이를 `NFS_MOUNT_FAIL`로 오판했지만, 콘솔 증거를 반영하도록 verdict 로직을 고쳤습니다.

정정된 verdict:

```text
INIT_EXEC_REACHED_BUSYBOX_RC_MISSING
```

의미:

- haneWIN minimal profile은 NFS root mount에 성공했습니다.
- `/usr/sbin/init` 실행도 성공했습니다.
- 멈춘 이유는 진단용 BusyBox init이 `/etc/init.d/rcS`를 찾기 때문입니다.

조치:

- 원래 systemd init을 복원했습니다.
- `BOOT-NFS-BUSYBOX-DIAGNOSTIC.txt` marker를 제거하도록 `init-diagnostic.ps1`를 고쳤습니다.

## 14:43 - haneWIN minimal + systemd 재시험 시작

Attempt:

```text
20260519-144335-d80c0b88-hanewin-systemd-explicit
```

현재 사용자 RPi4 전원 재연결 대기 중입니다.
