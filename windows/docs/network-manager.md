# 네트워크 관리자 운영 메모

이 문서는 현재 Raspberry Pi netboot 실험망의 고정 운영 계획을 기록한다. 대상 망은 `10.73.0.0/24`이며, 실험 장비는 ipTIME 공유기의 LAN 포트에만 연결한다.

## 주소 계획

| 역할 | 주소 | 비고 |
| --- | --- | --- |
| ipTIME LAN 관리 주소 | `10.73.0.1/24` | 공유기 관리자 페이지와 기본 LAN 주소 |
| 서버 PC 유선 Ethernet | `10.73.0.10/24` | 기본 게이트웨이를 설정하지 않음 |
| 클라이언트 예약 시작 | `10.73.0.101` 이상 | Raspberry Pi 및 실험 클라이언트 MAC별 예약 |

서버 PC의 Ethernet 인터페이스에는 `10.73.0.10`, 서브넷 마스크 `255.255.255.0`만 설정한다. 기본 게이트웨이는 비워 둔다. 이렇게 해야 서버 PC의 일반 인터넷 경로는 Wi-Fi 또는 기존 업무망이 계속 담당하고, 실험망 Ethernet은 `10.73.0.0/24` 내부 통신에만 사용된다.

## DHCP 충돌 방지 규칙

- 같은 `10.73.0.0/24` LAN 안에서 DHCP 서버는 한 번에 하나만 응답해야 한다.
- Raspberry Pi netboot 시험 중 Windows 서버 PC의 DHCP/TFTP 도구가 DHCP를 제공하면 ipTIME DHCP 서버는 끈다.
- ipTIME DHCP를 켜야 하는 점검 상황에서는 Windows DHCP/TFTP 도구의 DHCP 기능을 끈다.
- ipTIME의 동적 DHCP 풀을 사용할 때는 서버 PC 주소 `10.73.0.10`과 클라이언트 예약 대역 `10.73.0.101` 이상이 겹치지 않게 한다.
- 클라이언트 고정 예약은 `10.73.0.101`부터 순서대로 배정한다. 예: 첫 번째 Pi `10.73.0.101`, 두 번째 Pi `10.73.0.102`.
- `10.73.0.1`은 ipTIME, `10.73.0.10`은 서버 PC 전용으로 예약하고 다른 장비에 배정하지 않는다.
- 새 예약을 추가하기 전에 같은 IP가 이미 응답하는지 확인한다. 응답이 있거나 ARP에 다른 MAC이 보이면 예약하지 않는다.
- MAC 주소 하나에 IP 하나만 예약한다. 같은 MAC에 여러 예약을 만들거나, 같은 IP를 여러 MAC에 중복 예약하지 않는다.
- 기존 DHCP 임대가 남아 있으면 ipTIME 또는 Windows DHCP 도구에서 임대를 삭제한 뒤 클라이언트를 재부팅하거나 DHCP 갱신을 수행한다.

## 검증 명령

아래 명령은 관리자 PowerShell에서 실행한다. 유선 어댑터 이름이 `Ethernet`이 아니면 첫 명령으로 실제 이름을 확인한 뒤 `$IfAlias` 값만 바꾼다.

```powershell
Get-NetAdapter | Sort-Object Name | Format-Table -Auto Name, Status, MacAddress, LinkSpeed
```

```powershell
$IfAlias = "Ethernet"
Get-NetIPAddress -InterfaceAlias $IfAlias -AddressFamily IPv4 |
  Format-Table -Auto IPAddress, PrefixLength, InterfaceAlias
```

정상 기준: 서버 PC Ethernet에 `10.73.0.10`과 `PrefixLength` `24`가 보인다.

```powershell
$IfAlias = "Ethernet"
Get-NetRoute -InterfaceAlias $IfAlias -AddressFamily IPv4 |
  Sort-Object DestinationPrefix |
  Format-Table -Auto DestinationPrefix, NextHop, RouteMetric, InterfaceAlias
```

정상 기준: `0.0.0.0/0` 기본 경로가 Ethernet 인터페이스에 없어야 한다. `10.73.0.0/24` 온링크 경로만 있으면 된다.

```powershell
$IfAlias = "Ethernet"
Get-NetRoute -InterfaceAlias $IfAlias -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
```

정상 기준: 아무 출력도 없어야 한다. 출력이 있으면 Ethernet에 기본 게이트웨이가 설정된 상태다.

```powershell
Test-Connection -ComputerName 10.73.0.1 -Count 4
```

정상 기준: ipTIME `10.73.0.1`에서 4회 응답한다.

```powershell
Test-Connection -ComputerName 10.73.0.10 -Count 2
```

정상 기준: 서버 PC 자신의 `10.73.0.10` 주소가 응답한다.

```powershell
arp -a | Select-String "10\.73\.0\."
```

정상 기준: `10.73.0.1`과 부팅 또는 연결된 클라이언트의 `10.73.0.101` 이상 주소가 보인다. 같은 IP에 MAC이 바뀌어 나타나면 DHCP 예약 충돌을 의심한다.

```powershell
ipconfig /all
```

정상 기준: Ethernet 어댑터의 IPv4 주소는 `10.73.0.10`, 서브넷 마스크는 `255.255.255.0`, 기본 게이트웨이는 비어 있다.

```powershell
Get-NetUDPEndpoint -LocalPort 67,69 -ErrorAction SilentlyContinue |
  Format-Table -Auto LocalAddress, LocalPort, OwningProcess
```

정상 기준: netboot DHCP/TFTP 서비스를 켠 상태에서는 서버 PC에서 UDP `67` 또는 `69` 리스너가 보인다. ipTIME DHCP를 사용하는 점검 상황에서는 Windows DHCP 리스너가 없어야 한다.

```powershell
Get-NetTCPConnection -LocalPort 2049 -State Listen -ErrorAction SilentlyContinue |
  Format-Table -Auto LocalAddress, LocalPort, State, OwningProcess
```

정상 기준: NFS를 켠 상태에서는 TCP `2049` 리스너가 보인다. 사용하는 NFS 구현에 따라 UDP `2049`도 함께 확인한다.

```powershell
.\tools\check-lab-10.73.ps1
```

정상 기준: 라우터 `10.73.0.1` ping이 성공하고, 설치한 DHCP/TFTP/NFS 서비스의 포트 상태가 의도한 값과 일치한다.
