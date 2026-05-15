# Windows 부팅 서비스 provider 정리

## 결론

기존 Linux 프로그램에서 하던 일은 보통 `dnsmasq`, TFTP 서버, NFS 서버 조합입니다. Windows판에도 같은 역할이 필요합니다.

현재 자동화는 haneWIN을 **빠른 검증용 provider**로만 사용합니다. haneWIN은 미등록 상태에서 30일 평가판으로 동작하므로, 장기 운영 기본 provider로 고정하면 안 됩니다.

장기 운영 방향은 provider를 분리하는 것입니다. 지금 프로젝트에는 우선 `무료 Lite provider`를 추가했습니다. DHCP/TFTP는 프로젝트 안에서 빌드되는 `RpiBootServiceLite.exe`가 담당하고, NFS는 무료 `WinNFSd`가 담당합니다. haneWIN은 빠른 비교/검증용으로만 유지합니다.

## Provider 후보

| Provider | DHCP | TFTP | NFS | 비용/제약 | 판단 |
| --- | --- | --- | --- | --- | --- |
| haneWIN | haneWIN DHCP | haneWIN TFTP | haneWIN NFS | 미등록 30일 평가판 | 빠른 검증 전용. 운영 기본값 아님 |
| 무료 Lite provider | RpiBootServiceLite | RpiBootServiceLite | WinNFSd | 무료, 프로젝트에서 직접 시작/중지 | 현재 Windows Desktop 기본 테스트 경로 |
| 오픈소스 스택 | Open DHCP Server | Tftpd64 | WinNFSd | 무료/오픈소스 계열, 통합 자동화 개발 필요 | Windows Desktop 운영용 후보, 준비 중 |
| Windows Server 스택 | Microsoft DHCP | 별도 TFTP | Server for NFS | Windows Server 필요 | 회사/서버 환경 후보 |
| WSL2/Linux helper | Linux 도구 | Linux 도구 | Linux 도구 | DHCP 브로드캐스트/물리 NIC 바인딩이 까다로움 | rootfs 복제 helper로 우선 사용 |

## 지금 프로그램의 방향

1. `haneWIN` provider는 현재 테스트를 살리는 빠른 검증용으로만 유지합니다.
2. UI와 문서에서는 haneWIN을 “30일 평가판/외부 provider/운영 기본값 아님”으로 명확히 표시합니다.
3. `무료 Lite provider`는 haneWIN 없이 현재 테스트를 진행하기 위한 기본 경로입니다.
4. 다음 provider로 Open DHCP Server + Tftpd64 + WinNFSd 자동 설치/설정 기능을 별도 후보로 유지합니다.
5. Windows Server 또는 Windows 내장 기능을 쓰는 환경도 별도 운영 provider로 분리합니다.
6. Pi rootfs 복제는 Windows 탐색기 복사가 아니라 Linux/WSL/helper 방식으로 처리합니다. 권한, 심볼릭 링크, 소유자가 중요하기 때문입니다.

## 참고 링크

- haneWIN Raspberry Pi Windows netboot guide: https://www.hanewin.net/rpi/remote-rpi-boot.htm
- Raspberry Pi network boot documentation: https://www.raspberrypi.com/documentation/computers/raspberry-pi.html
- Tftpd64 project: https://github.com/PJO2/tftpd64
- WinNFSd project: https://github.com/winnfsd/winnfsd
- Open DHCP Server: https://sourceforge.net/projects/dhcpserver/
