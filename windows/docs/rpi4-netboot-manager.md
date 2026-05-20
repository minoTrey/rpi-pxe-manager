# RPi4 네트워크 부팅 체크리스트

## 서버 기준

- 서버 PC 유선 이더넷: `10.73.0.10/24`
- 공유기: `10.73.0.1`
- TFTP root: `<저장소>\tftp`
- rootfs root: `<저장소>\rootfs`
- NFS alias: `/rpi`
- SD카드 드라이브: 보통 `S:`

## Pi 4 EEPROM 확인

Pi 4에서 SD 부팅이 가능한 상태라면 다음 값을 확인한다.

```bash
vcgencmd bootloader_config | tee ~/bootloader-config.before-netboot.txt
rpi-eeprom-config | tee ~/rpi-eeprom-config.before-netboot.txt
grep Serial /proc/cpuinfo
ethtool -P eth0
```

권장 시작값:

```text
BOOT_ORDER=0xf21
TFTP_PREFIX=0
```

## 테스트 순서

1. `lab-10.73.json`에서 실제 Pi serial/MAC/IP가 맞는지 확인.
2. `<저장소>\tftp\<serial>`에 boot partition 파일 준비.
3. `cmdline.txt`가 한 줄인지 확인.
4. `<저장소>\rootfs\<serial>`에 실제 Linux rootfs 준비.
5. `RPI-Netboot-Manager.exe`에서 `부팅 서비스 시작`.
6. `.\tools\check-lab-10.73.ps1`로 UDP 67/69, TCP/UDP 2049 리스너 확인.
7. Pi 전원을 다시 넣어 네트워크 부팅 확인.

## TFTP 폴더 구조

```text
<저장소>\tftp\
  d80c0b88\
    cmdline.txt
    config.txt
    start4.elf
    fixup4.dat
    kernel8.img
    bcm2711-rpi-4-b.dtb
    overlays\
```

## cmdline 기준

`cmdline.txt`는 반드시 한 줄이어야 한다.

```text
console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=10.73.0.10:/rpi/<serial>,vers=3,tcp rw ip=dhcp rootwait elevator=deadline
```

중요 조건:

- `root=/dev/nfs`가 있어야 한다.
- `nfsroot=10.73.0.10:/rpi/<serial>,vers=3,tcp`가 rootfs 서비스 설정과 맞아야 한다.
- 실제 rootfs는 `<저장소>\rootfs\<serial>\etc`, `<저장소>\rootfs\<serial>\usr` 같은 Linux 구조여야 한다.

## 실패 시 확인 순서

1. DHCP 요청이 서비스 로그에 보이는지 확인.
2. TFTP에서 `<serial>/start4.elf` 요청이 보이는지 확인.
3. 커널 파일이 로드되는지 확인.
4. rootfs mount 단계까지 가는지 확인.
5. rootfs 안의 `/etc/fstab`, hostname, SSH 설정을 확인.

첫 Pi가 안정적으로 부팅되면 그 rootfs를 기준 템플릿으로 삼아 다음 Pi들을 복제한다.
