# 새 RPi4 네트워크 부팅 복제 Runbook

이 문서는 이미 성공한 RPi4 `d80c0b88` 구성을 기준으로, 새 Raspberry Pi 4를 SD카드 없이 네트워크 부팅 클라이언트로 빠르게 등록하고 복제하기 위한 운영 절차입니다.

## 현재 기준

| 항목 | 값 |
| --- | --- |
| 서버 PC | `10.73.0.10` |
| 공유기 | `10.73.0.1` |
| 성공한 RPi4 | `d80c0b88`, `88:a2:9e:4f:a9:b1`, `10.73.0.155` |
| bootfs/TFTP | `D:\tftp\d80c0b88` |
| rootfs/NFS | `D:\rootfs\d80c0b88` |
| 성공 verdict | `BOOT_REACHED_USERSPACE` |

haneWIN은 성공을 증명하는 데만 사용합니다. 30일 평가판이므로 운영 provider로 쓰면 안 됩니다.

## 목표 흐름

```text
EEPROM 네트워크 부팅 설정
-> 새 RPi4 serial/MAC 확인
-> clone-rpi4-client.ps1 clone 실행
-> D:\tftp\<serial> 생성
-> D:\rootfs\<serial> 생성
-> DHCP 예약 추가
-> provider 재시작 또는 reload
-> 새 RPi4 전원 재인가
-> harness verdict 기록
```

사용자가 직접 해야 하는 물리 작업은 새 Pi 전원을 뺐다 꽂는 것까지로 제한합니다.

## 복제 명령

먼저 계획을 확인합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\tools\clone-rpi4-client.ps1 plan -Config .\windows\lab-10.73.json
```

새 Pi를 등록하고 복제합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\tools\clone-rpi4-client.ps1 clone `
  -Config .\windows\lab-10.73.json `
  -GoldenSerial d80c0b88 `
  -DeviceId rpi-001 `
  -Serial <새Pi8자리시리얼> `
  -Mac <새PiMAC주소>
```

IP를 지정하지 않으면 `10.73.0.100-199` 범위에서 다음 빈 주소를 자동으로 고릅니다.

## 자동화가 하는 일

- `windows/lab-10.73.json`에 새 RPi4 client를 추가합니다.
- `D:\tftp\d80c0b88`를 `D:\tftp\<serial>`로 복제합니다.
- `D:\rootfs\d80c0b88`를 `D:\rootfs\<serial>`로 복제합니다.
- 새 `cmdline.txt`가 `/rpi/<serial>` rootfs를 보도록 고칩니다.
- `etc/hostname`, `etc/hosts`, `etc/machine-id`, SSH host key를 새 Pi용으로 정리합니다.
- `/etc/rpi-netboot/client.json`과 `/etc/rpi-netboot/client.env`를 만들어 내부 프로그램이 `rpi-001` 같은 기기 번호를 읽을 수 있게 합니다.
- cloud-init이 hostname/hosts를 다시 덮어쓰지 않도록 `99-rpi-netboot-identity.cfg`를 넣습니다.
- 기존 성공 client `d80c0b88`는 덮어쓰지 않습니다.

## UI에서 새 기기 만들기

프로그램에서 `새 RPi4 등록/복제`를 누르면 아래 값을 입력합니다.

| 입력 | 예시 | 의미 |
| --- | --- | --- |
| 기기 번호 | `rpi-001` | hostname과 내부 프로그램용 device id |
| RPi4 시리얼 | `a1b2c3d4` | TFTP/rootfs 폴더 이름 |
| MAC 주소 | `88:a2:9e:aa:bb:cc` | DHCP 예약 |
| 예약 IP | 비움 또는 `10.73.0.160` | 비우면 자동 할당 |

완료 후 생성되는 내부 설정:

```text
/etc/hostname
/etc/hosts
/etc/rpi-netboot/client.json
/etc/rpi-netboot/client.env
```

`client.json`에는 device id, serial, MAC, IP, 서버 IP가 들어갑니다. 지금 Zero 2 W gadget peer는 `10.73.0.11` 힌트로 남깁니다.

## 안전 규칙

- `d80c0b88`는 known-good 기준입니다. 복제 대상 serial로 쓰면 안 됩니다.
- 대상 `D:\tftp\<serial>` 또는 `D:\rootfs\<serial>`에 파일이 이미 있으면 기본적으로 중단합니다.
- Pi가 `D:\rootfs\d80c0b88`에서 실행 중이면 골든 템플릿 승격은 Pi를 정상 종료한 뒤에 합니다.
- haneWIN은 proof-only입니다. 운영 provider로 선택하지 않습니다.

## Provider 결정

현재 추천 순서:

1. 즉시 실험: WinNFSd를 haneWIN 성공 cmdline과 같은 최소 profile로 재시험합니다.
2. 안정 운영: Windows GUI + Linux NFS appliance 구조로 갑니다.
3. Windows-only 장기 대안: iSCSI root disk를 별도 검토합니다.

Linux NFS appliance 구조:

```text
Windows
  - GUI
  - DHCP/TFTP
  - client registry
  - bootfs generation

Linux helper/appliance
  - ext4 storage
  - nfs-kernel-server
  - golden rootfs clone
  - per-Pi exports
```

## 성공 판정

새 Pi 첫 부팅에서 아래가 모두 보여야 합니다.

```text
DHCP ACK
TFTP GET/DONE kernel8.img
TFTP GET/DONE cmdline.txt
NFS root mount
systemd/userspace reached
login 또는 SSH 가능
```

하네스 verdict는 `BOOT_REACHED_USERSPACE` 또는 그보다 명확한 성공 상태가 되어야 합니다.

## 실패 분기

| 증상 | 먼저 볼 곳 |
| --- | --- |
| DHCP ACK 없음 | MAC 예약, 이더넷 링크, 공유기 대역 |
| TFTP 요청 없음 | EEPROM boot order, DHCP option, TFTP listener |
| TFTP 파일 실패 | `D:\tftp\<serial>` 파일 세트 |
| NFS mount 실패 | provider, `cmdline.txt`, export alias |
| init 실패 | rootfs 파일 표현, NFS provider, Linux metadata |

## 기록

복제/부팅 결과는 아래에 남깁니다.

- Obsidian: `windows/knowledge/obsidian-vault/Timeline.md`
- GBrain: `windows/knowledge/gbrain/graph.json`
- Hermes: `windows/knowledge/hermes/events.jsonl`
- GitHub PR #1
- Linear `3D-5`
