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
HOSTNAME_PREFIX="rpi4"
TFTP_ROOT="/tftpboot"
NFS_ROOT="/mnt/ssd"
IP_LIST_FILE="rpi_ips.txt"
SERIAL_LIST_FILE="rpi_serials.txt"

# 루트 권한 확인
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 root 권한으로 실행되어야 합니다."
        log_info "다음과 같이 실행하세요: sudo $0"
        exit 1
    fi
}

# 기존 클라이언트 목록 표시
show_existing_clients() {
    log_info "기존 클라이언트 목록:"
    
    if [[ ! -f "$SERIAL_LIST_FILE" ]] || [[ ! -s "$SERIAL_LIST_FILE" ]]; then
        log_warning "등록된 클라이언트가 없습니다."
        log_error "먼저 ./scripts/setup_client.sh를 실행하여 첫 번째 클라이언트를 설정하세요."
        exit 1
    fi
    
    SERIALS=()
    INDEX=0
    
    while IFS= read -r line; do
        # 주석 및 빈 줄 제외
        if [[ ! "$line" =~ ^#.* ]] && [[ -n "$line" ]]; then
            serial=$(echo "$line" | tr -d '\r\n')
            SERIALS+=("$serial")
            hostname="$HOSTNAME_PREFIX-$serial"
            
            # 해당 디렉터리가 존재하는지 확인
            if [[ -d "$NFS_ROOT/$hostname" ]]; then
                echo "  [$INDEX] $serial ($hostname) ✓"
            else
                echo "  [$INDEX] $serial ($hostname) ✗ (디렉터리 없음)"
            fi
            INDEX=$((INDEX + 1))
        fi
    done < "$SERIAL_LIST_FILE"
    
    if [[ ${#SERIALS[@]} -eq 0 ]]; then
        log_error "유효한 클라이언트가 없습니다."
        exit 1
    fi
}

# 소스 클라이언트 선택
select_source_client() {
    show_existing_clients
    echo
    echo -n "복사할 소스 클라이언트 번호를 선택하세요: "
    read CHOICE
    
    if [[ ! "$CHOICE" =~ ^[0-9]+$ ]] || [[ $CHOICE -ge ${#SERIALS[@]} ]]; then
        log_error "유효하지 않은 선택입니다."
        exit 1
    fi
    
    SRC_SERIAL=${SERIALS[$CHOICE]}
    SRC_HOSTNAME="$HOSTNAME_PREFIX-$SRC_SERIAL"
    
    log_info "선택된 소스 클라이언트: $SRC_SERIAL ($SRC_HOSTNAME)"
    
    # 소스 디렉터리 존재 확인
    if [[ ! -d "$NFS_ROOT/$SRC_HOSTNAME" ]]; then
        log_error "소스 클라이언트의 root 디렉터리가 존재하지 않습니다: $NFS_ROOT/$SRC_HOSTNAME"
        exit 1
    fi
    
    if [[ ! -d "$TFTP_ROOT/$SRC_SERIAL" ]]; then
        log_error "소스 클라이언트의 TFTP 디렉터리가 존재하지 않습니다: $TFTP_ROOT/$SRC_SERIAL"
        exit 1
    fi
}

# 새 클라이언트 시리얼 번호 입력
get_new_serial() {
    echo
    echo "새 클라이언트의 시리얼 번호를 확인하는 방법:"
    echo "1. 새 Raspberry Pi를 부팅하고 다음 명령어 실행:"
    echo "   cat /sys/firmware/devicetree/base/serial-number"
    echo "2. 또는 부팅 로그에서 시리얼 번호 확인"
    echo
    
    while true; do
        echo -n "새 클라이언트의 시리얼 번호를 입력하세요: "
        read NEW_SERIAL
        
        if [[ -z "$NEW_SERIAL" ]]; then
            log_error "시리얼 번호를 입력해야 합니다."
            continue
        fi
        
        # 중복 확인
        if grep -q "^$NEW_SERIAL$" "$SERIAL_LIST_FILE" 2>/dev/null; then
            log_error "이미 등록된 시리얼 번호입니다: $NEW_SERIAL"
            continue
        fi
        
        break
    done
    
    NEW_HOSTNAME="$HOSTNAME_PREFIX-$NEW_SERIAL"
    log_info "새 클라이언트: $NEW_SERIAL ($NEW_HOSTNAME)"
}

# IP 자동 할당
assign_new_ip() {
    log_info "새 클라이언트 IP를 할당하는 중..."
    
    # IP 목록 파일이 없다면 생성
    if [[ ! -f "$IP_LIST_FILE" ]]; then
        touch "$IP_LIST_FILE"
    fi
    
    # 마지막 사용된 IP 찾기
    BASE_IP="192.168.0."
    START_NUM=11
    
    if [[ -s "$IP_LIST_FILE" ]]; then
        LAST_USED=$(grep -oP "$BASE_IP\K\d+" "$IP_LIST_FILE" 2>/dev/null | sort -n | tail -1)
        if [[ -n "$LAST_USED" ]]; then
            NEXT_NUM=$((LAST_USED + 1))
        else
            NEXT_NUM=$START_NUM
        fi
    else
        NEXT_NUM=$START_NUM
    fi
    
    NEW_CLIENT_IP="${BASE_IP}${NEXT_NUM}"
    
    log_info "할당된 IP: $NEW_CLIENT_IP"
}

# 디렉터리 생성
create_new_directories() {
    log_info "새 클라이언트 디렉터리를 생성하는 중..."
    
    NEW_ROOT_DIR="$NFS_ROOT/$NEW_HOSTNAME"
    NEW_TFTP_DIR="$TFTP_ROOT/$NEW_SERIAL"
    
    mkdir -p "$NEW_ROOT_DIR"
    mkdir -p "$NEW_TFTP_DIR"
    
    log_success "디렉터리 생성 완료:"
    log_info "Root: $NEW_ROOT_DIR"
    log_info "TFTP: $NEW_TFTP_DIR"
}

# 파일시스템 복사
copy_client_filesystems() {
    log_info "클라이언트 파일시스템을 복사하는 중..."
    
    SRC_ROOT_DIR="$NFS_ROOT/$SRC_HOSTNAME"
    SRC_TFTP_DIR="$TFTP_ROOT/$SRC_SERIAL"
    NEW_ROOT_DIR="$NFS_ROOT/$NEW_HOSTNAME"
    NEW_TFTP_DIR="$TFTP_ROOT/$NEW_SERIAL"
    
    # Root 파일시스템 복사
    log_info "Root 파일시스템 복사 중... (시간이 걸릴 수 있습니다)"
    rsync -aAX "$SRC_ROOT_DIR/" "$NEW_ROOT_DIR/"
    
    # Boot 파일시스템 복사
    log_info "Boot 파일시스템 복사 중..."
    rsync -aAX "$SRC_TFTP_DIR/" "$NEW_TFTP_DIR/"
    
    log_success "파일시스템 복사 완료"
}

# 새 클라이언트 설정 업데이트
update_client_config() {
    log_info "새 클라이언트 설정을 업데이트하는 중..."
    
    NEW_ROOT_DIR="$NFS_ROOT/$NEW_HOSTNAME"
    NEW_TFTP_DIR="$TFTP_ROOT/$NEW_SERIAL"
    IFACE="eth0"
    
    # 호스트명 업데이트
    echo "$NEW_HOSTNAME" > "$NEW_ROOT_DIR/etc/hostname"
    
    # /etc/hosts 업데이트
    cat > "$NEW_ROOT_DIR/etc/hosts" << EOF
127.0.0.1       localhost
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters

127.0.1.1       $NEW_HOSTNAME
EOF

    # cmdline.txt 업데이트
    cat > "$NEW_TFTP_DIR/cmdline.txt" << EOF
console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=$SERVER_IP:$NEW_ROOT_DIR,vers=3 rw ip=$NEW_CLIENT_IP::$GATEWAY:$NETMASK:$NEW_HOSTNAME:$IFACE:off rootwait elevator=deadline
EOF

    # fstab 업데이트 (이미 올바른 형태이므로 변경 불필요하지만 확인차 재작성)
    cat > "$NEW_ROOT_DIR/etc/fstab" << EOF
proc            /proc           proc    defaults          0       0
tmpfs           /tmp            tmpfs   defaults,nosuid   0       0
devpts          /dev/pts        devpts  gid=5,mode=620    0       0
EOF

    log_success "클라이언트 설정 업데이트 완료"
}

# SSH 키 초기화
reset_ssh_keys() {
    log_info "SSH 키를 초기화하는 중..."
    
    NEW_ROOT_DIR="$NFS_ROOT/$NEW_HOSTNAME"
    
    # 기존 SSH 호스트 키 제거
    rm -f "$NEW_ROOT_DIR/etc/ssh/ssh_host_"*
    
    # SSH 키 재생성 서비스 설정 (첫 부팅시 자동 생성)
    mkdir -p "$NEW_ROOT_DIR/etc/systemd/system/ssh.service.d"
    cat > "$NEW_ROOT_DIR/etc/systemd/system/ssh.service.d/override.conf" << EOF
[Service]
ExecStartPre=/bin/bash -c 'if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then /usr/bin/ssh-keygen -A; fi'
EOF

    log_success "SSH 키 초기화 완료"
}

# Machine ID 초기화
reset_machine_id() {
    log_info "Machine ID를 초기화하는 중..."
    
    NEW_ROOT_DIR="$NFS_ROOT/$NEW_HOSTNAME"
    
    # /etc/machine-id 초기화
    echo "" > "$NEW_ROOT_DIR/etc/machine-id"
    
    # /var/lib/dbus/machine-id 초기화 (있다면)
    if [[ -f "$NEW_ROOT_DIR/var/lib/dbus/machine-id" ]]; then
        echo "" > "$NEW_ROOT_DIR/var/lib/dbus/machine-id"
    fi
    
    log_success "Machine ID 초기화 완료"
}

# NFS exports 업데이트
update_nfs_exports() {
    log_info "NFS exports를 업데이트하는 중..."
    
    NEW_ROOT_DIR="$NFS_ROOT/$NEW_HOSTNAME"
    NEW_TFTP_DIR="$TFTP_ROOT/$NEW_SERIAL"
    
    # exports 파일에 추가
    echo "$NEW_ROOT_DIR *(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
    echo "$NEW_TFTP_DIR *(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
    
    # NFS exports 다시 로드
    exportfs -ra
    
    log_success "NFS exports 업데이트 완료"
}

# 권한 설정
set_permissions() {
    log_info "권한을 설정하는 중..."
    
    NEW_ROOT_DIR="$NFS_ROOT/$NEW_HOSTNAME"
    NEW_TFTP_DIR="$TFTP_ROOT/$NEW_SERIAL"
    
    # 전체 권한 설정
    chmod -R 755 "$NEW_ROOT_DIR"
    chmod -R 755 "$NEW_TFTP_DIR"
    
    # pi 사용자 홈 디렉터리 권한
    chown -R 1000:1000 "$NEW_ROOT_DIR/home/pi"
    
    log_success "권한 설정 완료"
}

# 클라이언트 정보 기록
record_new_client_info() {
    log_info "새 클라이언트 정보를 기록하는 중..."
    
    # IP 목록에 추가
    echo "$NEW_CLIENT_IP" >> "$IP_LIST_FILE"
    
    # 시리얼 번호 목록에 추가
    echo "$NEW_SERIAL" >> "$SERIAL_LIST_FILE"
    
    # 상세 정보 기록
    cat >> client_info.txt << EOF
===== 클라이언트 정보 =====
시리얼: $NEW_SERIAL
IP: $NEW_CLIENT_IP
호스트명: $NEW_HOSTNAME
생성일: $(date)
소스: $SRC_SERIAL ($SRC_HOSTNAME)
Root 경로: $NFS_ROOT/$NEW_HOSTNAME
TFTP 경로: $TFTP_ROOT/$NEW_SERIAL
========================

EOF

    log_success "클라이언트 정보 기록 완료"
}

# dnsmasq에 MAC 주소 기반 부팅 설정 추가 (선택사항)
configure_dhcp_reservation() {
    echo
    echo "DHCP 예약 설정을 원하시나요? (y/N)"
    echo "MAC 주소를 알고 있다면 고정 IP를 보장할 수 있습니다."
    read -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -n "새 클라이언트의 MAC 주소를 입력하세요 (예: b8:27:eb:12:34:56): "
        read MAC_ADDRESS
        
        if [[ -n "$MAC_ADDRESS" ]]; then
            # dnsmasq 설정에 DHCP 예약 추가
            echo "dhcp-host=$MAC_ADDRESS,$NEW_CLIENT_IP,$NEW_HOSTNAME" >> /etc/dnsmasq.conf
            systemctl restart dnsmasq
            log_success "DHCP 예약 설정 완료: $MAC_ADDRESS -> $NEW_CLIENT_IP"
        fi
    fi
}

# 설정 요약
print_summary() {
    echo
    echo "=================================================="
    echo "         새 클라이언트 생성 완료!"
    echo "=================================================="
    echo "소스 클라이언트: $SRC_SERIAL ($SRC_HOSTNAME)"
    echo "새 클라이언트:"
    echo "  시리얼 번호: $NEW_SERIAL"
    echo "  IP 주소: $NEW_CLIENT_IP"
    echo "  호스트명: $NEW_HOSTNAME"
    echo "  Root 경로: $NFS_ROOT/$NEW_HOSTNAME"
    echo "  TFTP 경로: $TFTP_ROOT/$NEW_SERIAL"
    echo
    echo "다음 단계:"
    echo "1. 새 Raspberry Pi에서 네트워크 부팅 테스트"
    echo "2. 필요시 EEPROM 설정 업데이트:"
    echo "   sudo rpi-eeprom-update -d -f ./netboot-pieeprom.bin"
    echo "3. 부팅 후 고유 설정 적용 (SSH 키 자동 생성됨)"
    echo "=================================================="
}

# 메인 실행 함수
main() {
    log_info "새 Raspberry Pi 클라이언트 생성을 시작합니다..."
    
    check_root
    select_source_client
    get_new_serial
    assign_new_ip
    create_new_directories
    copy_client_filesystems
    update_client_config
    reset_ssh_keys
    reset_machine_id
    set_permissions
    update_nfs_exports
    record_new_client_info
    configure_dhcp_reservation
    print_summary
    
    log_success "새 클라이언트 생성이 완료되었습니다!"
}

# 스크립트 실행
main "$@"