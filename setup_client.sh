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
CLIENT_IP_START="192.168.0.11"
HOSTNAME_PREFIX="rpi4"
TFTP_ROOT="/tftpboot"
NFS_ROOT="/mnt/ssd"
SD_BOOT_PATH=""
SD_ROOT_PATH=""

# 루트 권한 확인
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 root 권한으로 실행되어야 합니다."
        log_info "다음과 같이 실행하세요: sudo $0"
        exit 1
    fi
}

# SD 카드 경로 감지
detect_sd_card() {
    log_info "SD 카드를 감지하는 중..."
    
    # 마운트된 저장 장치 목록 표시
    echo "현재 마운트된 저장 장치:"
    lsblk -f | grep -E "(boot|root)"
    
    echo
    echo "일반적인 SD 카드 경로:"
    echo "1. /media/$SUDO_USER/bootfs 및 /media/$SUDO_USER/rootfs"
    echo "2. /media/rpi-server/bootfs 및 /media/rpi-server/rootfs"
    echo
    
    # 자동 감지 시도
    POSSIBLE_BOOT_PATHS=(
        "/media/$SUDO_USER/bootfs"
        "/media/rpi-server/bootfs"
        "/media/*/bootfs"
    )
    
    POSSIBLE_ROOT_PATHS=(
        "/media/$SUDO_USER/rootfs"
        "/media/rpi-server/rootfs"
        "/media/*/rootfs"
    )
    
    for path in "${POSSIBLE_BOOT_PATHS[@]}"; do
        if [[ -d $path ]]; then
            SD_BOOT_PATH="$path"
            break
        fi
    done
    
    for path in "${POSSIBLE_ROOT_PATHS[@]}"; do
        if [[ -d $path ]]; then
            SD_ROOT_PATH="$path"
            break
        fi
    done
    
    # 수동 입력
    if [[ -z "$SD_BOOT_PATH" ]]; then
        echo -n "SD 카드 boot 파티션 경로를 입력하세요: "
        read SD_BOOT_PATH
    fi
    
    if [[ -z "$SD_ROOT_PATH" ]]; then
        echo -n "SD 카드 root 파티션 경로를 입력하세요: "
        read SD_ROOT_PATH
    fi
    
    # 경로 검증
    if [[ ! -d "$SD_BOOT_PATH" ]]; then
        log_error "Boot 파티션을 찾을 수 없습니다: $SD_BOOT_PATH"
        exit 1
    fi
    
    if [[ ! -d "$SD_ROOT_PATH" ]]; then
        log_error "Root 파티션을 찾을 수 없습니다: $SD_ROOT_PATH"
        exit 1
    fi
    
    log_success "SD 카드 경로 확인:"
    log_info "Boot: $SD_BOOT_PATH"
    log_info "Root: $SD_ROOT_PATH"
}

# 시리얼 번호 획득
get_serial_from_sd() {
    log_info "SD 카드에서 시리얼 번호를 확인하는 중..."
    
    # /proc/device-tree/serial-number에서 시리얼 번호 읽기 시뮬레이션
    # 실제로는 RPi가 부팅된 상태에서만 가능하므로, 사용자 입력으로 대체
    
    echo "Raspberry Pi의 시리얼 번호를 확인하는 방법:"
    echo "1. RPi를 부팅하고 다음 명령어 실행:"
    echo "   cat /sys/firmware/devicetree/base/serial-number"
    echo "2. 또는 SD 카드를 RPi에 넣고 부팅 후 확인"
    echo
    
    echo -n "Raspberry Pi 시리얼 번호를 입력하세요 (예: 81fe4bf3): "
    read SERIAL
    
    if [[ -z "$SERIAL" ]]; then
        log_error "시리얼 번호를 입력해야 합니다."
        exit 1
    fi
    
    log_info "사용할 시리얼 번호: $SERIAL"
}

# 클라이언트 IP 할당
assign_client_ip() {
    log_info "클라이언트 IP를 할당하는 중..."
    
    IP_LIST_FILE="rpi_ips.txt"
    
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
    
    CLIENT_IP="${BASE_IP}${NEXT_NUM}"
    HOSTNAME="${HOSTNAME_PREFIX}-${SERIAL}"
    
    log_info "할당된 IP: $CLIENT_IP"
    log_info "호스트명: $HOSTNAME"
}

# 디렉터리 생성
create_directories() {
    log_info "클라이언트 디렉터리를 생성하는 중..."
    
    ROOT_DIR="$NFS_ROOT/$HOSTNAME"
    TFTP_DIR="$TFTP_ROOT/$SERIAL"
    
    mkdir -p "$ROOT_DIR"
    mkdir -p "$TFTP_DIR"
    
    log_success "디렉터리 생성 완료:"
    log_info "Root: $ROOT_DIR"
    log_info "TFTP: $TFTP_DIR"
}

# 파일시스템 복사
copy_filesystems() {
    log_info "파일시스템을 복사하는 중..."
    
    ROOT_DIR="$NFS_ROOT/$HOSTNAME"
    TFTP_DIR="$TFTP_ROOT/$SERIAL"
    
    # Root 파일시스템 복사
    log_info "Root 파일시스템 복사 중... (시간이 걸릴 수 있습니다)"
    rsync -aAXv "$SD_ROOT_PATH/" "$ROOT_DIR/" \
        --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"}
    
    # Boot 파일시스템 복사
    log_info "Boot 파일시스템 복사 중..."
    rsync -aAXv "$SD_BOOT_PATH/" "$TFTP_DIR/"
    
    log_success "파일시스템 복사 완료"
}

# fstab 설정
configure_fstab() {
    log_info "fstab를 설정하는 중..."
    
    ROOT_DIR="$NFS_ROOT/$HOSTNAME"
    
    cat > "$ROOT_DIR/etc/fstab" << EOF
proc            /proc           proc    defaults          0       0
tmpfs           /tmp            tmpfs   defaults,nosuid   0       0
devpts          /dev/pts        devpts  gid=5,mode=620    0       0
EOF

    log_success "fstab 설정 완료"
}

# cmdline.txt 설정
configure_cmdline() {
    log_info "cmdline.txt를 설정하는 중..."
    
    TFTP_DIR="$TFTP_ROOT/$SERIAL"
    ROOT_DIR="$NFS_ROOT/$HOSTNAME"
    IFACE="eth0"
    
    cat > "$TFTP_DIR/cmdline.txt" << EOF
console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=$SERVER_IP:$ROOT_DIR,vers=3 rw ip=$CLIENT_IP::$GATEWAY:$NETMASK:$HOSTNAME:$IFACE:off rootwait elevator=deadline
EOF

    log_success "cmdline.txt 설정 완료"
}

# 호스트명 설정
configure_hostname() {
    log_info "호스트명을 설정하는 중..."
    
    ROOT_DIR="$NFS_ROOT/$HOSTNAME"
    
    echo "$HOSTNAME" > "$ROOT_DIR/etc/hostname"
    
    # /etc/hosts 업데이트
    cat > "$ROOT_DIR/etc/hosts" << EOF
127.0.0.1       localhost
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters

127.0.1.1       $HOSTNAME
EOF

    log_success "호스트명 설정 완료"
}

# SSH 활성화
enable_ssh() {
    log_info "SSH를 활성화하는 중..."
    
    ROOT_DIR="$NFS_ROOT/$HOSTNAME"
    
    # SSH 서비스 활성화
    chroot "$ROOT_DIR" systemctl enable ssh
    
    # SSH 키 생성 (첫 부팅시 자동 생성되도록 설정)
    mkdir -p "$ROOT_DIR/etc/systemd/system/ssh.service.d"
    cat > "$ROOT_DIR/etc/systemd/system/ssh.service.d/override.conf" << EOF
[Service]
ExecStartPre=/bin/bash -c 'if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then /usr/bin/ssh-keygen -A; fi'
EOF

    log_success "SSH 활성화 완료"
}

# 자동 로그인 설정
configure_autologin() {
    log_info "자동 로그인을 설정하는 중..."
    
    ROOT_DIR="$NFS_ROOT/$HOSTNAME"
    
    mkdir -p "$ROOT_DIR/etc/systemd/system/getty@tty1.service.d"
    cat > "$ROOT_DIR/etc/systemd/system/getty@tty1.service.d/override.conf" << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin pi --noclear %I \$TERM
EOF

    log_success "자동 로그인 설정 완료"
}

# 카메라 모듈 설정
setup_camera() {
    log_info "카메라 모듈을 설정하는 중..."
    
    ROOT_DIR="$NFS_ROOT/$HOSTNAME"
    TFTP_DIR="$TFTP_ROOT/$SERIAL"
    
    # config.txt에 카메라 설정 추가
    if ! grep -q "dtoverlay=imx519" "$TFTP_DIR/config.txt"; then
        echo "" >> "$TFTP_DIR/config.txt"
        echo "# Camera module" >> "$TFTP_DIR/config.txt"
        echo "dtoverlay=imx519" >> "$TFTP_DIR/config.txt"
    fi
    
    # 카메라 관련 패키지 설치 스크립트 생성
    cat > "$ROOT_DIR/home/pi/install_camera.sh" << 'EOF'
#!/bin/bash
cd /home/pi
wget -O install_pivariety_pkgs.sh https://github.com/ArduCAM/Arducam-Pivariety-V4L2-Driver/releases/download/install_script/install_pivariety_pkgs.sh
chmod +x install_pivariety_pkgs.sh
./install_pivariety_pkgs.sh -p libcamera_dev
./install_pivariety_pkgs.sh -p libcamera_apps
EOF
    
    chmod +x "$ROOT_DIR/home/pi/install_camera.sh"
    chown 1000:1000 "$ROOT_DIR/home/pi/install_camera.sh"
    
    log_success "카메라 모듈 설정 완료"
}

# NFS exports 업데이트
update_nfs_exports() {
    log_info "NFS exports를 업데이트하는 중..."
    
    ROOT_DIR="$NFS_ROOT/$HOSTNAME"
    TFTP_DIR="$TFTP_ROOT/$SERIAL"
    
    # exports 파일에 추가
    echo "$ROOT_DIR *(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
    echo "$TFTP_DIR *(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
    
    # NFS exports 다시 로드
    exportfs -ra
    
    log_success "NFS exports 업데이트 완료"
}

# 클라이언트 정보 기록
record_client_info() {
    log_info "클라이언트 정보를 기록하는 중..."
    
    # IP 목록에 추가
    echo "$CLIENT_IP" >> rpi_ips.txt
    
    # 시리얼 번호 목록에 추가
    echo "$SERIAL" >> rpi_serials.txt
    
    # 상세 정보 기록
    cat >> client_info.txt << EOF
===== 클라이언트 정보 =====
시리얼: $SERIAL
IP: $CLIENT_IP
호스트명: $HOSTNAME
생성일: $(date)
Root 경로: $NFS_ROOT/$HOSTNAME
TFTP 경로: $TFTP_ROOT/$SERIAL
========================

EOF

    log_success "클라이언트 정보 기록 완료"
}

# 권한 설정
set_permissions() {
    log_info "권한을 설정하는 중..."
    
    ROOT_DIR="$NFS_ROOT/$HOSTNAME"
    TFTP_DIR="$TFTP_ROOT/$SERIAL"
    
    # 전체 권한 설정
    chmod -R 755 "$ROOT_DIR"
    chmod -R 755 "$TFTP_DIR"
    
    # pi 사용자 홈 디렉터리 권한
    chown -R 1000:1000 "$ROOT_DIR/home/pi"
    
    log_success "권한 설정 완료"
}

# 설정 요약
print_summary() {
    echo
    echo "=================================================="
    echo "         첫 번째 클라이언트 설정 완료!"
    echo "=================================================="
    echo "시리얼 번호: $SERIAL"
    echo "IP 주소: $CLIENT_IP"
    echo "호스트명: $HOSTNAME"
    echo "Root 경로: $NFS_ROOT/$HOSTNAME"
    echo "TFTP 경로: $TFTP_ROOT/$SERIAL"
    echo
    echo "다음 단계:"
    echo "1. SD 카드를 제거하세요"
    echo "2. Raspberry Pi에서 SD 카드 없이 네트워크 부팅 테스트"
    echo "3. 부팅 후 다음 명령어로 카메라 모듈 설치:"
    echo "   ./install_camera.sh"
    echo "4. 추가 클라이언트는 ./scripts/create_new_client.sh 사용"
    echo "=================================================="
}

# 메인 실행 함수
main() {
    log_info "첫 번째 Raspberry Pi 클라이언트 설정을 시작합니다..."
    
    check_root
    detect_sd_card
    get_serial_from_sd
    assign_client_ip
    create_directories
    copy_filesystems
    configure_fstab
    configure_cmdline
    configure_hostname
    enable_ssh
    configure_autologin
    setup_camera
    set_permissions
    update_nfs_exports
    record_client_info
    print_summary
    
    log_success "첫 번째 클라이언트 설정이 완료되었습니다!"
}

# 스크립트 실행
main "$@"