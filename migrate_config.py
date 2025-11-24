#!/usr/bin/env python3
"""
기존 dnsmasq 설정에서 클라이언트 정보를 추출하여
~/.rpi_pxe_config.json 파일을 생성하는 마이그레이션 스크립트
"""

import json
import re
from pathlib import Path


def parse_dnsmasq_config():
    """dnsmasq.conf에서 클라이언트 정보 추출"""
    clients = []

    # dnsmasq.conf 읽기
    dnsmasq_conf = Path('/etc/dnsmasq.conf')

    if not dnsmasq_conf.exists():
        print("❌ /etc/dnsmasq.conf 파일을 찾을 수 없습니다.")
        return clients

    try:
        with open(dnsmasq_conf, 'r') as f:
            content = f.read()

        # dhcp-host 라인 찾기
        # 형식: dhcp-host=88:a2:9e:1b:e3:ac,192.168.0.101,d3a76dcf,infinite
        pattern = r'dhcp-host=([0-9a-f:]+),([0-9.]+),([^,]+),'

        matches = re.findall(pattern, content)

        for mac, ip, serial in matches:
            client = {
                'serial': serial,
                'hostname': serial,  # 시리얼을 호스트명으로 사용
                'mac': mac,
                'ip': ip,
                'online': False
            }
            clients.append(client)

        print(f"✅ {len(clients)}개의 클라이언트를 찾았습니다.")

    except Exception as e:
        print(f"❌ 오류 발생: {e}")

    return clients


def create_config_file(clients):
    """설정 파일 생성"""
    config_file = Path.home() / '.rpi_pxe_config.json'

    # 기본 설정
    config = {
        'server_ip': '192.168.0.10',
        'dhcp_range_start': '192.168.0.100',
        'dhcp_range_end': '192.168.0.200',
        'network_interface': 'eth0',
        'nfs_root': '/media/rpi-client',
        'tftp_root': '/tftpboot',
        'clients': clients
    }

    # 파일 저장
    try:
        with open(config_file, 'w') as f:
            json.dump(config, f, indent=2)

        print(f"✅ 설정 파일이 생성되었습니다: {config_file}")
        print(f"   등록된 클라이언트: {len(clients)}개")

        # 생성된 클라이언트 목록 표시
        if clients:
            print("\n📋 등록된 클라이언트:")
            print(f"  {'번호':<4} {'시리얼':<12} {'IP 주소':<15} {'MAC 주소':<20}")
            print(f"  {'-'*55}")
            for i, client in enumerate(sorted(clients, key=lambda c: c['ip']), 1):
                print(f"  {i:<4} {client['serial']:<12} {client['ip']:<15} {client['mac']:<20}")

        return True

    except Exception as e:
        print(f"❌ 설정 파일 생성 실패: {e}")
        return False


def main():
    print("🔄 기존 클라이언트 정보 마이그레이션 시작...\n")

    # 기존 설정 파일 확인
    config_file = Path.home() / '.rpi_pxe_config.json'
    if config_file.exists():
        print(f"⚠️  경고: 설정 파일이 이미 존재합니다: {config_file}")
        response = input("   덮어쓰시겠습니까? (y/n): ").lower()
        if response != 'y':
            print("취소되었습니다.")
            return
        print()

    # dnsmasq 설정에서 클라이언트 추출
    clients = parse_dnsmasq_config()

    if not clients:
        print("\n⚠️  등록된 클라이언트가 없습니다.")
        print("   기본 설정 파일만 생성합니다.")

    # 설정 파일 생성
    if create_config_file(clients):
        print("\n✅ 마이그레이션 완료!")
        print("   이제 GUI 프로그램에서 기존 클라이언트를 확인할 수 있습니다.")
        print("\n실행 방법:")
        print("  ./run_gui.sh")
        print("  또는")
        print("  python3 pxe_gui.py")
    else:
        print("\n❌ 마이그레이션 실패")


if __name__ == "__main__":
    main()
