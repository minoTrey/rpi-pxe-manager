# 현재 테스트 상태

마지막 업데이트: 2026-05-20 17:14 KST

## 결론

RPi4 `d80c0b88`는 Windows 서버 PC에서 제공한 bootfs/rootfs로 userspace까지 부팅한 이력이 있다.

```text
verdict: BOOT_REACHED_USERSPACE
attempt: 20260519-144335-d80c0b88-hanewin-systemd-explicit
cmdline: nfsroot=10.73.0.10:/rpi/d80c0b88,vers=3 init=/usr/sbin/init
```

haneWIN은 성공 경로 검증용으로만 남기고, 이 PC에서는 제거했다. 현재 부팅 서비스는 `RpiBootServiceLite`와 프로젝트 로컬 `WinNFSd` 경로를 사용한다.

## 활성 작업 기준

활성 폴더:

```text
C:\Users\test\Documents\workspace\rpi-pxe-manager\windows
```

활성 실행 파일:

```text
C:\Users\test\Documents\workspace\rpi-pxe-manager\windows\RPI-Netboot-Manager.exe
```

`C:\Users\test\Documents\workspace\rpi-netboot-windows`는 레거시 스냅샷이다.

## 장비와 주소

| 항목 | 값 |
| --- | --- |
| 서버 PC Ethernet | `10.73.0.10/24` |
| 공유기 | `10.73.0.1` |
| 테스트 RPi4 MAC | `88:a2:9e:4f:a9:b1` |
| 테스트 RPi4 serial | `d80c0b88` |
| 테스트 RPi4 예약 IP | `10.73.0.155` |
| 현재 저장소 root | `D:\` |
| TFTP 경로 | `D:\tftp\d80c0b88` |
| Windows rootfs 경로 | `D:\rootfs\d80c0b88` |
| 다운로드 캐시 | `windows\cache\downloads` |

## 2026-05-20 변경 결과

- 루트 `AGENTS.md`를 복원해 Codex/agent 작업 규칙을 repo에 고정했다.
- haneWIN 서비스와 설치 폴더를 PC에서 제거했다. proof 로그는 `D:\logs`에 보존했다.
- GUI SD 쓰기 전에 물리 디스크를 선택하게 했다.
- `D:\downloads`의 모든 항목을 `windows\cache\downloads`로 옮겼고, `D:\downloads`는 비어 있다.
- GUI 기본 SD 작업을 `RPi4 EEPROM SD`에서 `RPi4 OS SD 작성`으로 바꿨다.
- 기본 OS 이미지는 `2026-04-21-raspios-trixie-arm64-lite.img`이다.
- `저장소 설정`과 `저장소 열기` 버튼은 이제 `서버 PC 준비` 화면에서만 보인다.

## OS SD 상태

현재 GUI 기본 쓰기 대상 이미지:

```text
windows\cache\downloads\2026-04-21-raspios-trixie-arm64-lite.img
Raspberry Pi OS Lite 64-bit Trixie
Image size: 3.01 GB
```

검증:

```text
powershell -File tools\rpi-sd-card.ps1 download-rpios-lite-trixie -CacheDir .\windows\cache\downloads
Source: cache
```

현재 Windows 디스크 후보:

```text
Disk 3
Generic STORAGE DEVICE
USB
29.72 GB
MBR
IsBoot: false
IsSystem: false
```

주의: 이 디스크를 선택하고 쓰기를 진행하면 전체 내용이 지워진다.

## EEPROM SD 참고

EEPROM 이미지는 여전히 프로젝트 캐시에 남아 있으나, GUI의 기본 흐름은 더 이상 EEPROM SD 작성이 아니다.

```text
windows\cache\downloads\rpi-boot-eeprom-recovery-2026-01-09-2711-vl805-000138c0-network\
SHA256 43639F3D17C53D47C1E54D6B6C9229BB095014A15A93BD948717B45343EA22F7
```

## 새 RPi4 복제 순서

1. GUI에서 `RPi4 OS SD 작성`을 실행해 OS SD를 만든다.
2. 새 RPi4를 그 OS SD로 부팅한다.
3. RPi OS에서 serial/MAC을 확인한다.

   ```bash
   cat /proc/cpuinfo | grep Serial
   cat /sys/class/net/eth0/address
   ```

4. 필요하면 OS에서 EEPROM/network boot order를 업데이트한다.
5. GUI에서 `새 RPi4 등록/복제`를 실행한다.
6. DHCP 예약이 바뀌면 `부팅 서비스 시작`을 다시 실행한다.
7. SD를 제거하고 새 RPi4를 Ethernet netboot로 확인한다.

## 다음 액션

1. 새 GUI를 실행한다.
2. `RPi4 OS SD 작성` 버튼의 구조와 확인 문구를 점검한다.
3. 사용자가 직접 디스크를 선택하고 쓰기 버튼을 누르는 과정을 모니터링한다.
4. 쓰기 후 Disk 3 파티션/볼륨 상태를 확인한다.
