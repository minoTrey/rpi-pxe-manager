#!/bin/bash

echo "RPI PXE Manager 설치 스크립트"
echo "==============================="

# Python 버전 확인
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')

if [ -z "$PYTHON_VERSION" ]; then
    echo "❌ Python3가 설치되어 있지 않습니다."
    echo "다음 명령으로 설치해주세요: sudo apt install python3 python3-pip"
    exit 1
fi

echo "✓ Python 버전: $PYTHON_VERSION (3.8+ 지원, 기본 설치 버전 사용)"

# 버전 체크 (3.8 이상인지 확인)
PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d. -f1)
PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d. -f2)

if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 8 ]); then
    echo "⚠️  Python 3.8 이상이 권장되지만 계속 진행합니다."
fi

# pip 확인
if ! command -v pip3 &> /dev/null; then
    echo "❌ pip3가 설치되어 있지 않습니다."
    echo "다음 명령으로 설치해주세요: sudo apt install python3-pip"
    exit 1
fi

# 가상환경 생성 (선택사항)
read -p "Python 가상환경을 생성하시겠습니까? (권장) [Y/n]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    if ! command -v virtualenv &> /dev/null; then
        echo "virtualenv 설치 중..."
        pip3 install virtualenv
    fi
    
    echo "가상환경 생성 중..."
    python3 -m venv venv
    source venv/bin/activate
    echo "✓ 가상환경이 활성화되었습니다."
fi

# 의존성 설치
echo "Python 패키지 설치 중..."
pip3 install -r requirements.txt

if [ $? -eq 0 ]; then
    echo "✓ 모든 패키지가 성공적으로 설치되었습니다."
else
    echo "❌ 패키지 설치 중 오류가 발생했습니다."
    exit 1
fi

# 스크립트 파일 확인
echo "필수 스크립트 파일 확인 중..."
SCRIPTS=("setup_server.sh" "setup_client.sh" "create_new_client.sh" "dnsmasq_config.sh")
MISSING_SCRIPTS=()

for script in "${SCRIPTS[@]}"; do
    if [ ! -f "../$script" ]; then
        MISSING_SCRIPTS+=("$script")
    fi
done

if [ ${#MISSING_SCRIPTS[@]} -gt 0 ]; then
    echo "⚠️  다음 스크립트 파일을 찾을 수 없습니다:"
    for script in "${MISSING_SCRIPTS[@]}"; do
        echo "   - $script"
    done
    echo ""
    echo "이 파일들은 상위 디렉토리에서 복사해주세요:"
    echo "cp ../{setup_server.sh,setup_client.sh,create_new_client.sh,dnsmasq_config.sh} ./"
else
    # 스크립트 복사
    echo "스크립트 파일 복사 중..."
    cp ../setup_server.sh ../setup_client.sh ../create_new_client.sh ../dnsmasq_config.sh ./
    chmod +x *.sh
    echo "✓ 스크립트 파일이 복사되었습니다."
fi

# 실행 권한 설정
chmod +x rpi_pxe_server.py
chmod +x client/rpi-pxe-client.py

echo ""
echo "==============================================="
echo "✅ 설치가 완료되었습니다!"
echo "==============================================="
echo ""
echo "서버를 시작하려면 다음 명령을 실행하세요:"
if [ -f "venv/bin/activate" ]; then
    echo "  source venv/bin/activate  # 가상환경 활성화"
    echo "  sudo env PATH=\$PATH python3 rpi_pxe_server.py  # 가상환경용"
else
    echo "  sudo python3 rpi_pxe_server.py  # 시스템 전역 설치용"
fi
echo ""
echo "웹 브라우저에서 http://localhost:5000 으로 접속하세요."
echo ""