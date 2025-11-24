#!/bin/bash

# RPI PXE Manager GUI 런처
# GUI 버전 실행 스크립트

cd "$(dirname "$0")"

echo "🚀 RPI PXE Manager GUI를 시작합니다..."
echo ""

# Python 버전 확인
if ! command -v python3 &> /dev/null; then
    echo "❌ Python3가 설치되어 있지 않습니다."
    exit 1
fi

# GUI 실행
python3 pxe_gui.py

# 종료 메시지
echo ""
echo "프로그램이 종료되었습니다."
