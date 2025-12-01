# RPI PXE Manager

![Version](https://img.shields.io/badge/version-2.7-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Python](https://img.shields.io/badge/python-3.8+-yellow.svg)

**라즈베리파이 네트워크 부팅(PXE) 중앙 관리 시스템**

여러 라즈베리파이를 SD카드 없이 네트워크 부팅으로 운영하는 통합 관리 시스템입니다.

## 주요 기능

- **CLI / GUI 지원** - 터미널 또는 그래픽 인터페이스 선택
- **클라이언트 관리** - 추가, 편집, 삭제, 온라인 상태 확인
- **네트워크 부팅** - DHCP/PXE/TFTP/NFS 통합 관리
- **원격 제어** - SSH로 재부팅, 종료, 시스템 정보 확인
- **서비스 관리** - dnsmasq, NFS 서버 제어

## 시스템 요구사항

**서버**
- Ubuntu 20.04+ / Debian 10+
- Python 3.8+
- 유선 네트워크 연결

**클라이언트**
- Raspberry Pi 3B+ / 4B / 5
- 네트워크 부팅 활성화
- 유선 연결

## 설치

### 1. 시스템 패키지
```bash
sudo apt update
sudo apt install -y dnsmasq nfs-kernel-server sshpass python3-pyqt5
```

### 2. Python 패키지
```bash
pip install psutil netifaces
```

### 3. 프로그램 다운로드
```bash
git clone https://github.com/user/rpi-pxe-manager.git
cd rpi-pxe-manager
chmod +x pxe
```

## 사용법

### CLI 실행
```bash
./pxe
```

### GUI 실행
```bash
python3 pxe_gui_qt.py
```

## 메뉴 구성

### CLI 메뉴
1. 시스템 상태 - 서버 및 클라이언트 상태 확인
2. 클라이언트 관리 - 추가/편집/삭제/백업
3. 서버 설정 - 네트워크 설정 변경
4. 서비스 관리 - dnsmasq/NFS 제어
5. 로그 확인 - 실시간 로그 모니터링
6. 초기 설정 - 자동 설정 마법사

### GUI 기능
- **대시보드** - CPU, 메모리, 디스크, 서비스 상태
- **클라이언트 관리** - 목록 보기, 상세 정보, 편집, 삭제
- **서버 설정** - IP, DHCP 범위, 경로 설정
- **서비스 관리** - 시작/중지/재시작
- **NFS 설정** - exports 생성, cmdline.txt 경로 수정

## 클라이언트 추가

```
시리얼: 12345678     (8자리, RPi 시리얼)
MAC: e3:0f           (마지막 4자리 → 자동완성: 88:a2:9e:1b:e3:0f)
IP: [Enter]          (자동 할당: 192.168.0.100~)
```

## 네트워크 구성

```
인터넷
  │
  └── 공유기 (192.168.0.1)
        │
        ├── PXE 서버 (192.168.0.10)
        │     - dnsmasq (DHCP/TFTP/PXE)
        │     - NFS 서버
        │
        └── RPi 클라이언트 (192.168.0.100~199)
```

## 설정 파일 위치

| 파일 | 경로 |
|------|------|
| 프로그램 설정 | `~/.rpi_pxe_config.json` |
| 클라이언트 백업 | `./clients_backup.json` |
| dnsmasq 설정 | `/etc/dnsmasq.conf` |
| NFS exports | `/etc/exports` |
| TFTP 부팅 파일 | `/tftpboot/[시리얼]/` |
| NFS 루트 | `/media/polygom3d/rpi-client/[시리얼]/` |

## SSH 접속

```bash
# 클라이언트 접속
ssh pi@192.168.0.100
# 기본 비밀번호: raspberry
```

## 문제 해결

### dnsmasq 서비스 실패
```bash
sudo dnsmasq --test          # 설정 검사
sudo journalctl -u dnsmasq   # 로그 확인
sudo systemctl restart dnsmasq
```

### 네트워크 인터페이스 오류
설정 파일에서 `network_interface`가 실제 인터페이스명과 일치하는지 확인:
```bash
ip link show   # 인터페이스 목록 확인
```

### NFS 마운트 실패
```bash
sudo exportfs -ra            # exports 리로드
sudo systemctl restart nfs-kernel-server
```

## 라이센스

MIT License
