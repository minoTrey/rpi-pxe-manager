#!/bin/bash

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 설정 변수
SERVER_IP="192.168.0.10"
GATEWAY="192.168.0.1"
NETMASK="255.255.255.0"
DHCP_RANGE_START="192.168.0.100"
DHCP_RANGE_END="192.168.0.200"
CLIENT_IP_START="192.168.0.11"

TFTP_ROOT="/tftpboot"
NFS_ROOT="/mnt/ssd"
CONFIG_DIR="./config"
SCRIPTS_DIR="./scripts"

# 루트 권한 확인
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 root 권한으로 실행되어야 합니다."
        log_info "다음과 같이 실행하세요: sudo $0"
        exit 1
    fi
}

# 네트워크 인터페이스 감지
detect_ethernet_interface() {
    log_info "이더넷 인터페이스를 감지하는 중..."
    
    # 활성화된 이더넷 인터페이스 찾기
    ETHERNET_INTERFACE=$(ip link show | grep -E "^[0-9]+: en" | head -1 | cut -d: -f2 | tr -d ' ')
    
    if [[ -z "$ETHERNET_INTERFACE" ]]; then
        log_warning "자동으로 이더넷 인터페이스를 찾을 수 없습니다."
        echo "사용 가능한 네트워크 인터페이스:"
        ip link show | grep -E "^[0-9]+:" | cut -d: -f2 | tr -d ' '
        echo -n "이더넷 인터페이스 이름을 입력하세요: "
        read ETHERNET_INTERFACE
    fi
    
    log_info "사용할 이더넷 인터페이스: $ETHERNET_INTERFACE"
}

# 패키지 설치
install_packages() {
    log_info "필요한 패키지를 설치하는 중..."
    
    apt update
    apt install -y \
        dnsmasq \
        nfs-kernel-server \
        kpartx \
        unzip \
        wget \
        rsync \
        rpi-imager
    
    log_success "패키지 설치 완료"
}

# 네트워크 설정
configure_network() {
    log_info "서버 네트워크를 설정하는 중..."
    
    # netplan 설정 파일 생성
    cat > /etc/netplan/01-netcfg.yaml << EOF
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    $ETHERNET_INTERFACE:
      dhcp4: no
      dhcp6: no
      addresses:
        - $SERVER_IP/24
      gateway4: $GATEWAY
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
EOF

    netplan apply
    log_success "네트워크 설정 완료"
    
    # 네트워크 연결 확인
    sleep 2
    if ping -c 1 $GATEWAY &> /dev/null; then
        log_success "네트워크 연결 확인됨"
    else
        log_warning "게이트웨이에 ping이 실패했습니다. 네트워크 설정을 확인하세요."
    fi
}

# dnsmasq 설정
configure_dnsmasq() {
    log_info "dnsmasq를 설정하는 중..."
    
    # 기존 설정 백업
    if [[ -f /etc/dnsmasq.conf ]]; then
        cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup
    fi
    
    # dnsmasq 설정 파일 생성
    cat > /etc/dnsmasq.conf << EOF
# dnsmasq 설정 - PXE 부팅용
port=0
interface=$ETHERNET_INTERFACE
no-hosts
dhcp-range=$DHCP_RANGE_START,$DHCP_RANGE_END,12h
log-dhcp
enable-tftp
tftp-root=$TFTP_ROOT
pxe-service=0,"Raspberry Pi Boot"

# 시리얼 번호별 부팅 파일 지정
dhcp-boot=tag:!known-id,undionly.kpxe
dhcp-boot=tag:known-id,\${mac:hexhyp}.bin

# 로그 설정
log-facility=/var/log/dnsmasq.log
log-async
EOF

    # dnsmasq 서비스 재시작
    systemctl enable dnsmasq
    systemctl restart dnsmasq
    
    log_success "dnsmasq 설정 완료"
}

# TFTP 디렉터리 설정
setup_tftp() {
    log_info "TFTP 디렉터리를 설정하는 중..."
    
    mkdir -p $TFTP_ROOT
    chmod 755 $TFTP_ROOT
    
    log_success "TFTP 디렉터리 설정 완료"
}

# NFS 설정
configure_nfs() {
    log_info "NFS를 설정하는 중..."
    
    mkdir -p $NFS_ROOT
    
    # /etc/exports 파일 생성 (기존 내용이 있다면 백업)
    if [[ -f /etc/exports ]]; then
        cp /etc/exports /etc/exports.backup
    fi
    
    # 기본 exports 파일 생성 (클라이언트별 추가는 나중에)
    cat > /etc/exports << EOF
# NFS exports for PXE booting
# 클라이언트별 설정은 create_client.sh에서 자동 추가됩니다
EOF

    # NFS 서비스 활성화 및 시작
    systemctl enable nfs-kernel-server
    systemctl start nfs-kernel-server
    
    log_success "NFS 설정 완료"
}

# 방화벽 설정
configure_firewall() {
    log_info "방화벽을 설정하는 중..."
    
    # UFW가 설치되어 있다면 필요한 포트 열기
    if command -v ufw &> /dev/null; then
        ufw allow 67/udp    # DHCP
        ufw allow 69/udp    # TFTP
        ufw allow 111/tcp   # NFS portmapper
        ufw allow 111/udp   # NFS portmapper
        ufw allow 2049/tcp  # NFS
        ufw allow 2049/udp  # NFS
        ufw allow from 192.168.0.0/24  # 로컬 네트워크
        
        log_success "방화벽 규칙 설정 완료"
    else
        log_info "UFW가 설치되어 있지 않습니다. 방화벽 설정을 건너뜁니다."
    fi
}

# 클라이언트 관리 파일 생성
create_management_files() {
    log_info "클라이언트 관리 파일을 생성하는 중..."
    
    # IP 추적 파일 생성
    touch rpi_ips.txt
    echo "# 할당된 클라이언트 IP 목록" > rpi_ips.txt
    
    # 시리얼 번호 추적 파일 생성
    touch rpi_serials.txt
    echo "# 등록된 클라이언트 시리얼 번호 목록" > rpi_serials.txt
    
    log_success "관리 파일 생성 완료"
}

# 상태 확인
check_services() {
    log_info "서비스 상태를 확인하는 중..."
    
    services=("dnsmasq" "nfs-kernel-server")
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet $service; then
            log_success "$service: 실행 중"
        else
            log_error "$service: 실행되지 않음"
            systemctl status $service
        fi
    done
    
    # 포트 확인
    log_info "포트 사용 상태 확인:"
    netstat -tulnp | grep -E ":(67|69|111|2049)"
}

# 설정 요약 출력
print_summary() {
    echo
    echo "=================================================="
    echo "         PXE 서버 설정 완료!"
    echo "=================================================="
    echo "서버 IP: $SERVER_IP"
    echo "이더넷 인터페이스: $ETHERNET_INTERFACE"
    echo "DHCP 범위: $DHCP_RANGE_START - $DHCP_RANGE_END"
    echo "TFTP 루트: $TFTP_ROOT"
    echo "NFS 루트: $NFS_ROOT"
    echo
    echo "다음 단계:"
    echo "1. SD 카드에 Raspberry Pi OS 설치"
    echo "2. ./scripts/setup_client.sh 실행"
    echo "=================================================="
}

# 메인 실행 함수
main() {
    log_info "Raspberry Pi PXE 서버 설정을 시작합니다..."
    
    check_root
    detect_ethernet_interface
    install_packages
    configure_network
    setup_tftp
    configure_dnsmasq
    configure_nfs
    configure_firewall
    create_management_files
    check_services
    print_summary
    
    log_success "PXE 서버 설정이 완료되었습니다!"
}

# 스크립트 실행
main "$@"