# 🚀 RPI PXE Manager

<div align="center">

![Version](https://img.shields.io/badge/version-2.2-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Python](https://img.shields.io/badge/python-3.8+-yellow.svg)

**라즈베리파이 네트워크 부팅 중앙 관리 시스템**

</div>

## 🎯 개요

여러 라즈베리파이를 SD카드 없이 네트워크 부팅으로 운영하는 통합 관리 시스템입니다.

**장점:**
- 📦 중앙 관리 - 한 곳에서 모든 라즈베리파이 관리
- 💾 SD카드 불필요 - 하드웨어 고장 위험 감소
- 🔄 쉬운 업데이트 - 서버 업데이트만으로 전체 적용
- 🚀 즉시 배포 - 새 장치 추가 시 바로 부팅

## ✨ 주요 기능

- 🎮 **터미널 GUI** - 직관적인 메뉴 시스템
- 🖥️ **클라이언트 관리** - IP 자동 할당, MAC 주소 자동완성
- 🌐 **네트워크 부팅** - DHCP/PXE/TFTP/NFS 통합
- 🔐 **SSH 자동 설정** - 모든 클라이언트 원격 접속 가능
- ⚙️ **자동화** - 서비스 관리, 설정 생성, 에러 복구

## 💻 시스템 요구사항

**서버:** Ubuntu 20.04+ / Debian 10+ | 2GB+ RAM | 유선 네트워크  
**클라이언트:** Raspberry Pi 3B+/4B/5 | 네트워크 부팅 활성화 | 유선 연결

## 🚀 빠른 시작

```bash
# 1. 다운로드
git clone https://github.com/minoTrey/rpi-pxe-manager.git
cd rpi-pxe-manager

# 2. 실행
chmod +x pxe
./pxe

# 3. 초기 설정 (메뉴 6번)
# 4. 클라이언트 추가 (메뉴 2→1)
```

## 📖 사용법

### 메인 메뉴
1. 📊 **시스템 상태** - 서버 및 클라이언트 상태
2. 🖥️ **클라이언트 관리** - 추가/제거/편집
3. ⚙️ **서버 설정** - 네트워크/서비스 설정
4. 🚀 **서비스 관리** - 시작/중지/재시작
5. 📝 **로그 확인** - 실시간 모니터링
6. 🔧 **초기 설정** - 자동 설정 마법사

### 클라이언트 추가
```bash
시리얼: [8자리]     # 예: 1234abcd
MAC: [4자리]        # 예: a1b2 (자동완성→88:a2:9e:1b:a1:b2)
IP: [Enter]         # 자동할당 (192.168.0.100부터)
```

## 🌐 네트워크 구성

```
인터넷
  │
  ├── 공유기 (192.168.0.1)
  │     │
  │     ├── PXE 서버 (192.168.0.10)
  │     │
  │     ├── RPi 클라이언트 (192.168.0.100-199)
```

### SSH 접속
```bash
# 서버
ssh user@192.168.0.10

# 클라이언트
ssh pi@192.168.0.100  # 기본 비밀번호: raspberry
```

## 🔧 문제 해결

### 일반적인 문제

**dnsmasq 서비스 중지**
```bash
sudo dnsmasq --test  # 설정 검사
sudo systemctl restart dnsmasq
```

**SSH 접속 불가**
- 라즈베리파이 재부팅 필요
- NFS 환경에서 첫 부팅 시 SSH 자동 활성화됨

**sudo 권한 오류**
- NFS 환경에서 자동으로 권한 수정됨
- 수동 수정: `sudo chmod 4755 /media/rpi-client/*/usr/bin/sudo`

### 진단 명령어
```bash
# 서비스 상태
systemctl status dnsmasq nfs-kernel-server

# 로그 확인
sudo journalctl -u dnsmasq -f

# SSH 포트 확인
for ip in {100..105}; do
    nc -zv 192.168.0.$ip 22 2>&1 | grep -o "succeeded" || echo "닫힘"
done
```

## 📋 고급 설정

### 설정 파일 위치
- 설정: `~/.rpi_pxe_config.json`
- dnsmasq: `/etc/dnsmasq.conf`
- NFS: `/etc/exports`
- 클라이언트: `/media/rpi-client/[시리얼번호]/`

### IP 할당 규칙
- 서버: `192.168.0.10` (고정)
- 클라이언트: `192.168.0.100-199` (고정 할당)
- DHCP: `192.168.0.200-250` (동적)

## 🤝 기여하기

버그 리포트, 기능 제안, 풀 리퀘스트를 환영합니다!

## 📄 라이센스

MIT License

---

<div align="center">

**⭐ 프로젝트가 도움이 되었다면 Star를 눌러주세요!**

</div>