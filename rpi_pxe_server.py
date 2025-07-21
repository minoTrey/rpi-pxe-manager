#!/usr/bin/env python3
import os
import sys
import subprocess
import json
import threading
import time
from pathlib import Path
from datetime import datetime
from flask import Flask, render_template, request, jsonify, Response, session
from flask_socketio import SocketIO, emit
import psutil
import netifaces

app = Flask(__name__)
app.config['SECRET_KEY'] = 'rpi-pxe-secret-key-2024'
socketio = SocketIO(app, cors_allowed_origins="*")

# 전역 변수
SCRIPTS_PATH = Path(__file__).parent.parent
CONFIG_FILE = Path.home() / '.rpi-pxe-manager.json'

class PXEServerManager:
    def __init__(self):
        self.config = self.load_config()
        self.status_thread = None
        self.running = True
        
    def load_config(self):
        if CONFIG_FILE.exists():
            with open(CONFIG_FILE, 'r') as f:
                return json.load(f)
        return {
            'server_ip': '192.168.0.10',
            'dhcp_range_start': '192.168.0.11',
            'dhcp_range_end': '192.168.0.100',
            'interface': self.get_default_interface()
        }
    
    def save_config(self):
        with open(CONFIG_FILE, 'w') as f:
            json.dump(self.config, f, indent=2)
    
    def get_default_interface(self):
        """기본 이더넷 인터페이스 찾기"""
        interfaces = netifaces.interfaces()
        for iface in interfaces:
            if iface.startswith('e'):  # eth, enp 등
                addrs = netifaces.ifaddresses(iface)
                if netifaces.AF_INET in addrs:
                    return iface
        return 'eth0'
    
    def check_service(self, service_name):
        """서비스 상태 확인"""
        try:
            result = subprocess.run(['systemctl', 'is-active', service_name], 
                                  capture_output=True, text=True)
            return result.stdout.strip() == 'active'
        except:
            return False
    
    def get_system_status(self):
        """시스템 상태 정보 수집"""
        status = {
            'server': {
                'ip': '',
                'dhcp_range': '',
                'interface': self.config.get('interface', ''),
                'cpu_percent': psutil.cpu_percent(interval=1),
                'memory_percent': psutil.virtual_memory().percent,
                'disk_usage': psutil.disk_usage('/').percent
            },
            'services': {
                'dnsmasq': self.check_service('dnsmasq'),
                'nfs': self.check_service('nfs-kernel-server')
            },
            'clients': []
        }
        
        # 서버 IP 확인
        try:
            netplan_file = Path('/etc/netplan/01-netcfg.yaml')
            if netplan_file.exists():
                content = netplan_file.read_text()
                import re
                ip_match = re.search(r'addresses:\s*\[\s*([^\]]+)\s*\]', content)
                if ip_match:
                    status['server']['ip'] = ip_match.group(1).strip()
        except:
            pass
        
        # DHCP 범위 확인
        try:
            dnsmasq_conf = Path('/etc/dnsmasq.conf')
            if dnsmasq_conf.exists():
                content = dnsmasq_conf.read_text()
                import re
                range_match = re.search(r'dhcp-range=([^,]+),([^,]+)', content)
                if range_match:
                    status['server']['dhcp_range'] = f"{range_match.group(1)} - {range_match.group(2)}"
        except:
            pass
        
        # 클라이언트 정보
        try:
            serials_file = SCRIPTS_PATH / 'rpi_serials.txt'
            ips_file = SCRIPTS_PATH / 'rpi_ips.txt'
            
            if serials_file.exists():
                serials = serials_file.read_text().strip().split('\n')
                serials = [s for s in serials if s]
                
                ips_dict = {}
                if ips_file.exists():
                    for line in ips_file.read_text().strip().split('\n'):
                        if ':' in line:
                            serial, ip = line.split(':', 1)
                            ips_dict[serial.strip()] = ip.strip()
                
                for serial in serials:
                    client = {
                        'serial': serial,
                        'hostname': f'rpi4-{serial}',
                        'ip': ips_dict.get(serial, ''),
                        'online': False
                    }
                    
                    # Ping 테스트
                    if client['ip']:
                        try:
                            result = subprocess.run(['ping', '-c', '1', '-W', '1', client['ip']], 
                                                  capture_output=True)
                            client['online'] = result.returncode == 0
                        except:
                            pass
                    
                    status['clients'].append(client)
        except Exception as e:
            print(f"클라이언트 정보 로드 오류: {e}")
        
        return status
    
    def execute_script(self, script_name, args=None, callback=None):
        """스크립트 실행"""
        script_path = SCRIPTS_PATH / script_name
        
        if not script_path.exists():
            return {'success': False, 'error': f'스크립트를 찾을 수 없습니다: {script_name}'}
        
        cmd = ['sudo', 'bash', str(script_path)]
        if args:
            cmd.extend(args)
        
        try:
            process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, 
                                     text=True, bufsize=1)
            
            output = []
            error_output = []
            
            # 실시간 출력
            while True:
                stdout_line = process.stdout.readline()
                stderr_line = process.stderr.readline()
                
                if stdout_line:
                    output.append(stdout_line.rstrip())
                    if callback:
                        callback('output', stdout_line.rstrip())
                    socketio.emit('script_output', {
                        'script': script_name,
                        'data': stdout_line.rstrip()
                    })
                
                if stderr_line:
                    error_output.append(stderr_line.rstrip())
                    if callback:
                        callback('error', stderr_line.rstrip())
                    socketio.emit('script_error', {
                        'script': script_name,
                        'data': stderr_line.rstrip()
                    })
                
                if process.poll() is not None:
                    break
            
            return_code = process.wait()
            
            return {
                'success': return_code == 0,
                'output': '\n'.join(output),
                'error': '\n'.join(error_output),
                'code': return_code
            }
            
        except Exception as e:
            return {'success': False, 'error': str(e)}
    
    def get_mounted_sdcards(self):
        """마운트된 SD 카드 목록"""
        sdcards = []
        
        try:
            result = subprocess.run(['lsblk', '-J', '-o', 'NAME,MOUNTPOINT,SIZE,TYPE'], 
                                  capture_output=True, text=True)
            data = json.loads(result.stdout)
            
            for device in data.get('blockdevices', []):
                if device['type'] == 'disk' and device['name'].startswith('sd'):
                    for child in device.get('children', []):
                        if child.get('mountpoint') and '/media' in child['mountpoint']:
                            sdcards.append({
                                'device': f"/dev/{child['name']}",
                                'mountpoint': child['mountpoint'],
                                'size': child.get('size', 'Unknown')
                            })
        except:
            pass
        
        return sdcards
    
    def status_monitor(self):
        """주기적 상태 모니터링"""
        while self.running:
            status = self.get_system_status()
            socketio.emit('status_update', status)
            time.sleep(5)

manager = PXEServerManager()

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/status')
def api_status():
    return jsonify(manager.get_system_status())

@app.route('/api/setup-server', methods=['POST'])
def setup_server():
    def callback(msg_type, data):
        socketio.emit(f'script_{msg_type}', {'script': 'setup_server.sh', 'data': data})
    
    result = manager.execute_script('setup_server.sh', callback=callback)
    return jsonify(result)

@app.route('/api/setup-client', methods=['POST'])
def setup_client():
    data = request.get_json()
    serial = data.get('serial')
    sd_card = data.get('sdCard')
    
    if not serial or not sd_card:
        return jsonify({'success': False, 'error': '필수 정보가 누락되었습니다'}), 400
    
    # 대화형 입력을 위한 임시 스크립트 생성
    input_script = f"""#!/bin/bash
echo "{serial}"
echo "{sd_card}"
"""
    
    temp_input = Path('/tmp/setup_client_input.sh')
    temp_input.write_text(input_script)
    temp_input.chmod(0o755)
    
    def callback(msg_type, data):
        socketio.emit(f'script_{msg_type}', {'script': 'setup_client.sh', 'data': data})
    
    result = manager.execute_script('setup_client.sh', callback=callback)
    
    # 임시 파일 삭제
    temp_input.unlink(missing_ok=True)
    
    return jsonify(result)

@app.route('/api/create-client', methods=['POST'])
def create_client():
    data = request.get_json()
    source_serial = data.get('sourceSerial')
    new_serial = data.get('newSerial')
    mac_address = data.get('macAddress', '')
    
    if not source_serial or not new_serial:
        return jsonify({'success': False, 'error': '필수 정보가 누락되었습니다'}), 400
    
    args = []
    if mac_address:
        args.append(mac_address)
    
    # 대화형 입력을 위한 임시 스크립트 생성
    input_script = f"""#!/bin/bash
echo "{source_serial}"
echo "{new_serial}"
"""
    if mac_address:
        input_script += f'echo "{mac_address}"\n'
    
    temp_input = Path('/tmp/create_client_input.sh')
    temp_input.write_text(input_script)
    temp_input.chmod(0o755)
    
    def callback(msg_type, data):
        socketio.emit(f'script_{msg_type}', {'script': 'create_new_client.sh', 'data': data})
    
    result = manager.execute_script('create_new_client.sh', args, callback=callback)
    
    # 임시 파일 삭제
    temp_input.unlink(missing_ok=True)
    
    return jsonify(result)

@app.route('/api/mounted-sdcards')
def mounted_sdcards():
    return jsonify(manager.get_mounted_sdcards())

@app.route('/api/logs/<service>')
def service_logs(service):
    valid_services = ['dnsmasq', 'nfs-kernel-server']
    
    if service not in valid_services:
        return jsonify({'error': '유효하지 않은 서비스입니다'}), 400
    
    try:
        result = subprocess.run(['sudo', 'journalctl', '-u', service, '-n', '100', '--no-pager'],
                              capture_output=True, text=True)
        return jsonify({'logs': result.stdout})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/config', methods=['GET', 'POST'])
def config():
    if request.method == 'POST':
        data = request.get_json()
        manager.config.update(data)
        manager.save_config()
        return jsonify({'success': True, 'config': manager.config})
    else:
        return jsonify(manager.config)

@socketio.on('connect')
def handle_connect():
    print('클라이언트 연결됨')
    emit('status_update', manager.get_system_status())

@socketio.on('disconnect')
def handle_disconnect():
    print('클라이언트 연결 해제됨')

@socketio.on('get_status')
def handle_get_status():
    emit('status_update', manager.get_system_status())

def main():
    # 상태 모니터링 스레드 시작
    manager.status_thread = threading.Thread(target=manager.status_monitor, daemon=True)
    manager.status_thread.start()
    
    # 서버 실행
    try:
        # Root 권한 확인
        if os.geteuid() != 0:
            print("이 프로그램은 sudo 권한이 필요합니다.")
            print("사용법: sudo python3 rpi_pxe_server.py")
            sys.exit(1)
        
        print("RPI PXE Manager 서버 시작...")
        print("웹 UI: http://localhost:5000")
        
        socketio.run(app, host='0.0.0.0', port=5000, debug=False)
    except KeyboardInterrupt:
        print("\n서버 종료 중...")
        manager.running = False
    except Exception as e:
        print(f"서버 실행 오류: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()