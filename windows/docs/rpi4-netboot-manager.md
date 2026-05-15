# RPi4 네트워크 부팅 관리자 체크리스트

## 서버 기준

- 서버 PC 이더넷: `10.73.0.10/24`
- 공유기/ipTIME: `10.73.0.1`
- TFTP root: `D:\tftp`
- rootfs root: `D:\rootfs`
- NFS alias: `/rpi`
- SD카드 드라이브: `S:`

## Pi 4 EEPROM 확인

첫 Pi를 SD카드로 정상 부팅한 뒤 실행한다.

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

`BOOT_ORDER=0xf21`은 SD카드를 먼저 시도하고, 실패하면 네트워크 부팅을 시도한 뒤 반복한다. 테스트 중 문제가 생겨도 정상 SD카드를 꽂으면 롤백하기 쉽다.

## 첫 Pi 테스트 순서

1. `lab-10.73.json`에서 실제 Pi의 serial/MAC/IP가 맞는지 확인
2. `D:\tftp\<serial>`에 boot partition 파일 복사
3. 생성된 `cmdline.txt`는 한 줄 그대로 유지
4. `D:\rootfs\<serial>`에 rootfs를 Linux/Pi helper로 복사
5. 무료 Lite provider 실행. 내장 DHCP/TFTP와 WinNFSd가 DHCP/TFTP/NFS 역할을 맡는다.
6. `.\tools\check-lab-10.73.bat`로 UDP 67/69, TCP/UDP 2049 리스너 확인
7. Pi 한 대만 전원 투입

## TFTP 폴더 구조

```text
D:\tftp\
  d3a76dcf\
    cmdline.txt
    config.txt
    start4.elf
    fixup4.dat
    kernel8.img
    bcm2711-rpi-4-b.dtb
    overlays\
```

Pi 4 기본 `TFTP_PREFIX=0`은 serial 기반 prefix를 사용한다. 그래서 여러 대 운영 시 각 Pi는 `D:\tftp\<serial>` 아래에서 부팅 파일을 찾게 한다.

## cmdline 기준

생성된 `cmdline.txt` 예:

```text
console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=10.73.0.10:/rpi/<serial>,vers=3,tcp rw ip=dhcp rootwait elevator=deadline
```

중요한 점:

- `cmdline.txt`는 반드시 한 줄이어야 한다.
- `root=/dev/nfs`가 있어야 한다.
- `nfsroot=10.73.0.10:/rpi/<serial>,vers=3,tcp`가 현재 provider의 NFS export와 맞아야 한다. 무료 Lite provider에서는 WinNFSd path file이 `D:\rootfs > /rpi`인지 확인한다.
- 실제 rootfs는 `D:\rootfs\<serial>\etc`, `D:\rootfs\<serial>\usr` 형태가 되어야 한다.

## 실패 시 보는 순서

1. DHCP 요청이 현재 provider에 보이는지. 무료 Lite provider에서는 `D:\logs\rpi-boot-lite.log`를 확인한다.
2. TFTP에서 `<serial>/start4.elf` 요청이 보이는지
3. 커널이 로드되는지
4. NFS mount 단계까지 가는지
5. rootfs 내부 `/etc/fstab`, hostname, SSH 설정이 맞는지

첫 번째 Pi가 SSH까지 안정적으로 들어오면 그 rootfs를 golden template로 삼아 다음 Pi들을 복제한다.

주의: haneWIN은 30일 평가판 제약이 있는 빠른 비교용 provider다. 기본 테스트는 무료 Lite provider를 기준으로 한다.
