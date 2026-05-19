# Linux NFS Provider

현재 WinNFSd/NTFS provider는 RPi4가 NFS root를 mount하고 static busybox init을 읽는 단계까지는 통과하지만, init 실행 이후 실패하는 것으로 보입니다. 다음 원인 분리는 같은 bootfs/rootfs를 Linux NFS provider에서 제공하는 A/B 테스트입니다.

## 현재 판단

하네스 최신 판정:

```text
INIT_EXEC_FAIL_PROBABLE
```

통과한 단계:

```text
DHCP
TFTP_STARTED
TFTP_KERNEL
TFTP_CMDLINE
TFTP_DTB
INITRAMFS_TRANSFER
NFS_MOUNT
NFS_ROOT_READ
INIT_READ
```

따라서 다음 실험은 Windows DHCP/TFTP는 유지하고, NFS root provider만 Linux로 바꾸는 것입니다.

## Windows 쪽 준비

안전한 준비만 수행합니다. 이 명령은 `cmdline.txt`를 바꾸지 않습니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\tools\linux-nfs-provider.ps1 prepare -Config .\windows\lab-10.73.json -Serial d80c0b88 -LinuxServerIp 10.73.0.20
```

생성 위치:

```text
D:\tools\rpi-netboot\linux-nfs-provider
```

더블클릭용:

```text
windows\RPI-Netboot-LinuxNFS-Prepare.bat
```

## Linux VM 쪽 준비

Linux VM은 유선 이더넷에 bridged로 붙이고 `10.73.0.20/24`를 사용합니다. Windows 서버 PC는 계속 `10.73.0.10`으로 DHCP/TFTP를 담당합니다.

Linux VM 또는 Linux helper로 `D:\tools\rpi-netboot\linux-nfs-provider` 폴더를 옮긴 뒤 실행합니다.

```bash
sudo SOURCE_SSH=pi@10.73.0.155 SERIAL=d80c0b88 EXPORT_ROOT=/srv/rpi-root bash setup-linux-nfs-provider.sh
sudo SERIAL=d80c0b88 EXPORT_ROOT=/srv/rpi-root bash verify-linux-nfs-provider.sh
```

Pi를 SD카드로 부팅해 SSH source로 쓸 수 없다면, SD카드의 root partition을 Linux VM에 mount하고 다음처럼 실행합니다.

```bash
sudo SOURCE_DIR=/mnt/rpi-root SERIAL=d80c0b88 EXPORT_ROOT=/srv/rpi-root bash setup-linux-nfs-provider.sh
sudo SERIAL=d80c0b88 EXPORT_ROOT=/srv/rpi-root bash verify-linux-nfs-provider.sh
```

## A/B 시도 시작

Linux NFS export가 준비된 뒤에만 실행합니다. 이 명령은 `D:\tftp\d80c0b88\cmdline.txt`를 Linux NFS server로 전환하고, 하네스 attempt를 시작합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\tools\linux-nfs-provider.ps1 start-attempt -Config .\windows\lab-10.73.json -Serial d80c0b88 -LinuxServerIp 10.73.0.20
```

더블클릭용:

```text
windows\RPI-Netboot-LinuxNFS-Start-Attempt.bat
```

그 다음 SD 없는 RPi4 전원을 완전히 뺐다가 다시 넣습니다.

## 결과 마무리

화면 메시지를 `ConsoleText`에 넣어 finish합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\tools\linux-nfs-provider.ps1 finish-attempt -Config .\windows\lab-10.73.json -Serial d80c0b88 -LinuxServerIp 10.73.0.20 -ConsoleText "HDMI screen text here"
```

## 해석

- Linux NFS에서 부팅 성공: WinNFSd/NTFS provider가 원인입니다. Windows 앱은 Linux-backed provider를 정식 경로로 지원해야 합니다.
- Linux NFS에서도 같은 실패: rootfs 복제 품질, 파일 내용, initramfs/cmdline 설정을 다시 봅니다.

## WinNFSd로 되돌리기

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\tools\linux-nfs-provider.ps1 restore-winnfsd-cmdline -Config .\windows\lab-10.73.json -Serial d80c0b88
```
