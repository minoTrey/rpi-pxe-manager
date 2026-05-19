# Netboot Test Harness

이 문서는 RPi4 네트워크 부팅 실패를 재현 가능한 증거 묶음으로 남기는 하네스 운영 기준입니다.

## 목적

하네스의 목적은 "부팅이 안 된다"를 더 작은 단계로 나누는 것입니다.

- DHCP가 통과했는지
- TFTP boot 파일을 받았는지
- initramfs를 받았는지
- NFS root를 mount했는지
- rootfs 안의 init을 읽었는지
- init 실행 단계에서 실패했는지

현재 대표 판정은 다음입니다.

```text
INIT_EXEC_FAIL_PROBABLE
```

즉, RPi4가 서버를 못 찾는 문제가 아닙니다. DHCP, TFTP, initramfs, NFS mount, rootfs read, init read까지 갔고, 남은 관문은 NFS root 위 ELF 실행입니다.

## 명령

최신 로그를 한 번에 수집하고 자동 판정합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\tools\netboot-harness.ps1 collect-latest -Config .\windows\lab-10.73.json -Serial d80c0b88 -Mac 88:a2:9e:4f:a9:b1 -PiIp 10.73.0.155 -Provider WinNFSd -InitVariant busybox-static
```

전원 재투입 실험을 새로 시작할 때는 먼저 attempt를 엽니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\tools\netboot-harness.ps1 start-attempt -Config .\windows\lab-10.73.json -Serial d80c0b88 -Mac 88:a2:9e:4f:a9:b1 -PiIp 10.73.0.155 -Provider WinNFSd -InitVariant busybox-static
```

그 다음 SD카드 없는 RPi4 전원을 완전히 뺐다가 다시 넣습니다. 화면에 나온 핵심 메시지를 적어둔 뒤 finish를 실행합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\tools\netboot-harness.ps1 finish-attempt -Config .\windows\lab-10.73.json -Serial d80c0b88 -Mac 88:a2:9e:4f:a9:b1 -PiIp 10.73.0.155 -Provider WinNFSd -InitVariant busybox-static -ConsoleText "HDMI screen text here"
```

rootfs의 init/loader/shell 상태만 확인할 때는 다음을 씁니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\tools\netboot-harness.ps1 inspect-rootfs -Config .\windows\lab-10.73.json -Serial d80c0b88
```

## 산출물

증거는 `D:\logs\netboot-harness` 아래에 저장됩니다.

```text
D:\logs\netboot-harness\
  latest-verdict.json
  latest-YYYYMMDD-HHMMSS-d80c0b88\
    preflight.json
    tftp-manifest.json
    rootfs-exec-inspection.json
    rpi-boot-lite.tail.log
    winnfsd.stdout.tail.log
    console.txt
    verdict.json
```

전원 재투입 attempt는 다음 파일을 추가로 남깁니다.

```text
attempt-start.json
rpi-boot-lite.delta.log
winnfsd.stdout.delta.log
winnfsd.stderr.delta.log
ports-after.json
timeline.md
```

## 판정 규칙

하네스는 가장 뒤 단계의 성공 증거를 우선합니다. 예를 들어 TFTP timeout이 있어도 NFS mount와 init read가 보이면 TFTP 실패로 판정하지 않습니다.

대표 판정:

- `DHCP_FAIL`: DHCP ACK 없음
- `TFTP_NOT_STARTED`: DHCP ACK는 있으나 TFTP GET 없음
- `TFTP_BOOTFILE_FAIL`: 핵심 TFTP 파일 수신 실패
- `INITRAMFS_MISSING_OR_FAIL`: initramfs 설정이 있는데 수신 실패
- `NFS_MOUNT_FAIL`: TFTP 이후 NFS mount 증거 없음
- `NFS_ROOT_READ_FAIL`: NFS mount는 됐지만 rootfs 하위 파일 read 없음
- `INIT_EXEC_REACHED`: init 파일 read까지 도달, 콘솔 증거 부족
- `INIT_EXEC_FAIL_PROBABLE`: init read 뒤 재부팅 반복 또는 콘솔 panic 증거

현재 최신 자동 판정:

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

## 다음 실험

static busybox init 상태에서도 실패가 반복되므로 다음 고가치 실험은 provider A/B 테스트입니다.

1. 같은 TFTP bootfs를 유지합니다.
2. 같은 rootfs 내용을 사용합니다.
3. NFS provider만 WinNFSd에서 bridged Linux VM의 `nfs-kernel-server`로 바꿉니다.
4. Pi `cmdline.txt`의 `nfsroot=<server-ip>:/srv/rpi-root,vers=3,proto=tcp,rw`만 VM IP와 export 경로로 바꿉니다.
5. Linux NFS에서 부팅되면 WinNFSd/NTFS provider 계층이 원인입니다.
6. Linux NFS에서도 실패하면 rootfs 복제 품질, 파일 내용, 커널/initramfs 설정을 다시 봅니다.
