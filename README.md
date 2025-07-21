# RPI PXE Manager

Raspberry Pi PXE Boot Manager - Python 기반의 웹 UI로 네트워크 부팅 환경을 쉽게 구성할 수 있는 프로그램입니다.

## 개요

이 프로젝트는 Raspberry Pi 4의 PXE 네트워크 부팅 환경을 쉽게 구성하고 관리할 수 있도록 도와줍니다. Flask 웹 프레임워크 기반의 서버와 Python 클라이언트 도구를 제공하여 복잡한 설정 과정을 단순화했습니다.

## 주요 기능

### 서버 컴포넌트 (Python/Flask)
- 웹 기반 관리 인터페이스
- 실시간 서비스 상태 모니터링 (DNSMASQ, NFS)
- 시스템 리소스 모니터링 (CPU, 메모리, 디스크)
- 클라이언트 상태 확인 (온라인/오프라인)
- 원클릭 서버 초기 설정
- SD 카드 자동 감지 및 클라이언트 설정
- 기존 클라이언트 복제를 통한 새 클라이언트 추가
- 서비스 로그 뷰어

### 클라이언트 컴포넌트
- EEPROM 자동 업데이트 (네트워크 부팅 활성화)
- SSH 서비스 활성화
- 자동 로그인 설정
- 네트워크 부팅 테스트 도구
- 대화형 설정 인터페이스

## 시스템 요구사항

### 서버
- Ubuntu 22.04 이상
- Python 3.8 이상
- 고정 IP 주소 (기본: 192.168.0.10)
- 유선 이더넷 연결

### 클라이언트
- Raspberry Pi 4
- 네트워크 부팅 가능한 EEPROM
- 유선 이더넷 연결

## 설치 방법

### 1. 저장소 클론
```bash
git clone https://github.com/minoTrey/rpi-pxe-manager.git
cd rpi-pxe-manager
```

### 2. 서버 설치 및 실행

```bash
# 기존 PXE 설정 스크립트 복사
cp ../setup_server.sh ./
cp ../setup_client.sh ./
cp ../create_new_client.sh ./
cp ../dnsmasq_config.sh ./

# Python 의존성 설치
pip3 install -r requirements.txt

# 서버 실행 (sudo 권한 필요)
sudo python3 rpi_pxe_server.py
```

웹 브라우저에서 `http://서버IP:5000` 으로 접속합니다.

### 3. 클라이언트 설정

Raspberry Pi에서:

```bash
# 클라이언트 스크립트 다운로드
wget https://raw.githubusercontent.com/minoTrey/rpi-pxe-manager/main/client/rpi-pxe-client.py
chmod +x rpi-pxe-client.py

# 대화형 설정 실행
sudo ./rpi-pxe-client.py

# 또는 개별 명령 실행
sudo ./rpi-pxe-client.py --update-eeprom  # EEPROM만 업데이트
sudo ./rpi-pxe-client.py --enable-ssh     # SSH만 활성화
sudo ./rpi-pxe-client.py --test          # 네트워크 부팅 테스트
```

## 사용 방법

### 서버 초기 설정
1. 웹 UI에서 "서버 초기 설정" 버튼 클릭
2. 자동으로 네트워크 설정, DNSMASQ, NFS 구성

### 첫 클라이언트 추가
1. Raspberry Pi OS가 설치된 SD 카드를 서버에 연결
2. 웹 UI에서 "첫 클라이언트 설정" 클릭
3. 시리얼 번호 입력 및 SD 카드 선택
4. 자동으로 파일시스템 복사 및 설정

### 추가 클라이언트 생성
1. 웹 UI에서 "새 클라이언트 추가" 클릭
2. 복사할 소스 클라이언트 선택
3. 새 Raspberry Pi의 시리얼 번호 입력
4. (선택) MAC 주소로 DHCP 예약 설정

## 프로젝트 구조

```
rpi-pxe-manager/
├── rpi_pxe_server.py      # Flask 서버 메인 파일
├── templates/             # HTML 템플릿
│   └── index.html        # 웹 UI 메인 페이지
├── static/               # 정적 파일
│   ├── css/
│   │   └── style.css     # 스타일시트
│   └── js/
│       └── app.js        # 클라이언트 JavaScript
├── client/               # 클라이언트 컴포넌트
│   └── rpi-pxe-client.py # Python 설정 스크립트
├── requirements.txt      # Python 의존성
└── README.md            # 이 파일
```

## 문제 해결

### 서버가 시작되지 않는 경우
- sudo 권한으로 실행했는지 확인
- 5000 포트가 사용 중인지 확인
- Python 3.8 이상이 설치되어 있는지 확인
- 모든 의존성이 설치되었는지 확인 (`pip3 install -r requirements.txt`)

### 클라이언트가 부팅되지 않는 경우
- EEPROM이 업데이트되었는지 확인
- 네트워크 케이블이 제대로 연결되었는지 확인
- DHCP 서비스가 실행 중인지 확인

### 서비스 로그 확인
```bash
sudo journalctl -u dnsmasq -f
sudo journalctl -u nfs-kernel-server -f
```

## 라이센스

MIT License

## 기여

이슈 및 PR은 언제나 환영합니다!

## 참고

이 프로젝트는 [RPI-PXE](https://github.com/original/RPI-PXE) 프로젝트의 설정 스크립트를 기반으로 하여 사용자 친화적인 인터페이스를 추가한 것입니다.