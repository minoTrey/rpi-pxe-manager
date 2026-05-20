# 현재 테스트 상태

마지막 업데이트: 2026-05-20 16:35 KST

## 결론

RPi4 `d80c0b88`는 Windows 서버 PC에서 제공한 bootfs/rootfs로 userspace까지 부팅한 이력이 있습니다.

최신 성공 판정:

```text
verdict: BOOT_REACHED_USERSPACE
attempt: 20260519-144335-d80c0b88-hanewin-systemd-explicit
cmdline: nfsroot=10.73.0.10:/rpi/d80c0b88,vers=3 init=/usr/sbin/init
```

주의: haneWIN은 성공 경로 검증용으로만 남깁니다. 장기 운영 provider로 고정하지 않습니다.

## 현재 작업 기준

활성 폴더:

```text
C:\Users\test\Documents\workspace\rpi-pxe-manager\windows
```

활성 실행파일:

```text
C:\Users\test\Documents\workspace\rpi-pxe-manager\windows\RPI-Netboot-Manager.exe
```

`C:\Users\test\Documents\workspace\rpi-netboot-windows`는 구버전 스냅샷입니다. 다음 세션에서는 active workspace로 쓰지 않습니다.

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
| 최신 성공 증거 폴더 | `D:\logs\netboot-harness\20260519-144335-d80c0b88-hanewin-systemd-explicit` |

## 2026-05-20 정리 결과

- GUI에서 `권장 순서`, `자동화 UI 빌드` 제거.
- haneWIN/평가판/provider 실험 문구를 실행파일 표면에서 제거.
- 버튼, 여백, 색상, 글씨 크기, 한글 폰트 fallback 개선.
- GUI에서 저장소 위치를 직접 지정 가능. 항상 `D:\`라고 가정하지 않음.
- 도움말/문서 버튼 중복 제거.
- 실행파일/배치 파일 표면은 `RPI-Netboot-Manager.exe` 하나만 남김.
- Pi 4 EEPROM 이미지 캐시를 `D:\downloads`가 아니라 프로젝트 내부 `windows\cache\downloads`로 이동.

## EEPROM SD 확인

Pi 4 Network Boot EEPROM 이미지:

```text
windows\cache\downloads\rpi-boot-eeprom-recovery-2026-01-09-2711-vl805-000138c0-network\rpi-boot-eeprom-recovery-2026-01-09-2711-vl805-000138c0-network.img
```

검증 해시:

```text
SHA256 43639F3D17C53D47C1E54D6B6C9229BB095014A15A93BD948717B45343EA22F7
```

현재 EEPROM SD 상태:

```text
Disk 3
Generic STORAGE DEVICE
USB
29.72 GB
MBR
Partition 1: FAT32 XINT13, 256 MiB
IsBoot: false
IsSystem: false
```

상태: GUI에서 물리 디스크 선택 창을 확인한 뒤 Disk 3에 Pi 4 Network Boot EEPROM 이미지를 썼습니다. 더 이상 `S:` 고정으로 쓰지 않습니다.

## 2026-05-20 16:35 추가 확인

- 루트 `AGENTS.md`를 복원해 Codex/agent 작업 규칙을 repo에 고정했습니다.
- haneWIN 서비스와 설치 폴더를 PC에서 제거했습니다.
- haneWIN proof 로그는 `D:\logs`에 보존했습니다.
- 현재 부팅 서비스는 `RpiBootServiceLite`와 프로젝트 로컬 `WinNFSd`로 실행 중입니다.
- `RPi4 EEPROM SD`는 쓰기 전에 물리 디스크를 선택하게 바뀌었습니다.
- Disk 3 EEPROM SD 쓰기 후 상태는 MBR + 256 MiB FAT32 XINT13 파티션입니다.

## 새 RPi4 복제 순서

현재 구현은 새 RPi4의 serial/MAC을 수동 입력해야 합니다.

1. `RPi4 EEPROM SD`로 Pi 4 EEPROM SD를 만든다.
2. 새 RPi4를 그 SD로 한 번 부팅해 EEPROM을 network boot 가능 상태로 바꾼다.
3. 전원을 끄고 SD를 뺀다.
4. 새 RPi4의 serial과 MAC을 확인한다.

   ```bash
   cat /proc/cpuinfo | grep Serial
   cat /sys/class/net/eth0/address
   ```

   Serial이 `10000000d80c0b88`처럼 나오면 GUI에는 마지막 8자리 `d80c0b88` 형식으로 입력한다.

5. GUI에서 `새 RPi4 등록/복제`를 실행한다.
6. 기기 번호, serial, MAC, 필요 시 IP를 입력한다.
7. `부팅 서비스 시작`을 다시 눌러 DHCP 예약을 반영한다.
8. 새 RPi4를 SD 없이 Ethernet만 연결하고 전원을 다시 넣는다.

현재 로그는 unknown MAC을 잡을 수 있습니다.

```text
DHCP ignored unknown MAC 88:36:6c:fa:64:b8
```

하지만 serial은 자동 확정하지 못합니다. 다음 개선 후보는 이 unknown MAC을 복제 dialog 후보로 보여주는 기능입니다.

## 다음 액션

1. 새 RPi4를 완성된 EEPROM SD로 한 번 부팅.
2. 전원을 끄고 SD 제거.
3. 새 RPi4 serial/MAC 확보.
4. `새 RPi4 등록/복제` 실행.
5. DHCP 예약이 바뀌면 `부팅 서비스 시작` 재실행.
6. SD 제거 상태에서 새 RPi4 netboot 확인.
