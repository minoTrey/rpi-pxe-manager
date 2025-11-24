#!/usr/bin/env python3
"""GUI 설정 로드 테스트"""

import json
from pathlib import Path

config_file = Path.home() / '.rpi_pxe_config.json'

print("🔍 GUI 설정 파일 테스트\n")
print(f"설정 파일: {config_file}")
print(f"존재 여부: {config_file.exists()}")

if config_file.exists():
    with open(config_file, 'r') as f:
        config = json.load(f)

    print(f"\n✅ 설정 파일 정상 로드")
    print(f"   서버 IP: {config.get('server_ip')}")
    print(f"   네트워크 인터페이스: {config.get('network_interface')}")
    print(f"   클라이언트 수: {len(config.get('clients', []))}")

    clients = config.get('clients', [])
    if clients:
        print(f"\n📋 처음 5개 클라이언트:")
        for i, client in enumerate(clients[:5], 1):
            print(f"   {i}. {client['serial']:<12} {client['ip']:<15} {client['mac']}")

        if len(clients) > 5:
            print(f"   ... 외 {len(clients) - 5}개")

    print("\n✅ GUI에서 이 클라이언트들이 모두 표시되어야 합니다!")
else:
    print("\n❌ 설정 파일이 없습니다!")
    print("   migrate_config.py를 실행하세요.")
