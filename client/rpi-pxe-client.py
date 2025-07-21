#!/usr/bin/env python3
import os
import sys
import subprocess
import json
import time
import argparse
from pathlib import Path

class RPIPXEClient:
    def __init__(self):
        self.config_file = Path.home() / '.rpi-pxe-client.json'
        self.config = self.load_config()
        
    def load_config(self):
        if self.config_file.exists():
            with open(self.config_file, 'r') as f:
                return json.load(f)
        return {}
    
    def save_config(self):
        with open(self.config_file, 'w') as f:
            json.dump(self.config, f, indent=2)
    
    def get_serial_number(self):
        try:
            with open('/proc/cpuinfo', 'r') as f:
                for line in f:
                    if line.startswith('Serial'):
                        return line.split(':')[1].strip()[-8:]
        except:
            pass
        return None
    
    def update_eeprom(self):
        print("EEPROM 업데이트를 시작합니다...")
        
        # EEPROM 구성 파일 생성
        bootconf_content = """[all]
BOOT_UART=0
WAKE_ON_GPIO=1
POWER_OFF_ON_HALT=0

[all]
BOOT_ORDER=0xf21

[all]
NET_INSTALL_ENABLED=1
DHCP_TIMEOUT=45000
DHCP_REQ_TIMEOUT=4000
TFTP_FILE_TIMEOUT=30000
TFTP_IP=
TFTP_PREFIX=0
ENABLE_SELF_UPDATE=1
DISABLE_HDMI=0
"""
        
        # 임시 디렉토리 생성
        temp_dir = Path('/tmp/rpi-eeprom-update')
        temp_dir.mkdir(exist_ok=True)
        
        bootconf_file = temp_dir / 'bootconf.txt'
        with open(bootconf_file, 'w') as f:
            f.write(bootconf_content)
        
        try:
            # 최신 EEPROM 이미지 찾기
            result = subprocess.run(['ls', '-1', '/lib/firmware/raspberrypi/bootloader/stable/'],
                                  capture_output=True, text=True)
            eeprom_files = [f for f in result.stdout.strip().split('\n') if f.startswith('pieeprom-') and f.endswith('.bin')]
            
            if not eeprom_files:
                print("EEPROM 이미지를 찾을 수 없습니다.")
                return False
            
            latest_eeprom = sorted(eeprom_files)[-1]
            eeprom_path = f'/lib/firmware/raspberrypi/bootloader/stable/{latest_eeprom}'
            
            # 새 EEPROM 이미지 생성
            new_eeprom = temp_dir / 'pieeprom-netboot.bin'
            cmd = f'rpi-eeprom-config --out {new_eeprom} --config {bootconf_file} {eeprom_path}'
            subprocess.run(cmd, shell=True, check=True)
            
            # EEPROM 업데이트
            print(f"EEPROM을 업데이트합니다: {latest_eeprom}")
            subprocess.run(['sudo', 'rpi-eeprom-update', '-d', '-f', str(new_eeprom)], check=True)
            
            print("\nEEPROM 업데이트가 완료되었습니다!")
            print("변경사항을 적용하려면 재부팅이 필요합니다.")
            
            return True
            
        except subprocess.CalledProcessError as e:
            print(f"EEPROM 업데이트 실패: {e}")
            return False
        finally:
            # 임시 파일 정리
            if temp_dir.exists():
                subprocess.run(['rm', '-rf', str(temp_dir)])
    
    def enable_ssh(self):
        print("SSH 서비스를 활성화합니다...")
        try:
            subprocess.run(['sudo', 'systemctl', 'enable', 'ssh'], check=True)
            subprocess.run(['sudo', 'systemctl', 'start', 'ssh'], check=True)
            print("SSH가 활성화되었습니다.")
            return True
        except subprocess.CalledProcessError:
            print("SSH 활성화 실패")
            return False
    
    def setup_auto_login(self):
        print("자동 로그인을 설정합니다...")
        autologin_conf = """[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin pi --noclear %I $TERM
"""
        
        autologin_dir = Path('/etc/systemd/system/getty@tty1.service.d')
        try:
            subprocess.run(['sudo', 'mkdir', '-p', str(autologin_dir)], check=True)
            
            with subprocess.Popen(['sudo', 'tee', str(autologin_dir / 'autologin.conf')],
                                stdin=subprocess.PIPE, stdout=subprocess.DEVNULL) as proc:
                proc.communicate(autologin_conf.encode())
            
            subprocess.run(['sudo', 'systemctl', 'daemon-reload'], check=True)
            print("자동 로그인이 설정되었습니다.")
            return True
        except subprocess.CalledProcessError:
            print("자동 로그인 설정 실패")
            return False
    
    def test_network_boot(self):
        print("\n네트워크 부팅 테스트를 시작합니다...")
        serial = self.get_serial_number()
        
        if not serial:
            print("시리얼 번호를 찾을 수 없습니다.")
            return
        
        print(f"Raspberry Pi 시리얼 번호: {serial}")
        print("\n현재 EEPROM 설정:")
        subprocess.run(['vcgencmd', 'bootloader_config'])
        
        print("\n네트워크 인터페이스 상태:")
        subprocess.run(['ip', 'addr', 'show', 'eth0'])
        
        print("\nDHCP 테스트:")
        subprocess.run(['sudo', 'dhclient', '-v', 'eth0'], capture_output=False)
    
    def show_info(self):
        serial = self.get_serial_number()
        print(f"\nRaspberry Pi 정보:")
        print(f"시리얼 번호: {serial}")
        
        # 현재 부팅 모드 확인
        try:
            result = subprocess.run(['vcgencmd', 'bootloader_version'], 
                                  capture_output=True, text=True)
            print(f"\nBootloader 정보:")
            print(result.stdout)
        except:
            pass
        
        # 네트워크 정보
        try:
            result = subprocess.run(['hostname', '-I'], capture_output=True, text=True)
            ips = result.stdout.strip()
            if ips:
                print(f"\nIP 주소: {ips}")
        except:
            pass
    
    def interactive_setup(self):
        print("\nRaspberry Pi PXE 클라이언트 설정")
        print("-" * 40)
        
        self.show_info()
        
        while True:
            print("\n메뉴:")
            print("1. EEPROM 업데이트 (네트워크 부팅 활성화)")
            print("2. SSH 활성화")
            print("3. 자동 로그인 설정")
            print("4. 네트워크 부팅 테스트")
            print("5. 모든 설정 실행")
            print("0. 종료")
            
            choice = input("\n선택: ").strip()
            
            if choice == '1':
                self.update_eeprom()
            elif choice == '2':
                self.enable_ssh()
            elif choice == '3':
                self.setup_auto_login()
            elif choice == '4':
                self.test_network_boot()
            elif choice == '5':
                print("\n모든 설정을 실행합니다...")
                self.enable_ssh()
                self.setup_auto_login()
                self.update_eeprom()
                print("\n모든 설정이 완료되었습니다.")
                print("재부팅 후 네트워크 부팅이 가능합니다.")
            elif choice == '0':
                break
            else:
                print("잘못된 선택입니다.")
        
        reboot = input("\n지금 재부팅하시겠습니까? (y/N): ").strip().lower()
        if reboot == 'y':
            print("재부팅합니다...")
            subprocess.run(['sudo', 'reboot'])

def main():
    parser = argparse.ArgumentParser(description='Raspberry Pi PXE 클라이언트 설정 도구')
    parser.add_argument('--update-eeprom', action='store_true', help='EEPROM 업데이트만 실행')
    parser.add_argument('--enable-ssh', action='store_true', help='SSH만 활성화')
    parser.add_argument('--auto-login', action='store_true', help='자동 로그인만 설정')
    parser.add_argument('--test', action='store_true', help='네트워크 부팅 테스트')
    parser.add_argument('--info', action='store_true', help='시스템 정보 표시')
    
    args = parser.parse_args()
    
    # Root 권한 확인
    if os.geteuid() != 0 and not args.info:
        print("이 스크립트는 sudo 권한이 필요합니다.")
        sys.exit(1)
    
    client = RPIPXEClient()
    
    if args.update_eeprom:
        client.update_eeprom()
    elif args.enable_ssh:
        client.enable_ssh()
    elif args.auto_login:
        client.setup_auto_login()
    elif args.test:
        client.test_network_boot()
    elif args.info:
        client.show_info()
    else:
        client.interactive_setup()

if __name__ == '__main__':
    main()