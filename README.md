# 🚀 RPI PXE Manager - 라즈베리파이 네트워크 부팅 관리 시스템

<div align="center">

![Version](https://img.shields.io/badge/version-2.1-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Python](https://img.shields.io/badge/python-3.8+-yellow.svg)
![Platform](https://img.shields.io/badge/platform-Raspberry%20Pi-red.svg)

**라즈베리파이를 SD카드 없이 네트워크로 부팅하고 중앙에서 관리하는 올인원 솔루션**

[설치](#-빠른-시작) • [기능](#-주요-기능) • [사용법](#-사용법) • [문제해결](#-문제-해결)

</div>

---

## 📋 목차

- [개요](#-개요)
- [주요 기능](#-주요-기능)
- [시스템 요구사항](#-시스템-요구사항)
- [빠른 시작](#-빠른-시작)
- [사용법](#-사용법)
  - [메인 메뉴](#메인-메뉴)
  - [초기 설정 마법사](#1-초기-설정-마법사)
  - [클라이언트 관리](#2-클라이언트-관리)
  - [서버 설정](#3-서버-설정)
  - [서비스 관리](#4-서비스-관리)
- [네트워크 구성](#-네트워크-구성)
- [문제 해결](#-문제-해결)
- [고급 설정](#-고급-설정)

---

## 🎯 개요

RPI PXE Manager는 여러 대의 라즈베리파이를 SD카드 없이 네트워크 부팅으로 운영할 수 있게 해주는 통합 관리 시스템입니다. 한 대의 서버에서 모든 라즈베리파이의 OS와 파일을 중앙 관리할 수 있어, 대규모 라즈베리파이 클러스터 운영에 최적화되어 있습니다.

### 왜 네트워크 부팅인가?

- **📦 중앙 관리**: 모든 라즈베리파이를 한 곳에서 관리
- **💾 SD카드 불필요**: SD카드 고장 걱정 없음
- **🔄 쉬운 업데이트**: 서버에서 한 번만 업데이트하면 모든 클라이언트에 적용
- **🚀 빠른 배포**: 새 라즈베리파이 추가 시 즉시 부팅 가능
- **💰 비용 절감**: SD카드 구매 비용 절약

---

## ✨ 주요 기능

### 🎮 올인원 관리 시스템
- **터미널 기반 GUI**: 직관적인 메뉴 시스템
- **원클릭 설정**: 복잡한 설정을 자동으로 처리
- **실시간 모니터링**: 시스템 상태 실시간 확인

### 🖥️ 클라이언트 관리
- **자동 IP 할당**: 순차적 IP 자동 배정 (192.168.0.100부터)
- **MAC 주소 자동완성**: 라즈베리파이 MAC 주소 빠른 입력
- **시리얼 번호 기반 관리**: 각 라즈베리파이를 시리얼 번호로 식별
- **템플릿 복사**: 기존 클라이언트에서 새 클라이언트로 시스템 복사

### 🌐 네트워크 기능
- **DHCP/PXE 통합**: dnsmasq를 이용한 통합 서비스
- **NFS 루트 파일시스템**: 네트워크 파일시스템 자동 구성
- **TFTP 부트 서버**: 부트 파일 자동 관리
- **IP 충돌 방지**: 공유기와 충돌 없는 안전한 설정

### 🛠️ 자동화 기능
- **서비스 자동 시작**: 필요한 서비스 자동 관리
- **설정 파일 자동 생성**: 복잡한 설정 파일 자동 작성
- **에러 자동 복구**: 일반적인 문제 자동 해결

---

## 💻 시스템 요구사항

### 서버 (PXE 서버)
- **OS**: Ubuntu 20.04+ 또는 Debian 10+
- **RAM**: 최소 2GB (권장 4GB+)
- **저장공간**: 클라이언트당 8GB + 여유 공간
- **네트워크**: 유선 이더넷 연결 필수
- **권한**: sudo 권한 필요

### 클라이언트 (라즈베리파이)
- **모델**: Raspberry Pi 3B+, 4B, 5 (PXE 부팅 지원 모델)
- **부팅 설정**: EEPROM에서 네트워크 부팅 활성화
- **네트워크**: 유선 이더넷 연결 필수

### 필수 패키지 (자동 설치됨)
```bash
dnsmasq          # DHCP/PXE/TFTP 서버
nfs-kernel-server # NFS 파일 공유
python3-pip      # Python 패키지 관리
psutil           # 시스템 모니터링
netifaces        # 네트워크 인터페이스 관리
```

---

## 🚀 빠른 시작

### 1️⃣ 다운로드 및 실행

```bash
# 저장소 클론
git clone https://github.com/minoTrey/rpi-pxe-manager.git
cd rpi-pxe-manager

# 실행 권한 부여
chmod +x pxe

# 프로그램 실행 (자동으로 sudo 권한 요청)
./pxe
```

### 2️⃣ 초기 설정 마법사 실행

프로그램 실행 후 메뉴에서 `6. 초기 설정 마법사` 선택

```
🚀 원클릭 PXE 부팅 설정 마법사
모든 설정을 자동으로 구성합니다!

자동 설정을 시작하시겠습니까? (Y/n): Y
```

### 3️⃣ 첫 번째 클라이언트 추가

```bash
# 메인 메뉴에서 2 → 1 선택
2. 클라이언트 관리
  1. 새 클라이언트 추가

시리얼 번호: eb2a1f17
MAC 주소: e30f  # 마지막 4자리만 입력!
고정 IP 주소 [192.168.0.100]: [Enter]  # 자동 할당
```

---

## 📖 사용법

### 메인 메뉴

```
========================================================
       RPI PXE Manager - 터미널 관리 시스템
========================================================

메인 메뉴:
  1. 📊 시스템 상태 확인
  2. 🖥️  클라이언트 관리
  3. ⚙️  서버 설정
  4. 🚀 서비스 관리
  5. 📝 로그 확인
  6. 🔧 초기 설정 마법사
  0. 🚪 종료
```

### 1. 초기 설정 마법사

처음 시작할 때 반드시 실행해야 합니다:

```bash
# 메인 메뉴에서 6번 선택
6. 🔧 초기 설정 마법사

# 자동 설정 진행
✓ 네트워크 인터페이스 자동 감지
✓ 서버 IP 고정 (192.168.0.10)
✓ Netplan 설정 (고정 IP)
✓ dnsmasq 통합 설정 생성
✓ NFS/TFTP 디렉토리 생성
✓ 서비스 자동 시작
```

**중요**: 초기 설정 후 네트워크가 재시작됩니다. SSH 연결이 끊길 수 있습니다.

### 2. 클라이언트 관리

#### 새 클라이언트 추가

```bash
# 메인 메뉴 → 2 → 1
2. 🖥️ 클라이언트 관리
  1. 새 클라이언트 추가

# 입력 예시
시리얼 번호: eb2a1f17         # 8자리 16진수
MAC 주소: e3:0f               # 마지막 4자리만 입력!
고정 IP 주소 [192.168.0.100]: # Enter로 자동 할당
```

#### MAC 주소 빠른 입력
```
모든 라즈베리파이 MAC: 88:a2:9e:1b:XX:XX
마지막 4자리만 입력하면 자동 완성!

예시: 
- e30f → 88:a2:9e:1b:e3:0f
- e4:2b → 88:a2:9e:1b:e4:2b
```

#### IP 할당 규칙
```
고정 IP 범위: 192.168.0.100-199 (100개)
동적 DHCP 범위: 192.168.0.200-250

- 192.168.0.100: 첫 번째 클라이언트
- 192.168.0.101: 두 번째 클라이언트
- ... 순차적 자동 할당
```

#### SD카드에서 시스템 복사

기존 Raspberry Pi OS SD카드에서 시스템을 복사:

```bash
# 메인 메뉴 → 2 → 5
5. SD 카드에서 시스템 복사

# SD카드 삽입 후
사용 가능한 장치:
  1. /dev/sda (32GB SD Card)
  
대상 클라이언트: eb2a1f17
복사 시작 (약 10-20분 소요)
```

### 3. 서버 설정 변경

#### 네트워크 설정
```bash
# 메인 메뉴 → 3 → 1
1. 네트워크 인터페이스 변경

현재: enp0s31f6
사용 가능한 인터페이스:
  1. enp0s31f6 (192.168.0.10)
  2. wlan0 (not recommended)
```

#### dnsmasq 설정 재생성
```bash
# 메인 메뉴 → 3 → 4
4. DHCP/PXE 설정 재생성

✓ /etc/dnsmasq.conf 통합 설정 생성
✓ 고정 IP 범위: 100-199
✓ DHCP 동적 범위: 200-250
✓ dnsmasq 서비스 재시작
```

### 4. 서비스 관리

서비스 상태 확인 및 재시작:

```bash
# 메인 메뉴 → 4
서비스 관리:
  1. 모든 서비스 시작
  2. 모든 서비스 중지
  3. 서비스 재시작
  4. 서비스 상태 확인

현재 상태:
✅ dnsmasq (DHCP/TFTP)
✅ nfs-kernel-server (NFS)
✅ rpcbind (RPC)
```

### 5. 문제 진단

#### 로그 확인
```bash
# 메인 메뉴 → 5
로그 확인:
  1. dnsmasq 로그 (DHCP/TFTP)
  2. NFS 로그
  3. 시스템 로그
  4. 부팅 로그 (특정 클라이언트)
```

#### 실시간 모니터링
```bash
# dnsmasq 실시간 로그
sudo journalctl -u dnsmasq -f

# 네트워크 부팅 과정 확인
# SI_ADDR: 192.168.0.10 (정상)
# IP 할당: 192.168.0.100
# TFTP 파일 전송 상태
```

---

## 🔧 문제 해결

### ❌ 일반적인 문제와 해결법

#### 1. "SI_ADDR에 192.168.0.1이 표시됨"

**원인:** dnsmasq 설정이 잘못됨

**해결:**
```bash
# dnsmasq 재시작
sudo systemctl restart dnsmasq

# 설정 확인
cat /etc/dnsmasq.d/pxe-main.conf
```

#### 2. "Emergency mode로 부팅됨"

**원인:** fstab 설정 문제

**해결:**
```bash
# 클라이언트 fstab 확인
sudo nano /media/rpi-client/{serial}/etc/fstab

# 최소 설정으로 변경
proc /proc proc defaults 0 0
```

#### 3. "DHCP IP를 받지 못함"

**원인:** 네트워크 인터페이스 설정 오류

**해결:**
```bash
# 네트워크 인터페이스 확인
ip link show

# pxe 프로그램에서 인터페이스 재설정
3. 서버 설정 → 1. 네트워크 인터페이스 변경
```

#### 4. "sudo: /usr/lib/sudo/sudoers.so must be owned by uid 0"

**원인:** NFS 파일시스템에서 sudo 바이너리 및 플러그인 권한 문제

**해결:** 
```bash
# pxe 프로그램이 자동으로 처리하지만, 수동 수정이 필요한 경우:
sudo chown root:root /media/rpi-client/{serial}/usr/bin/sudo
sudo chmod 4755 /media/rpi-client/{serial}/usr/bin/sudo
sudo chown -R root:root /media/rpi-client/{serial}/usr/lib/sudo
sudo chmod 755 /media/rpi-client/{serial}/usr/lib/sudo/sudoers.so
```

#### 5. "dnsmasq 서비스가 계속 중지됨"

**원인:** dnsmasq.conf 파일의 문법 오류 (특히 dhcp-option=252 설정)

**해결:**
```bash
# 설정 파일 문법 검사
sudo dnsmasq --test

# 문제가 있는 라인 확인 및 제거
sudo nano /etc/dnsmasq.conf
```

### 📋 진단 명령어

```bash
# dnsmasq 로그 확인
sudo tail -f /var/log/dnsmasq.log

# NFS 공유 확인
showmount -e localhost

# TFTP 파일 확인
ls -la /tftpboot/

# 포트 사용 확인
sudo netstat -tulpn | grep -E '(67|69|111|2049)'
```

---

## ⚙️ 고급 설정

### 사용자 정의 설정 파일

설정 파일 위치: `~/.rpi_pxe_config.json`

```json
{
  "server_ip": "192.168.0.10",
  "network_interface": "enp0s31f6",
  "nfs_root": "/media/rpi-client",
  "tftp_root": "/tftpboot",
  "clients": [
    {
      "serial": "eb2a1f17",
      "hostname": "eb2a1f17",
      "mac": "88:a2:9e:1b:e3:0f",
      "ip": "192.168.0.100"
    }
  ]
}
```

### dnsmasq 설정 파일

**메인 설정**: `/etc/dnsmasq.d/pxe-main.conf`
```conf
interface=enp0s31f6
bind-interfaces

# DHCP 범위 설정
# DHCP 서버 활성화 (고정 IP만 할당, 동적 범위 없음)
# 각 클라이언트는 client-*.conf 파일에서 개별 설정

# 게이트웨이 설정
dhcp-option=3,192.168.0.1

# DNS 서버 설정
dhcp-option=6,8.8.8.8,8.8.4.4

# PXE 부팅 기본 설정
dhcp-boot=bootcode.bin

# TFTP 서버 활성화
enable-tftp
tftp-root=/tftpboot
```

**클라이언트별 설정**: `/etc/dnsmasq.d/client-{serial}.conf`
```conf
# Fixed IP for eb2a1f17
dhcp-host=88:a2:9e:1b:e3:0f,192.168.0.100,eb2a1f17,12h

# PXE boot path for this client
dhcp-boot=tag:88:a2:9e:1b:e3:0f,eb2a1f17/bootcode.bin
```

### NFS 공유 설정

`/etc/exports` 파일:
```
/media/rpi-client/eb2a1f17 *(rw,sync,no_subtree_check,no_root_squash)
```

### 부트 설정 파일

`/tftpboot/{serial}/cmdline.txt`:
```
console=serial0,115200 console=tty1 root=/dev/nfs 
nfsroot=192.168.0.10:/media/rpi-client/{serial},vers=4.1,proto=tcp 
rw ip=dhcp rootwait
```

---

## 🌐 네트워크 구성

### 기본 네트워크 구조

```
인터넷
  │
  ├── 공유기 (192.168.0.1)
  │     │
  │     ├── PXE 서버 (192.168.0.10)
  │     │
  │     ├── RPi 클라이언트 #1 (192.168.0.100)
  │     ├── RPi 클라이언트 #2 (192.168.0.101)
  │     ├── RPi 클라이언트 #3 (192.168.0.102)
  │     └── ... 
```

### IP 할당 규칙

| 장치 | IP 범위 | 설명 |
|------|---------|------|
| 공유기 | 192.168.0.1 | 기본 게이트웨이 |
| PXE 서버 | 192.168.0.10 | 고정 IP |
| RPi 클라이언트 | 192.168.0.100-199 | 고정 IP만 할당 |
| 기타 장치 | 공유기 DHCP 사용 | 공유기에서 관리 |

### 포트 사용

| 포트 | 프로토콜 | 서비스 | 설명 |
|------|----------|--------|------|
| 22 | TCP | SSH | 원격 접속 |
| 67 | UDP | DHCP | IP 주소 할당 |
| 69 | UDP | TFTP | 부트 파일 전송 |
| 111 | TCP/UDP | RPC | NFS 지원 |
| 2049 | TCP/UDP | NFS | 루트 파일시스템 |
| 4011 | UDP | PXE | PXE 부팅 |

---

## 🚨 주의사항

### ⚠️ 중요 안전 수칙

1. **백업 필수**: 시스템 변경 전 항상 백업
2. **네트워크 격리**: 가능하면 별도 네트워크 구성
3. **보안 설정**: NFS 접근 제한 설정 권장
4. **전원 관리**: UPS 사용 권장 (전원 차단 시 파일시스템 손상 가능)

### 🔒 보안 권장사항

- NFS를 특정 IP 범위로만 제한
- 방화벽 규칙 설정
- 정기적인 시스템 업데이트
- 불필요한 서비스 비활성화

---

## 📚 추가 자료

### 유용한 링크
- [라즈베리파이 공식 PXE 부팅 가이드](https://www.raspberrypi.org/documentation/hardware/raspberrypi/bootmodes/net.md)
- [dnsmasq 매뉴얼](http://www.thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html)
- [NFS 설정 가이드](https://ubuntu.com/server/docs/service-nfs)

### 관련 프로젝트
- [PiServer](https://github.com/raspberrypi/piserver) - 라즈베리파이 공식 솔루션
- [LTSP](https://ltsp.org/) - Linux Terminal Server Project

---

## 🤝 기여하기

버그 리포트, 기능 제안, 풀 리퀘스트를 환영합니다!

---

## 📄 라이센스

이 프로젝트는 MIT 라이센스 하에 배포됩니다.

---

<div align="center">

**⭐ 이 프로젝트가 도움이 되었다면 Star를 눌러주세요!**

Made with ❤️ for Raspberry Pi Community

</div>