# RPI Netboot Windows Vault

## 바로 보기

- [[Current-State]]
- [[Timeline]]
- [[NFS-Provider-Matrix]]
- [[Linux-NFS-Next]]
- [[Tooling-Map]]

## 현재 목표

Windows 서버 PC는 DHCP/TFTP 관리 UI와 자동화의 중심으로 유지합니다. RPi4만 네트워크 부팅 대상입니다. Zero 2 W는 SD 부팅 + USB gadget mode 대상으로 별도 흐름입니다.

## 현재 판단

haneWIN UDP에서 Pi가 NFS mount negotiation까지 도달했지만 `invalid argument`로 실패했습니다. 다음 성공 가능성이 가장 높은 실험은 Linux `nfs-kernel-server` provider A/B입니다.
