#!/usr/bin/env python3
"""
RPI PXE Manager Demo Server
실제 시스템 서비스 없이도 웹 UI를 보여주는 데모용 서버
"""
import json
import random
import time
from flask import Flask, render_template, jsonify

app = Flask(__name__)

def generate_demo_status():
    """데모용 시스템 상태 생성"""
    return {
        'server': {
            'ip': '192.168.0.10/24',
            'dhcp_range': '192.168.0.11 - 192.168.0.100',
            'interface': 'eth0',
            'cpu_percent': random.uniform(15, 45),
            'memory_percent': random.uniform(30, 60),
            'disk_usage': random.uniform(25, 55)
        },
        'services': {
            'dnsmasq': True,
            'nfs': True
        },
        'clients': [
            {
                'serial': '10000000a1b2c3d4',
                'hostname': 'rpi4-a1b2c3d4',
                'ip': '192.168.0.11',
                'online': True
            },
            {
                'serial': '10000000e5f6g7h8',
                'hostname': 'rpi4-e5f6g7h8',
                'ip': '192.168.0.12',
                'online': True
            },
            {
                'serial': '10000000i9j0k1l2',
                'hostname': 'rpi4-i9j0k1l2',
                'ip': '192.168.0.13',
                'online': False
            },
            {
                'serial': '10000000m3n4o5p6',
                'hostname': 'rpi4-m3n4o5p6',
                'ip': '192.168.0.14',
                'online': True
            }
        ]
    }

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/status')
def api_status():
    return jsonify(generate_demo_status())

@app.route('/api/setup-server', methods=['POST'])
def setup_server():
    return jsonify({
        'success': True, 
        'output': 'DEMO: 서버 설정이 성공적으로 완료되었습니다!'
    })

@app.route('/api/setup-client', methods=['POST'])
def setup_client():
    return jsonify({
        'success': True, 
        'output': 'DEMO: 클라이언트 설정이 성공적으로 완료되었습니다!'
    })

@app.route('/api/create-client', methods=['POST'])
def create_client():
    return jsonify({
        'success': True, 
        'output': 'DEMO: 새 클라이언트가 성공적으로 생성되었습니다!'
    })

@app.route('/api/mounted-sdcards')
def mounted_sdcards():
    return jsonify([
        {
            'device': '/dev/sdb2',
            'mountpoint': '/media/user/raspios',
            'size': '32G'
        },
        {
            'device': '/dev/sdc1',
            'mountpoint': '/media/user/backup',
            'size': '16G'
        }
    ])

@app.route('/api/logs/<service>')
def service_logs(service):
    demo_logs = {
        'dnsmasq': """Jan 20 10:15:32 pxe-server dnsmasq[1234]: started, version 2.80
Jan 20 10:15:32 pxe-server dnsmasq[1234]: compile time options: IPv6 GNU-getopt DBus
Jan 20 10:15:32 pxe-server dnsmasq[1234]: DHCP, IP range 192.168.0.11 -- 192.168.0.100, lease time 12h
Jan 20 10:16:15 pxe-server dnsmasq[1234]: DHCP packet received on eth0 which has no address
Jan 20 10:16:45 pxe-server dnsmasq[1234]: DHCPDISCOVER(eth0) dc:a6:32:xx:xx:xx
Jan 20 10:16:45 pxe-server dnsmasq[1234]: DHCPOFFER(eth0) 192.168.0.11 dc:a6:32:xx:xx:xx
Jan 20 10:16:46 pxe-server dnsmasq[1234]: DHCPREQUEST(eth0) 192.168.0.11 dc:a6:32:xx:xx:xx
Jan 20 10:16:46 pxe-server dnsmasq[1234]: DHCPACK(eth0) 192.168.0.11 dc:a6:32:xx:xx:xx rpi4-a1b2c3d4""",
        'nfs-kernel-server': """Jan 20 10:15:30 pxe-server systemd[1]: Starting NFS server and services...
Jan 20 10:15:31 pxe-server exportfs[5678]: exporting *:/mnt/ssd/rpi4-a1b2c3d4
Jan 20 10:15:31 pxe-server exportfs[5678]: exporting *:/mnt/ssd/rpi4-e5f6g7h8
Jan 20 10:15:31 pxe-server systemd[1]: Started NFS server and services.
Jan 20 10:16:20 pxe-server rpc.mountd[9012]: authenticated mount request from 192.168.0.11:1023 for /mnt/ssd/rpi4-a1b2c3d4
Jan 20 10:16:45 pxe-server rpc.mountd[9012]: authenticated mount request from 192.168.0.12:1024 for /mnt/ssd/rpi4-e5f6g7h8"""
    }
    
    return jsonify({'logs': demo_logs.get(service, '로그를 찾을 수 없습니다.')})

@app.route('/api/config', methods=['GET', 'POST'])
def config():
    demo_config = {
        'server_ip': '192.168.0.10',
        'dhcp_range_start': '192.168.0.11',
        'dhcp_range_end': '192.168.0.100',
        'interface': 'eth0'
    }
    
    if request.method == 'POST':
        return jsonify({'success': True, 'config': demo_config})
    else:
        return jsonify(demo_config)

if __name__ == '__main__':
    print("🎬 RPI PXE Manager 데모 서버 시작")
    print("📸 스크린샷용 데모 모드입니다")
    print("🌐 브라우저에서 http://localhost:5000 접속")
    print("")
    print("💡 실제 기능은 작동하지 않지만 UI는 완전히 동작합니다!")
    
    app.run(host='0.0.0.0', port=5000, debug=True)