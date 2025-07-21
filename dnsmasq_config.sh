# dnsmasq configuration for PXE booting Raspberry Pi
# 이 파일은 setup_server.sh에서 자동으로 생성됩니다

# DNS 서비스 비활성화 (DHCP 및 TFTP만 사용)
port=0

# 사용할 네트워크 인터페이스 (스크립트에서 자동 설정)
interface=INTERFACE_NAME

# /etc/hosts 파일 읽기 비활성화
no-hosts

# DHCP 설정
dhcp-range=DHCP_START,DHCP_END,12h
dhcp-option=3,GATEWAY_IP  # 기본 게이트웨이
dhcp-option=6,8.8.8.8,1.1.1.1  # DNS 서버

# DHCP 로깅 활성화
log-dhcp

# TFTP 서버 활성화
enable-tftp
tftp-root=/tftpboot

# PXE 부팅 서비스
pxe-service=0,"Raspberry Pi Boot"

# 시리얼 번호별 부팅 파일 지정
# Raspberry Pi는 시리얼 번호 기반으로 부팅 파일을 요청합니다
dhcp-boot=tag:!known-id,undionly.kpxe

# MAC 주소 기반 DHCP 예약 (create_new_client.sh에서 추가)
# dhcp-host=MAC_ADDRESS,IP_ADDRESS,HOSTNAME

# 로깅 설정
log-facility=/var/log/dnsmasq.log
log-async=20

# 추가 보안 설정
bogus-priv
domain-needed
stop-dns-rebind

# DHCP 권한 설정
dhcp-authoritative

# TFTP 보안 설정
tftp-secure
tftp-lowercase