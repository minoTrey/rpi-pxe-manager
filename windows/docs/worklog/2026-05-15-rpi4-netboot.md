# 2026-05-15 작업 로그: RPi4 네트워크 부팅 복구와 운영 기억장

## 오늘의 목표

RPi4 네트워크 부팅이 실제로 어디까지 됐는지 확인하고, Windows 서버 PC에서 haneWIN 평가판에 의존하지 않는 부팅 서비스 방향을 잡고, 중간에 인터럽트가 많아도 다음 작업자가 이어받을 수 있게 순서를 문서화합니다.

## GitHub/Linear 추적

2026-05-15 오후 작업에서 GitHub/Linear를 실제 추적 도구로 붙였습니다.

- GitHub repository: `minoTrey/rpi-pxe-manager`
- Windows판 위치: `windows/`
- 작업 branch: `agent/windows-netboot-manager`
- Draft PR: `https://github.com/minoTrey/rpi-pxe-manager/pull/1`
- First Windows commit: `f4d89e0`
- Linear project: `RPI Netboot Windows`
- Linear issue `3D-5`: P0 rootfs 채우기
- Linear issue `3D-6`: rootfs 준비를 Windows manager/GUI에 연결
- Linear issue `3D-7`: Zero 2 W SD boot + USB gadget 흐름 분리
- Linear issue `3D-8`: 기존 GitHub repo에 Windows판 추가

사용자 결정: 새 GitHub repo를 만들지 않고 기존 `rpi-pxe-manager` repo에 Windows 버전을 추가합니다. Linux 버전과 Windows 버전은 같은 repo 안에서 명확히 분리합니다.

## 시작 시점 상태

- 서버 PC: Windows
- 프로젝트: `C:\Users\test\Documents\workspace\rpi-netboot-windows`
- 운영 저장소: `D:\`
- 서버 PC 이더넷: `10.73.0.10/24`
- 공유기/ipTIME: `10.73.0.1`
- RPi4 테스트 장비:
  - MAC: `88:a2:9e:4f:a9:b1`
  - serial/TFTP prefix: `d80c0b88`
  - IP: `10.73.0.155`
- TFTP 폴더: `D:\tftp\d80c0b88`
- rootfs 폴더: `D:\rootfs\d80c0b88`

## 진행 순서

### 1. 서버 네트워크 기준 고정

서버 PC는 유선 이더넷을 사용하고, Pi 부팅망은 `10.73.0.0/24`로 둡니다. 공유기 관리 페이지는 `10.73.0.1`, 서버 PC는 `10.73.0.10`으로 정했습니다.

확인된 결과:

- 공유기 `10.73.0.1` ping 성공
- 서버 PC 이더넷 `10.73.0.10`
- Wi-Fi는 인터넷용, 유선은 Pi 부팅망용으로 분리

### 2. 저장소 구조 정리

처음에는 `D:\rpi\rpi\...`처럼 경로가 중복될 위험이 있었습니다. 사용자가 이 구조를 싫어했고, 운영 폴더가 D 드라이브 바로 아래 보여야 한다고 했습니다.

결정:

- `D:\tftp`
- `D:\rootfs`
- `D:\iscsi`
- `D:\downloads`

이 구조를 기본으로 유지합니다.

### 3. GUI 자동화 방향 확정

사용자는 매번 PowerShell 명령을 치는 방식이 아니라 더블클릭 가능한 GUI 프로그램을 원했습니다. 그래서 한글 GUI를 기본 실행 경로로 잡았습니다.

현재 실행 파일:

- `RPI-Netboot-Manager.exe`
- `RPI-Netboot-Manager-Admin.exe`
- `RPI-Netboot-Manager-Admin-Update.exe`

중요한 UX 요구:

- 한글 문구가 잘리지 않아야 합니다.
- 로그가 무엇을 검사하는지 설명해야 합니다.
- 버튼 이름은 실제 목적이 드러나야 합니다.
- 도움말 문서는 예쁘고 읽기 쉬워야 합니다.

### 4. haneWIN 평가판 문제 확인

haneWIN은 사용자가 지어낸 이름이 아니라 실제 Windows용 DHCP/TFTP/NFS 계열 제품입니다. 다만 미등록 상태에서는 30일 평가판이라 장기 운영 기본값으로 쓰면 안 됩니다.

결정:

- haneWIN은 비교/검증용 provider로만 취급합니다.
- 기본 운영 방향은 무료 provider입니다.
- 현재 무료 provider는 내장 DHCP/TFTP 서버 + WinNFSd입니다.

### 5. 무료 provider 구성

추가된 구성:

- `src\RpiBootServiceLite\RpiBootServiceLite.cs`
- `tools\lite-provider.ps1`
- `RPI-Netboot-Lite-Provider-Start-Admin.bat`
- `RPI-Netboot-Lite-Provider-Stop-Admin.bat`

역할:

- 내장 C# 서버가 DHCP/TFTP를 처리합니다.
- WinNFSd가 `D:\rootfs`를 `/rpi`로 export합니다.
- haneWIN/PMAPDaemon/pmapd 충돌을 피하도록 stop/preflight 로직을 넣었습니다.

### 6. EEPROM SD 준비와 RPi4 네트워크 부팅 확인

사용자가 S 드라이브에 꽂은 SD카드는 RPi4 EEPROM을 네트워크 부팅 가능 상태로 바꾸기 위한 용도였습니다.

관찰:

- RPi4에 SD카드를 꽂고 켰을 때 초록 화면이 표시됨
- LED 2개 중 하나는 점등, 하나는 빠르게 점멸
- SD카드 제거 후 전원을 다시 넣으니 네트워크 부팅 시작

판단:

- EEPROM 업데이트는 동작한 것으로 봅니다.
- RPi4는 네트워크 부팅 순서로 진입했습니다.

### 7. DHCP/TFTP 성공 확인

RPi4 화면에서 확인된 내용:

```text
DHCP src: 6c:4b:90:3d:08:9b
YI_ADDR 10.73.0.11
SI_ADDR 10.73.0.10

Boot mode NETWORK (02) order f
network 88 a2 9e 4f a9 b1 wait for link TFTP: 0.0.0.0
Link ready
```

이후 커널 로그 화면에서 확인된 내용:

```text
IP-Config: Got DHCP answer from 10.73.0.10, my address is 10.73.0.155
bootserver=10.73.0.10, rootserver=10.73.0.10
```

판단:

- DHCP는 동작했습니다.
- TFTP도 동작했습니다.
- 커널까지 전달됐습니다.

### 8. 현재 부팅 실패 지점 확인

사진에서 핵심 오류:

```text
VFS: Unable to mount root fs via NFS
Kernel panic - not syncing: No working init found
```

의미:

- 커널은 떴습니다.
- 다음 단계인 NFS rootfs 마운트 또는 rootfs 내부 init 실행에서 실패했습니다.
- 현재 가장 큰 원인은 `D:\rootfs\d80c0b88`가 비어 있다는 점입니다.

### 9. NFS/portmapper 충돌 정리

상태 점검에서 haneWIN 계열 `PMAPDaemon` 또는 `pmapd`가 포트 111을 잡는 문제가 있었습니다. 이 포트는 NFS portmapper/rpcbind 계열에서 중요합니다.

조정:

- `lite-provider.ps1`에서 haneWIN 관련 DHCP/TFTP/NFS/PMAP 프로세스를 정리하도록 강화
- WinNFSd 시작 전 111/2049 포트 점유자를 확인
- WinNFSd가 바로 종료되면 로그를 보여주도록 보강

현재 판단:

- 서비스 기동 문제는 상당 부분 정리됐습니다.
- 남은 핵심 blocker는 rootfs 내용입니다.

### 10. RPi4와 Zero 2 W 역할 분리

사용자가 중요한 요구를 추가했습니다.

- RPi4만 네트워크 부팅 대상입니다.
- Zero 2 W는 네트워크 부팅 대상이 아니며, SD 부팅 + USB gadget mode 장치로 준비합니다.
- RPi4와 Zero 2 W는 OS 계열을 맞추고 싶습니다.

결정:

- RPi4: Ethernet netboot
- Zero 2 W: SD boot + USB gadget mode
- 공통 OS 후보: Raspberry Pi OS Lite 64-bit Trixie

추가 후보 스크립트:

- `tools\zero2w-gadget-sd.ps1`
- `tools\rootfs-helper.ps1`

아직 할 일:

- 두 스크립트를 GUI 버튼과 상태 점검에 제대로 연결해야 합니다.
- 문구에서 “Pi 클라이언트” 같은 애매한 표현을 줄이고 RPi4/Zero 2 W를 분리해서 써야 합니다.

### 11. GitHub/Linear 기록 체계 적용

기존 GitHub repo `minoTrey/rpi-pxe-manager`를 확인했습니다. 이 repo는 기존 Linux판의 버전 기록을 이미 갖고 있으므로, Windows판은 새 repo를 만들지 않고 `windows/` 하위 폴더로 추가하기로 했습니다.

Linear에는 `RPI Netboot Windows` 프로젝트를 만들고 남은 작업을 `3D-5`부터 `3D-8`까지 이슈로 분리했습니다.

### 12. manager/GUI 연결 작업

에이전트 작업으로 다음 task가 추가됐습니다.

- `prepare-rpi4-eeprom-sd`
- `prepare-rpi4-rootfs`
- `prepare-zero2w-gadget-sd`

GUI에는 다음 버튼이 추가됐습니다.

- `rootfs 상태 확인`
- `rootfs 준비 안내 만들기`
- `Zero 2 W gadget SD`

확인 사항:

- `rootfs-helper.ps1 status` 실행 성공
- `rootfs-helper.ps1 make-script` 실행 성공
- 생성 파일: `D:\downloads\rpi4-rootfs-import-d80c0b88.sh`
- 생성 파일: `D:\downloads\rpi4-rootfs-import-d80c0b88.txt`

### 13. GitHub PR 생성

기존 `minoTrey/rpi-pxe-manager` repo에서 branch `agent/windows-netboot-manager`를 만들고 Windows판을 `windows/` 폴더로 추가했습니다.

생성된 GitHub 기록:

- Commit: `f4d89e0 Add Windows netboot manager`
- Draft PR: `https://github.com/minoTrey/rpi-pxe-manager/pull/1`

PR에는 다음 내용을 포함했습니다.

- Linux판은 repo root 유지
- Windows판은 `windows/` 하위에 추가
- RPi4만 netboot 대상
- Zero 2 W는 SD boot + USB gadget
- P0 blocker는 `D:\rootfs\d80c0b88`가 비어 있는 것

주의: 최초 커밋 후 생성된 rootfs helper bash 기본값 버그를 고쳤습니다. `SERVER_IP`, `NFS_ALIAS`, `CLIENT_SERIAL`이 빈 문자열로 생성되지 않도록 PowerShell here-string escaping을 수정했습니다.

### 11. GitHub/Linear 운영 방침 확인

작업 추적 도구를 붙이려는 방향을 정리했습니다.

- 현재 원장은 저장소 안 Markdown 문서입니다.
- GitHub가 연결되면 Issues를 작업 원장, Projects를 대시보드, PR을 변경 감사 로그로 씁니다.
- Linear는 GitHub와 연결되는 보조 이슈 관리 도구로만 씁니다. GitHub와 Linear를 따로따로 수동 이중 관리하지 않습니다.

현재 적용한 결정:

- GitHub는 기존 `minoTrey/rpi-pxe-manager` repository를 사용합니다.
- Windows판은 `windows/` 폴더로 분리합니다.
- Linear에는 `RPI Netboot Windows` project를 만들었습니다.
- Linear 남은 작업 이슈는 `3D-5`, `3D-6`, `3D-7`, `3D-8`입니다.

따라서 다음 작업은 GitHub branch `agent/windows-netboot-manager`와 Linear 이슈를 기준으로 진행하되, 실제 장비 상태는 `docs\current-test-status-ko.md`를 우선합니다.

추적 도구에 올릴 남은 작업 후보:

- `rootfs`: `D:\rootfs\d80c0b88`에 실제 Raspberry Pi OS rootfs 준비
- `gui`: rootfs 준비 기능을 GUI 버튼과 상태 점검에 연결
- `zero2w-gadget`: Zero 2 W SD 부팅 + USB gadget 준비 흐름을 RPi4 netboot 흐름에서 분리

## 지금 당장 다음에 할 일

1. 관리자 GUI를 실행합니다.
2. `전체 상태 다시 확인`을 누릅니다.
3. 다음이 정상인지 확인합니다.
   - DHCP UDP 67
   - TFTP UDP 69
   - NFS TCP 2049
   - Portmapper TCP/UDP 111
4. `D:\rootfs\d80c0b88`가 비어 있는지 확인합니다.
5. rootfs 준비 기능을 GUI에 연결합니다.
6. Linux helper 또는 Pi에서 rootfs를 `D:\rootfs\d80c0b88`로 복제합니다.
7. `D:\rootfs\d80c0b88\sbin\init` 또는 `D:\rootfs\d80c0b88\bin\sh`가 생겼는지 확인합니다.
8. RPi4를 SD 없이 재부팅합니다.
9. Zero 2 W 작업은 SD + USB gadget 준비로만 진행하고, RPi4 netboot 대상 목록에 넣지 않습니다.

## 하지 말아야 할 것

- haneWIN을 장기 운영 기본 provider처럼 안내하지 않습니다.
- Windows 탐색기로 Linux rootfs를 대충 복사하지 않습니다.
- Zero 2 W를 네트워크 부팅 대상 목록에 섞지 않습니다.
- `D:\rpi\rpi\...` 같은 중복 경로를 다시 만들지 않습니다.
- 사용자가 매번 PowerShell 명령을 직접 입력해야 하는 흐름으로 되돌리지 않습니다.
- Linux판 루트 파일과 Windows판 `windows/` 파일의 역할을 섞지 않습니다.

## 다음 세션 시작 방법

다음에 작업을 이어갈 때는 이 순서로 읽습니다.

1. `docs\project-memory.md`
2. 이 파일
3. `docs\current-test-status-ko.md`
4. `tools\lite-provider.ps1`
5. `tools\rootfs-helper.ps1`
6. `gui\RpiNetbootManagerGui.cs`

## 2026-05-15 15:25-16:15 RPi4 SD 부팅 기반 rootfs 복제

사용자가 RPi4에 SD카드를 꽂고 Raspberry Pi OS Lite 64-bit Trixie가 부팅되는 것을 확인했습니다. 서버 PC에서 `10.73.0.155` ping과 SSH port 22 open을 확인했습니다.

자동 rootfs import는 한 번 실행됐지만 실패했습니다. Pi 안의 `/boot/firmware/rpi4-netboot-rootfs-import-d80c0b88.log`를 확인한 결과, Pi가 인터넷/DNS를 쓰지 못해 `nfs-common` 설치에 실패했고, `mount.nfs`가 없어 NFS mount가 실패했습니다.

Windows에서 Debian Trixie arm64 패키지 5개를 내려받아 Pi에 복사하고 오프라인 설치했습니다.

- `keyutils_1.6.3-6_arm64.deb`
- `libevent-core-2.1-7t64_2.1.12-stable-10+b1_arm64.deb`
- `libnfsidmap1_2.8.3-1_arm64.deb`
- `rpcbind_1.2.7-1_arm64.deb`
- `nfs-common_2.8.3-1_arm64.deb`

설치 후 Pi에서 `10.73.0.10:/rpi` NFS mount/write 테스트가 성공했습니다.

WinNFSd는 대량 rootfs 쓰기 중 `Input/output error`와 `Stale file handle`을 냈습니다. 이 문제를 줄이기 위해 `tools\rootfs-helper.ps1`에서 생성하는 rsync 옵션을 다음 방향으로 바꿨습니다.

- `--inplace`: 임시 파일 생성 후 rename하는 패턴 회피
- `--whole-file`: 델타 계산보다 단순 전송 우선
- `--omit-dir-times`: directory mtime 설정 오류 감소
- `/usr/include`, `/usr/share/doc`, `/usr/share/man`, `/usr/share/info`, apt cache/list 제외
- UTF-8 BOM 없는 bash script 생성

기존 깨진 partial rootfs는 삭제하지 않고 `D:\rootfs\d80c0b88.failed-20260515-155755`로 보존했습니다. 새 `D:\rootfs\d80c0b88`에 다시 복제했고, rsync는 일부 비필수 파일 오류로 code 23을 냈지만 부팅 핵심 파일은 준비됐습니다.

확인된 핵심 파일:

- `D:\rootfs\d80c0b88\bin\sh`
- `D:\rootfs\d80c0b88\sbin\init`
- `D:\rootfs\d80c0b88\usr\lib\systemd\systemd`
- `D:\rootfs\d80c0b88\usr\lib\modules`
- `D:\rootfs\d80c0b88\etc\fstab`

`etc\fstab`는 NFS rootfs용으로 수정했습니다. Pi에서 NFS로 rootfs 핵심 파일을 읽는 검증은 `ROOTFS_NFS_READ_OK`로 통과했습니다. 이후 Pi에 `poweroff`를 보냈습니다.

다음 물리 작업:

1. RPi4 전원이 완전히 내려간 것을 확인합니다.
2. SD카드를 제거합니다.
3. SD 없이 전원을 다시 넣습니다.
4. 화면에 나오는 새 메시지와 `D:\logs\rpi-boot-lite.log`를 같이 확인합니다.
