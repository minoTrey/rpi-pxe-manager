#!/usr/bin/env python3
"""
RPI PXE Manager - Modern GUI Version
현대적이고 사용자 친화적인 그래픽 인터페이스
"""

import os
import sys
import subprocess
import json
import threading
import re
import time
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional
from concurrent.futures import ThreadPoolExecutor, as_completed

# CustomTkinter 자동 설치
def install_gui_packages():
    required = ['customtkinter', 'psutil', 'netifaces', 'pillow']
    missing = []

    for pkg in required:
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)

    if missing:
        print(f"📦 GUI 패키지 설치 중: {', '.join(missing)}")
        cmd = [sys.executable, '-m', 'pip', 'install', '--user', '--break-system-packages'] + missing
        subprocess.run(cmd, stderr=subprocess.DEVNULL)
        print("✅ 패키지 설치 완료!")

install_gui_packages()

import customtkinter as ctk
import psutil
import netifaces
from tkinter import messagebox, ttk
import tkinter as tk

# 테마 설정
ctk.set_appearance_mode("dark")  # "dark" 또는 "light"
ctk.set_default_color_theme("blue")  # "blue", "green", "dark-blue"


class RPIPXEManagerGUI:
    def __init__(self):
        self.config_file = Path.home() / '.rpi_pxe_config.json'
        self.config = self.load_config()

        # 메인 윈도우 생성
        self.root = ctk.CTk()
        self.root.title("RPI PXE Manager - 현대적 관리 시스템")
        self.root.geometry("1400x900")

        # 최소 크기 설정
        self.root.minsize(1200, 700)

        # 상태 업데이트 스레드
        self.running = True
        self.status_data = {}
        self.current_view = None  # 현재 활성화된 뷰 추적

        # 클라이언트 상태 캐시 (IP -> (status, timestamp))
        self.client_status_cache = {}
        self.cache_duration = 30  # 30초 동안 캐시 유지

        # dnsmasq.conf 수정 시간 추적 (자동 새로고침용 - 진짜 설정 파일)
        self.dnsmasq_conf = Path('/etc/dnsmasq.conf')
        self.config_mtime = self.dnsmasq_conf.stat().st_mtime if self.dnsmasq_conf.exists() else 0

        self.setup_ui()
        self.start_status_updates()
        self.start_background_status_checker()

    def parse_clients_from_dnsmasq(self) -> List[dict]:
        """dnsmasq.conf에서 직접 클라이언트 정보 읽기 (진짜 설정)"""
        clients = []
        dnsmasq_conf = Path('/etc/dnsmasq.conf')

        if not dnsmasq_conf.exists():
            return clients

        try:
            with open(dnsmasq_conf, 'r') as f:
                content = f.read()

            # dhcp-host=MAC,IP,hostname,infinite 형식 파싱
            pattern = r'dhcp-host=([0-9a-f:]+),([0-9.]+),([^,]+),'
            matches = re.findall(pattern, content)

            for mac, ip, serial in matches:
                clients.append({
                    'serial': serial,
                    'hostname': serial,
                    'mac': mac,
                    'ip': ip,
                    'online': False
                })
        except Exception as e:
            print(f"dnsmasq.conf 읽기 오류: {e}")

        return clients

    def load_config(self) -> dict:
        """설정 파일 로드 - 클라이언트는 dnsmasq.conf에서 직접 읽기"""
        # 기본 설정 (서버 IP, 네트워크 등)
        config = {
            'server_ip': '192.168.0.10',
            'dhcp_range_start': '192.168.0.100',
            'dhcp_range_end': '192.168.0.200',
            'network_interface': 'eth0',
            'nfs_root': '/media/rpi-client',
            'tftp_root': '/tftpboot',
            'clients': []
        }

        # JSON 설정 파일이 있으면 기본 설정 로드
        if self.config_file.exists():
            try:
                with open(self.config_file, 'r') as f:
                    saved_config = json.load(f)
                # 기본 설정 업데이트 (clients 제외)
                for key in ['server_ip', 'dhcp_range_start', 'dhcp_range_end',
                           'network_interface', 'nfs_root', 'tftp_root']:
                    if key in saved_config:
                        config[key] = saved_config[key]
            except:
                pass

        # 클라이언트는 항상 dnsmasq.conf에서 읽기 (진짜 설정)
        config['clients'] = self.parse_clients_from_dnsmasq()

        return config

    def save_config(self):
        """설정 파일 저장"""
        with open(self.config_file, 'w') as f:
            json.dump(self.config, f, indent=2)
        # 수정 시간 업데이트 (자동 새로고침 방지)
        if self.config_file.exists():
            self.config_mtime = self.config_file.stat().st_mtime

    def run_sudo(self, cmd: List[str], input_data: bytes = None, **kwargs) -> subprocess.CompletedProcess:
        """
        sudo 명령을 비밀번호 자동 입력으로 실행

        Args:
            cmd: 실행할 명령 리스트 (['systemctl', 'restart', 'dnsmasq'] 형식)
            input_data: stdin으로 전달할 추가 데이터 (bytes)
            **kwargs: subprocess.run()에 전달할 추가 인자

        Returns:
            subprocess.CompletedProcess 객체
        """
        # sudo -S를 사용하여 stdin에서 비밀번호 읽기
        sudo_cmd = ['sudo', '-S'] + cmd

        # 비밀번호 준비 (1234\n)
        password = b'1234\n'

        # input_data가 있으면 비밀번호 뒤에 추가
        if input_data:
            stdin_data = password + input_data
        else:
            stdin_data = password

        # 기본 kwargs 설정
        default_kwargs = {
            'input': stdin_data,
            'capture_output': True,
            'text': False  # bytes 모드로 작동
        }
        default_kwargs.update(kwargs)

        return subprocess.run(sudo_cmd, **default_kwargs)

    def setup_ui(self):
        """UI 구성"""
        # 메인 컨테이너
        self.main_container = ctk.CTkFrame(self.root)
        self.main_container.pack(fill="both", expand=True, padx=10, pady=10)

        # 왼쪽 사이드바
        self.sidebar = ctk.CTkFrame(self.main_container, width=250, corner_radius=15)
        self.sidebar.pack(side="left", fill="y", padx=(0, 10))
        self.sidebar.pack_propagate(False)

        # 로고/타이틀
        title_frame = ctk.CTkFrame(self.sidebar, fg_color="transparent")
        title_frame.pack(pady=20, padx=20)

        title_label = ctk.CTkLabel(
            title_frame,
            text="🚀 RPI PXE\nManager",
            font=ctk.CTkFont(size=24, weight="bold"),
            justify="center"
        )
        title_label.pack()

        version_label = ctk.CTkLabel(
            title_frame,
            text="v2.3.0 GUI Edition",
            font=ctk.CTkFont(size=12),
            text_color="gray"
        )
        version_label.pack()

        # 메뉴 버튼들
        self.menu_buttons = []

        menus = [
            ("📊 대시보드", self.show_dashboard),
            ("🖥️  클라이언트 관리", self.show_client_management),
            ("⚙️  서버 설정", self.show_server_settings),
            ("🚀 서비스 관리", self.show_service_management),
            ("📝 로그 확인", self.show_logs),
            ("🔧 초기 설정", self.show_initial_setup),
        ]

        for text, command in menus:
            btn = ctk.CTkButton(
                self.sidebar,
                text=text,
                command=command,
                height=45,
                font=ctk.CTkFont(size=14),
                anchor="w",
                fg_color="transparent",
                text_color=("gray10", "gray90"),
                hover_color=("gray70", "gray30")
            )
            btn.pack(pady=5, padx=20, fill="x")
            self.menu_buttons.append(btn)

        # 설정 구분선
        separator = ctk.CTkFrame(self.sidebar, height=2, fg_color="gray30")
        separator.pack(pady=20, padx=20, fill="x")

        # 테마 스위치
        theme_label = ctk.CTkLabel(
            self.sidebar,
            text="다크 모드",
            font=ctk.CTkFont(size=12)
        )
        theme_label.pack(pady=(0, 5))

        self.theme_switch = ctk.CTkSwitch(
            self.sidebar,
            text="",
            command=self.toggle_theme,
            onvalue="dark",
            offvalue="light"
        )
        self.theme_switch.select()  # 기본 다크모드
        self.theme_switch.pack(pady=(0, 20))

        # 종료 버튼
        exit_btn = ctk.CTkButton(
            self.sidebar,
            text="🚪 종료",
            command=self.on_closing,
            height=40,
            fg_color="#D32F2F",
            hover_color="#B71C1C"
        )
        exit_btn.pack(side="bottom", pady=20, padx=20, fill="x")

        # 오른쪽 메인 컨텐츠 영역
        self.content_area = ctk.CTkFrame(self.main_container, corner_radius=15)
        self.content_area.pack(side="right", fill="both", expand=True)

        # 기본적으로 대시보드 표시
        self.show_dashboard()

        # 윈도우 닫기 이벤트
        self.root.protocol("WM_DELETE_WINDOW", self.on_closing)

    def clear_content_area(self):
        """컨텐츠 영역 초기화"""
        for widget in self.content_area.winfo_children():
            widget.destroy()

    def toggle_theme(self):
        """테마 전환"""
        if self.theme_switch.get() == "dark":
            ctk.set_appearance_mode("dark")
        else:
            ctk.set_appearance_mode("light")

    def show_dashboard(self):
        """대시보드 표시"""
        # 항상 최신 설정 로드 (dnsmasq.conf에서 클라이언트 읽기)
        self.config = self.load_config()
        if self.dnsmasq_conf.exists():
            self.config_mtime = self.dnsmasq_conf.stat().st_mtime

        self.clear_content_area()
        self.current_view = "dashboard"  # 현재 뷰 설정

        # 헤더 - 컴팩트하게
        header = ctk.CTkLabel(
            self.content_area,
            text="📊 시스템 대시보드",
            font=ctk.CTkFont(size=24, weight="bold")
        )
        header.pack(pady=(15, 10), padx=20, anchor="w")

        # 스크롤 가능한 프레임 - 스크롤 개선
        scroll_frame = ctk.CTkScrollableFrame(
            self.content_area,
            fg_color="transparent"
        )
        scroll_frame.pack(fill="both", expand=True, padx=20, pady=(0, 15))
        self.bind_mousewheel(scroll_frame)

        # 시스템 리소스 카드 - 컴팩트
        resource_card = self.create_card(scroll_frame, "💻 시스템 리소스")
        resource_card.pack(fill="x", pady=(0, 10))

        # 리소스를 가로로 배치
        resource_grid = ctk.CTkFrame(resource_card, fg_color="transparent")
        resource_grid.pack(fill="x", padx=15, pady=10)

        # CPU
        cpu_frame = ctk.CTkFrame(resource_grid, fg_color="transparent")
        cpu_frame.pack(side="left", fill="x", expand=True, padx=5)

        cpu_header = ctk.CTkFrame(cpu_frame, fg_color="transparent")
        cpu_header.pack(fill="x")
        self.cpu_label = ctk.CTkLabel(cpu_header, text="CPU", font=ctk.CTkFont(size=11, weight="bold"))
        self.cpu_label.pack(side="left")
        self.cpu_value_label = ctk.CTkLabel(cpu_header, text="0%", font=ctk.CTkFont(size=11))
        self.cpu_value_label.pack(side="right")

        self.cpu_progress = ctk.CTkProgressBar(cpu_frame, height=12)
        self.cpu_progress.pack(fill="x", pady=(2, 0))

        # 메모리
        mem_frame = ctk.CTkFrame(resource_grid, fg_color="transparent")
        mem_frame.pack(side="left", fill="x", expand=True, padx=5)

        mem_header = ctk.CTkFrame(mem_frame, fg_color="transparent")
        mem_header.pack(fill="x")
        self.mem_label = ctk.CTkLabel(mem_header, text="메모리", font=ctk.CTkFont(size=11, weight="bold"))
        self.mem_label.pack(side="left")
        self.mem_value_label = ctk.CTkLabel(mem_header, text="0%", font=ctk.CTkFont(size=11))
        self.mem_value_label.pack(side="right")

        self.mem_progress = ctk.CTkProgressBar(mem_frame, height=12)
        self.mem_progress.pack(fill="x", pady=(2, 0))

        # 디스크
        disk_frame = ctk.CTkFrame(resource_grid, fg_color="transparent")
        disk_frame.pack(side="left", fill="x", expand=True, padx=5)

        disk_header = ctk.CTkFrame(disk_frame, fg_color="transparent")
        disk_header.pack(fill="x")
        self.disk_label = ctk.CTkLabel(disk_header, text="디스크", font=ctk.CTkFont(size=11, weight="bold"))
        self.disk_label.pack(side="left")
        self.disk_value_label = ctk.CTkLabel(disk_header, text="0%", font=ctk.CTkFont(size=11))
        self.disk_value_label.pack(side="right")

        self.disk_progress = ctk.CTkProgressBar(disk_frame, height=12)
        self.disk_progress.pack(fill="x", pady=(2, 0))

        # 2열 레이아웃으로 네트워크와 서비스를 나란히 배치
        row_frame = ctk.CTkFrame(scroll_frame, fg_color="transparent")
        row_frame.pack(fill="x", pady=(0, 10))

        # 네트워크 정보 카드 - 왼쪽
        network_card = self.create_card(row_frame, "🌐 네트워크")
        network_card.pack(side="left", fill="both", expand=True, padx=(0, 5))

        self.network_info_frame = ctk.CTkFrame(network_card, fg_color="transparent")
        self.network_info_frame.pack(fill="x", padx=15, pady=10)

        # 서비스 상태 카드 - 오른쪽
        service_card = self.create_card(row_frame, "⚙️  서비스")
        service_card.pack(side="left", fill="both", expand=True, padx=(5, 0))

        self.service_info_frame = ctk.CTkFrame(service_card, fg_color="transparent")
        self.service_info_frame.pack(fill="x", padx=15, pady=10)

        # 클라이언트 요약 카드
        client_card = self.create_card(scroll_frame, "🖥️  클라이언트")
        client_card.pack(fill="x", pady=(0, 10))

        self.client_summary_frame = ctk.CTkFrame(client_card, fg_color="transparent")
        self.client_summary_frame.pack(fill="x", padx=15, pady=10)

        # 상태 업데이트
        self.update_dashboard()

    def create_card(self, parent, title):
        """카드 스타일 프레임 생성 - 컴팩트 버전"""
        card = ctk.CTkFrame(parent, corner_radius=8)

        title_label = ctk.CTkLabel(
            card,
            text=title,
            font=ctk.CTkFont(size=14, weight="bold")
        )
        title_label.pack(anchor="w", padx=15, pady=(10, 5))

        return card

    def update_dashboard(self):
        """대시보드 정보 업데이트"""
        # 현재 대시보드가 아니면 업데이트하지 않음
        if self.current_view != "dashboard":
            return

        # 위젯이 없으면 업데이트하지 않음
        if not hasattr(self, 'cpu_progress'):
            return

        try:
            # 위젯이 여전히 유효한지 확인
            if not self.cpu_progress.winfo_exists():
                return
            # CPU
            cpu_percent = psutil.cpu_percent(interval=0.1)
            self.cpu_progress.set(cpu_percent / 100)
            self.cpu_value_label.configure(text=f"{cpu_percent:.1f}%")

            # 메모리
            mem = psutil.virtual_memory()
            self.mem_progress.set(mem.percent / 100)
            self.mem_value_label.configure(text=f"{mem.percent:.1f}%")

            # 디스크
            disk = psutil.disk_usage('/')
            self.disk_progress.set(disk.percent / 100)
            self.disk_value_label.configure(text=f"{disk.percent:.1f}%")

            # 네트워크 정보 업데이트
            for widget in self.network_info_frame.winfo_children():
                widget.destroy()

            try:
                iface = self.config['network_interface']
                addrs = netifaces.ifaddresses(iface)
                if netifaces.AF_INET in addrs:
                    ip = addrs[netifaces.AF_INET][0]['addr']
                    netmask = addrs[netifaces.AF_INET][0]['netmask']
                else:
                    ip = "N/A"
                    netmask = "N/A"
            except:
                ip = "N/A"
                netmask = "N/A"

            info_items = [
                ("인터페이스", self.config['network_interface']),
                ("IP 주소", ip),
                ("서버 IP", self.config['server_ip'])
            ]

            for label, value in info_items:
                row = ctk.CTkFrame(self.network_info_frame, fg_color="transparent")
                row.pack(fill="x", pady=1)

                lbl = ctk.CTkLabel(row, text=f"{label}:", font=ctk.CTkFont(size=10, weight="bold"), width=70, anchor="w")
                lbl.pack(side="left")

                val = ctk.CTkLabel(row, text=value, font=ctk.CTkFont(size=10), anchor="w")
                val.pack(side="left", padx=5)

            # 서비스 상태 업데이트
            for widget in self.service_info_frame.winfo_children():
                widget.destroy()

            services = ['dnsmasq', 'nfs-kernel-server']

            for service in services:
                result = subprocess.run(
                    ['systemctl', 'is-active', service],
                    capture_output=True,
                    text=True
                )
                is_active = result.stdout.strip() == 'active'

                row = ctk.CTkFrame(self.service_info_frame, fg_color="transparent")
                row.pack(fill="x", pady=1)

                status_icon = "●" if is_active else "○"
                # 짧은 이름으로 표시
                short_name = "dnsmasq" if "dnsmasq" in service else "NFS"

                icon_label = ctk.CTkLabel(
                    row,
                    text=status_icon,
                    font=ctk.CTkFont(size=14),
                    width=20,
                    text_color="green" if is_active else "gray"
                )
                icon_label.pack(side="left")

                name_label = ctk.CTkLabel(row, text=short_name, font=ctk.CTkFont(size=10), anchor="w")
                name_label.pack(side="left", padx=3)

            # 클라이언트 요약 업데이트
            for widget in self.client_summary_frame.winfo_children():
                widget.destroy()

            total_clients = len(self.config['clients'])

            # 온라인/오프라인 개수 계산 (빠른 체크 - 캐시 사용)
            online_count = 0
            offline_count = 0

            # 간단한 요약 정보
            summary_text = f"총 {total_clients}개 등록"

            summary = ctk.CTkLabel(
                self.client_summary_frame,
                text=summary_text,
                font=ctk.CTkFont(size=11)
            )
            summary.pack()

        except Exception as e:
            print(f"Dashboard update error: {e}")

    def show_client_management(self):
        """클라이언트 관리 화면"""
        # 항상 최신 설정 로드 (dnsmasq.conf에서 클라이언트 직접 읽기)
        self.config = self.load_config()
        if self.dnsmasq_conf.exists():
            self.config_mtime = self.dnsmasq_conf.stat().st_mtime

        self.clear_content_area()
        self.current_view = "clients"  # 현재 뷰 설정

        # 헤더
        header_frame = ctk.CTkFrame(self.content_area, fg_color="transparent")
        header_frame.pack(fill="x", pady=20, padx=20)

        header = ctk.CTkLabel(
            header_frame,
            text="🖥️  클라이언트 관리",
            font=ctk.CTkFont(size=28, weight="bold")
        )
        header.pack(side="left")

        # 버튼 프레임
        btn_frame = ctk.CTkFrame(header_frame, fg_color="transparent")
        btn_frame.pack(side="right")

        add_btn = ctk.CTkButton(
            btn_frame,
            text="➕ 추가",
            command=self.add_client_dialog,
            height=35,
            width=100,
            fg_color="#4CAF50",
            hover_color="#45a049"
        )
        add_btn.pack(side="left", padx=5)

        refresh_btn = ctk.CTkButton(
            btn_frame,
            text="🔄 새로고침",
            command=self.refresh_client_list,
            height=35,
            width=110,
            fg_color="#2196F3",
            hover_color="#1976D2"
        )
        refresh_btn.pack(side="left", padx=5)

        copy_sd_btn = ctk.CTkButton(
            btn_frame,
            text="💾 SD 복사",
            command=self.copy_from_sd_dialog,
            height=35,
            width=100,
            fg_color="#FF9800",
            hover_color="#F57C00"
        )
        copy_sd_btn.pack(side="left", padx=5)

        # 클라이언트 리스트 프레임
        list_frame = ctk.CTkFrame(self.content_area, corner_radius=10)
        list_frame.pack(fill="both", expand=True, padx=20, pady=(0, 20))

        # 테이블 헤더
        header_frame = ctk.CTkFrame(list_frame, fg_color=("gray80", "gray25"))
        header_frame.pack(fill="x", padx=2, pady=2)

        headers = [("번호", 60), ("시리얼/호스트명", 180), ("IP 주소", 150), ("MAC 주소", 200), ("상태", 100), ("작업", 150)]

        for text, width in headers:
            lbl = ctk.CTkLabel(
                header_frame,
                text=text,
                font=ctk.CTkFont(size=12, weight="bold"),
                width=width
            )
            lbl.pack(side="left", padx=5, pady=8)

        # 스크롤 가능한 클라이언트 리스트
        self.client_list_frame = ctk.CTkScrollableFrame(list_frame, fg_color="transparent")
        self.client_list_frame.pack(fill="both", expand=True, padx=2, pady=(0, 2))
        self.bind_mousewheel(self.client_list_frame)

        # 로딩 인디케이터 먼저 표시
        loading_label = ctk.CTkLabel(
            self.client_list_frame,
            text="⏳ 클라이언트 목록 로딩 중...",
            font=ctk.CTkFont(size=16),
            text_color="gray"
        )
        loading_label.pack(pady=100)

        # 클라이언트 목록을 백그라운드에서 렌더링
        def load_clients():
            # 백그라운드에서 실행
            import time
            time.sleep(0.1)  # UI 업데이트를 위한 짧은 딜레이

            # 메인 스레드에서 렌더링
            self.root.after(0, lambda: loading_label.destroy())
            self.root.after(0, self._render_client_list)

        threading.Thread(target=load_clients, daemon=True).start()

    def refresh_client_list(self):
        """클라이언트 목록 새로고침 (dnsmasq.conf에서 직접 읽기 - 버튼용)"""
        # 설정 파일 다시 로드 (dnsmasq.conf에서 클라이언트 읽기)
        self.config = self.load_config()

        # 수정 시간 업데이트
        if self.dnsmasq_conf.exists():
            self.config_mtime = self.dnsmasq_conf.stat().st_mtime

        # 캐시 초기화 (최신 상태로 다시 체크)
        self.client_status_cache.clear()

        # 전체 화면 새로고침
        self.show_client_management()

    def _render_client_list(self):
        """클라이언트 목록 렌더링 (내부용)"""
        # 기존 항목 제거
        for widget in self.client_list_frame.winfo_children():
            widget.destroy()

        # IP로 정렬
        sorted_clients = sorted(
            self.config['clients'],
            key=lambda c: self.ip_to_number(c.get('ip', 'N/A'))
        )

        if not sorted_clients:
            empty_label = ctk.CTkLabel(
                self.client_list_frame,
                text="등록된 클라이언트가 없습니다.\n'추가' 버튼을 눌러 새 클라이언트를 등록하세요.",
                font=ctk.CTkFont(size=14),
                text_color="gray"
            )
            empty_label.pack(pady=50)
            return

        # 상태 레이블 저장용
        status_labels = {}

        # 클라이언트 목록을 빠르게 렌더링 (상태는 캐시 사용)
        for i, client in enumerate(sorted_clients, 1):
            row_frame = ctk.CTkFrame(
                self.client_list_frame,
                fg_color=("gray90", "gray20") if i % 2 == 0 else "transparent"
            )
            row_frame.pack(fill="x", pady=1)

            # 번호
            num_lbl = ctk.CTkLabel(row_frame, text=str(i), width=60)
            num_lbl.pack(side="left", padx=5, pady=8)

            # 시리얼
            serial_lbl = ctk.CTkLabel(row_frame, text=client['serial'], width=180, anchor="w")
            serial_lbl.pack(side="left", padx=5)

            # IP
            ip_lbl = ctk.CTkLabel(row_frame, text=client.get('ip', 'N/A'), width=150, anchor="w")
            ip_lbl.pack(side="left", padx=5)

            # MAC
            mac_lbl = ctk.CTkLabel(row_frame, text=client.get('mac', 'N/A'), width=200, anchor="w")
            mac_lbl.pack(side="left", padx=5)

            # 상태 (캐시에서 가져오기 - 즉시 표시)
            ip = client.get('ip', '')
            cached_status = None
            if ip in self.client_status_cache:
                status, timestamp = self.client_status_cache[ip]
                if time.time() - timestamp < self.cache_duration:
                    cached_status = status

            if cached_status is not None:
                # 캐시된 상태 즉시 표시
                status_text = "🟢 온라인" if cached_status else "⚫ 오프라인"
                status_color = "green" if cached_status else "gray"
            else:
                # 캐시 없으면 확인중으로 표시
                status_text = "⚪ 확인중"
                status_color = "gray"

            status_lbl = ctk.CTkLabel(row_frame, text=status_text, width=100, text_color=status_color)
            status_lbl.pack(side="left", padx=5)
            status_labels[ip] = status_lbl

            # 작업 버튼
            btn_frame = ctk.CTkFrame(row_frame, fg_color="transparent", width=150)
            btn_frame.pack(side="left", padx=5)

            edit_btn = ctk.CTkButton(
                btn_frame,
                text="✏️",
                width=35,
                height=28,
                command=lambda c=client: self.edit_client_dialog(c)
            )
            edit_btn.pack(side="left", padx=2)

            del_btn = ctk.CTkButton(
                btn_frame,
                text="🗑️",
                width=35,
                height=28,
                fg_color="#D32F2F",
                hover_color="#B71C1C",
                command=lambda c=client: self.delete_client_confirm(c)
            )
            del_btn.pack(side="left", padx=2)

        # 캐시에 없는 클라이언트만 백그라운드에서 체크
        def check_uncached_status():
            # 캐시에 없는 클라이언트만 필터링
            uncached_clients = []
            for client in sorted_clients:
                ip = client.get('ip', '')
                if ip and ip not in self.client_status_cache:
                    uncached_clients.append(client)
                elif ip in self.client_status_cache:
                    # 캐시가 만료되었는지 확인
                    _, timestamp = self.client_status_cache[ip]
                    if time.time() - timestamp >= self.cache_duration:
                        uncached_clients.append(client)

            # 캐시에 없는 것만 체크
            if uncached_clients:
                status_results = self.check_multiple_clients_status(uncached_clients)

                # GUI 업데이트
                for ip, is_online in status_results.items():
                    if ip in status_labels:
                        status_text = "🟢 온라인" if is_online else "⚫ 오프라인"
                        status_color = "green" if is_online else "gray"
                        self.root.after(0, lambda lbl=status_labels[ip], txt=status_text, col=status_color:
                                       lbl.configure(text=txt, text_color=col))

        # 백그라운드 스레드로 실행 (캐시에 없는 것만)
        threading.Thread(target=check_uncached_status, daemon=True).start()

    def ip_to_number(self, ip_str):
        """IP 주소를 숫자로 변환"""
        if ip_str == 'N/A' or not ip_str:
            return 999999999
        try:
            parts = ip_str.split('.')
            return int(parts[0]) * 256**3 + int(parts[1]) * 256**2 + int(parts[2]) * 256 + int(parts[3])
        except:
            return 999999999

    def check_client_status(self, ip: str, use_cache: bool = True) -> bool:
        """클라이언트 온라인 상태 확인 (캐시 지원)"""
        if not ip or ip == 'N/A':
            return False

        # 캐시 확인
        if use_cache and ip in self.client_status_cache:
            status, timestamp = self.client_status_cache[ip]
            if time.time() - timestamp < self.cache_duration:
                return status

        # 실제 체크
        try:
            result = subprocess.run(
                ['ping', '-c', '1', '-W', '1', ip],
                capture_output=True,
                timeout=2
            )
            is_online = result.returncode == 0

            # 캐시 저장
            self.client_status_cache[ip] = (is_online, time.time())
            return is_online
        except:
            self.client_status_cache[ip] = (False, time.time())
            return False

    def check_multiple_clients_status(self, clients: list) -> dict:
        """여러 클라이언트의 상태를 병렬로 확인"""
        results = {}

        def check_one(client):
            ip = client.get('ip', '')
            if ip:
                status = self.check_client_status(ip, use_cache=False)
                return ip, status
            return ip, False

        # 최대 10개 동시 실행
        with ThreadPoolExecutor(max_workers=10) as executor:
            futures = [executor.submit(check_one, client) for client in clients]

            for future in as_completed(futures):
                try:
                    ip, status = future.result()
                    results[ip] = status
                except Exception as e:
                    print(f"Status check error: {e}")

        return results

    def add_client_dialog(self):
        """클라이언트 추가 다이얼로그"""
        dialog = ctk.CTkToplevel(self.root)
        dialog.title("새 클라이언트 추가")
        dialog.geometry("550x600")

        # 중앙 배치
        dialog.update_idletasks()
        x = (dialog.winfo_screenwidth() // 2) - (550 // 2)
        y = (dialog.winfo_screenheight() // 2) - (600 // 2)
        dialog.geometry(f"550x600+{x}+{y}")

        # 다이얼로그가 완전히 렌더링된 후 grab 설정
        dialog.after(100, lambda: dialog.transient(self.root))
        dialog.after(100, lambda: dialog.grab_set())

        # 내용 프레임
        content = ctk.CTkFrame(dialog, fg_color=("gray92", "gray14"))
        content.pack(fill="both", expand=True, padx=20, pady=(20, 10))

        title = ctk.CTkLabel(content, text="새 클라이언트 추가", font=ctk.CTkFont(size=20, weight="bold"))
        title.pack(pady=(0, 20))

        # 시리얼 번호
        serial_label = ctk.CTkLabel(content, text="시리얼 번호 (8자리 16진수):", anchor="w")
        serial_label.pack(fill="x", pady=(5, 2))
        serial_entry = ctk.CTkEntry(content, placeholder_text="예: 1234abcd")
        serial_entry.pack(fill="x", pady=(0, 15))

        # MAC 주소 - 개선된 입력 방식
        mac_label = ctk.CTkLabel(content, text="MAC 주소 프리픽스 선택:", anchor="w")
        mac_label.pack(fill="x", pady=(5, 2))

        # 프리픽스 선택 (가장 흔한 것들)
        mac_prefixes = {
            "88:a2:9e:1b": "88:a2:9e:1b (가장 흔함 - 55%)",
            "88:a2:9e:48": "88:a2:9e:48 (14%)",
            "88:a2:9e:4f": "88:a2:9e:4f (12%)",
            "d8:3a:dd:bf": "d8:3a:dd:bf (4%)",
            "88:a2:9e:13": "88:a2:9e:13 (4%)",
            "직접입력": "전체 주소 직접 입력"
        }

        mac_prefix_var = tk.StringVar(value="88:a2:9e:1b")
        mac_prefix_menu = ctk.CTkOptionMenu(
            content,
            variable=mac_prefix_var,
            values=list(mac_prefixes.values()),
            width=400
        )
        mac_prefix_menu.pack(fill="x", pady=(2, 10))

        # 마지막 2옥텟 입력
        mac_suffix_frame = ctk.CTkFrame(content, fg_color="transparent")
        mac_suffix_frame.pack(fill="x", pady=(0, 5))

        mac_suffix_label = ctk.CTkLabel(
            mac_suffix_frame,
            text="마지막 2자리 (예: e3:0f 또는 e30f):",
            anchor="w"
        )
        mac_suffix_label.pack(fill="x")

        mac_suffix_entry = ctk.CTkEntry(
            mac_suffix_frame,
            placeholder_text="예: e3:0f"
        )
        mac_suffix_entry.pack(fill="x", pady=(2, 0))

        # MAC 주소 미리보기
        mac_preview_label = ctk.CTkLabel(
            content,
            text="→ 완성된 주소: ",
            font=ctk.CTkFont(size=11, weight="bold"),
            anchor="w",
            text_color=("#2196F3", "#64B5F6")
        )
        mac_preview_label.pack(fill="x", pady=(5, 15))

        # 실시간 미리보기 업데이트
        def update_mac_preview(*args):
            prefix_display = mac_prefix_var.get()
            # 표시명에서 실제 프리픽스 추출
            for key, val in mac_prefixes.items():
                if val == prefix_display:
                    prefix = key
                    break

            suffix = mac_suffix_entry.get().strip().lower().replace(":", "")

            if prefix == "직접입력":
                mac_preview_label.configure(text="→ 완성된 주소: (전체 MAC 주소를 아래에 입력하세요)")
                return

            if len(suffix) == 4:
                full_mac = f"{prefix}:{suffix[:2]}:{suffix[2:]}"
                mac_preview_label.configure(text=f"→ 완성된 주소: {full_mac}")
            elif len(suffix) == 5 and ':' in suffix:
                full_mac = f"{prefix}:{suffix}"
                mac_preview_label.configure(text=f"→ 완성된 주소: {full_mac}")
            else:
                mac_preview_label.configure(text="→ 완성된 주소: (4자리 입력하세요)")

        mac_prefix_var.trace_add("write", update_mac_preview)
        mac_suffix_entry.bind("<KeyRelease>", update_mac_preview)
        update_mac_preview()  # 초기 업데이트

        # IP 주소
        network_prefix = ".".join(self.config['server_ip'].split('.')[:3])
        used_ips = [int(c['ip'].split('.')[-1]) for c in self.config['clients']
                    if c.get('ip', '').startswith(network_prefix)]

        suggested_ip = f"{network_prefix}.100"
        if used_ips:
            used_ips.sort()
            for num in range(100, max(used_ips) + 2):
                if num not in used_ips:
                    suggested_ip = f"{network_prefix}.{num}"
                    break

        ip_label = ctk.CTkLabel(content, text="IP 주소:", anchor="w")
        ip_label.pack(fill="x", pady=(5, 2))
        ip_entry = ctk.CTkEntry(content, placeholder_text=suggested_ip)
        ip_entry.insert(0, suggested_ip)
        ip_entry.pack(fill="x", pady=(0, 15))

        # 버튼 프레임 (dialog에 직접 추가 - content 밖)
        btn_frame = ctk.CTkFrame(dialog, fg_color="transparent")
        btn_frame.pack(fill="x", padx=20, pady=(0, 20))

        def on_add():
            serial = serial_entry.get().strip().lower()
            ip = ip_entry.get().strip()

            # 유효성 검사
            if not serial:
                messagebox.showerror("오류", "시리얼 번호를 입력하세요.")
                return

            # MAC 주소 조합
            prefix_display = mac_prefix_var.get()
            # 표시명에서 실제 프리픽스 추출
            prefix = None
            for key, val in mac_prefixes.items():
                if val == prefix_display:
                    prefix = key
                    break

            if prefix == "직접입력":
                # 전체 주소 직접 입력 모드
                mac_input = mac_suffix_entry.get().strip().lower()
                if not mac_input:
                    messagebox.showerror("오류", "MAC 주소를 입력하세요.")
                    return
                mac = mac_input
            else:
                # 프리픽스 + 마지막 2옥텟 모드
                suffix = mac_suffix_entry.get().strip().lower().replace(":", "")
                if not suffix:
                    messagebox.showerror("오류", "MAC 주소 마지막 4자리를 입력하세요.")
                    return

                if len(suffix) == 4:
                    mac = f"{prefix}:{suffix[:2]}:{suffix[2:]}"
                elif len(suffix) == 5 and ':' in mac_suffix_entry.get():
                    mac = f"{prefix}:{suffix.replace(':', '')[:2]}:{suffix.replace(':', '')[2:]}"
                else:
                    messagebox.showerror("오류", "마지막 4자리를 올바르게 입력하세요 (예: e30f 또는 e3:0f).")
                    return

            # MAC 주소 형식 확인
            if not re.match(r'^([0-9a-f]{2}:){5}[0-9a-f]{2}$', mac):
                messagebox.showerror("오류", "올바른 MAC 주소 형식이 아닙니다.")
                return

            # 중복 확인
            for client in self.config['clients']:
                if client['serial'] == serial:
                    messagebox.showerror("오류", "이미 등록된 시리얼 번호입니다.")
                    return
                if client.get('mac') == mac:
                    messagebox.showerror("오류", "이미 등록된 MAC 주소입니다.")
                    return

            # 클라이언트 추가
            new_client = {
                'serial': serial,
                'hostname': serial,
                'mac': mac,
                'ip': ip,
                'online': False
            }

            self.config['clients'].append(new_client)
            self.save_config()

            dialog.destroy()

            # 완전한 PXE 설정 (CLI와 동일하게)
            self.setup_complete_pxe_client(serial, mac, ip, serial)

        # 버튼들
        cancel_btn = ctk.CTkButton(
            btn_frame,
            text="취소",
            command=dialog.destroy,
            width=120,
            height=35,
            fg_color="gray",
            hover_color="darkgray",
            font=ctk.CTkFont(size=14, weight="bold")
        )
        cancel_btn.pack(side="right", padx=5)

        add_btn = ctk.CTkButton(
            btn_frame,
            text="✅ 추가",
            command=on_add,
            width=120,
            height=35,
            fg_color="#4CAF50",
            hover_color="#45a049",
            font=ctk.CTkFont(size=14, weight="bold")
        )
        add_btn.pack(side="right", padx=5)

    def edit_client_dialog(self, client):
        """클라이언트 편집 다이얼로그"""
        dialog = ctk.CTkToplevel(self.root)
        dialog.title("클라이언트 편집")
        dialog.geometry("500x400")

        # 중앙 배치
        dialog.update_idletasks()
        x = (dialog.winfo_screenwidth() // 2) - (500 // 2)
        y = (dialog.winfo_screenheight() // 2) - (400 // 2)
        dialog.geometry(f"500x400+{x}+{y}")

        # 다이얼로그가 완전히 렌더링된 후 grab 설정
        dialog.after(100, lambda: dialog.transient(self.root))
        dialog.after(100, lambda: dialog.grab_set())

        content = ctk.CTkFrame(dialog, fg_color=("gray92", "gray14"))
        content.pack(fill="both", expand=True, padx=20, pady=(20, 10))

        title = ctk.CTkLabel(content, text="클라이언트 편집", font=ctk.CTkFont(size=20, weight="bold"))
        title.pack(pady=(0, 20))

        # 시리얼 (읽기 전용)
        serial_label = ctk.CTkLabel(content, text="시리얼 번호:", anchor="w")
        serial_label.pack(fill="x", pady=(5, 2))
        serial_entry = ctk.CTkEntry(content)
        serial_entry.insert(0, client['serial'])
        serial_entry.configure(state="disabled")
        serial_entry.pack(fill="x", pady=(0, 15))

        # MAC 주소
        mac_label = ctk.CTkLabel(content, text="MAC 주소:", anchor="w")
        mac_label.pack(fill="x", pady=(5, 2))
        mac_entry = ctk.CTkEntry(content)
        mac_entry.insert(0, client.get('mac', ''))
        mac_entry.pack(fill="x", pady=(0, 15))

        # IP 주소
        ip_label = ctk.CTkLabel(content, text="IP 주소:", anchor="w")
        ip_label.pack(fill="x", pady=(5, 2))
        ip_entry = ctk.CTkEntry(content)
        ip_entry.insert(0, client.get('ip', ''))
        ip_entry.pack(fill="x", pady=(0, 10))

        # 버튼 프레임 (dialog에 직접 추가 - content 밖)
        btn_frame = ctk.CTkFrame(dialog, fg_color="transparent")
        btn_frame.pack(fill="x", padx=20, pady=(0, 20))

        def on_save():
            new_mac = mac_entry.get().strip().lower()
            new_ip = ip_entry.get().strip()

            # MAC 형식 확인
            if not re.match(r'^([0-9a-f]{2}:){5}[0-9a-f]{2}$', new_mac):
                messagebox.showerror("오류", "올바른 MAC 주소 형식이 아닙니다.")
                return

            # 업데이트
            client['mac'] = new_mac
            client['ip'] = new_ip
            self.save_config()

            messagebox.showinfo("성공", "클라이언트 정보가 업데이트되었습니다.")
            dialog.destroy()
            self.refresh_client_list()

        cancel_btn = ctk.CTkButton(
            btn_frame,
            text="취소",
            command=dialog.destroy,
            width=100,
            fg_color="gray",
            hover_color="darkgray"
        )
        cancel_btn.pack(side="right", padx=5)

        save_btn = ctk.CTkButton(
            btn_frame,
            text="저장",
            command=on_save,
            width=100,
            fg_color="#4CAF50",
            hover_color="#45a049"
        )
        save_btn.pack(side="right", padx=5)

    def delete_client_confirm(self, client):
        """클라이언트 삭제 확인"""
        result = messagebox.askyesno(
            "삭제 확인",
            f"정말로 이 클라이언트를 삭제하시겠습니까?\n\n시리얼: {client['serial']}\nIP: {client.get('ip', 'N/A')}"
        )

        if result:
            self.config['clients'].remove(client)
            self.save_config()
            messagebox.showinfo("성공", "클라이언트가 삭제되었습니다.")
            self.refresh_client_list()

    def create_client_config(self, serial, mac, ip, hostname):
        """클라이언트 PXE 설정 생성 (간략 버전)"""
        try:
            # dnsmasq 설정 생성
            config_dir = Path('/etc/dnsmasq.d')
            if config_dir.exists():
                config_file = config_dir / f'pxe-client-{serial}.conf'
                config_content = f"""# PXE Client: {serial}
dhcp-host={mac},{ip},{hostname},infinite
"""
                self.run_sudo(['tee', str(config_file)],
                            input_data=config_content.encode())

                # dnsmasq 재시작
                self.run_sudo(['systemctl', 'restart', 'dnsmasq'])
        except Exception as e:
            print(f"Config creation error: {e}")

    def show_server_settings(self):
        """서버 설정 화면"""
        self.clear_content_area()
        self.current_view = "settings"  # 현재 뷰 설정

        header = ctk.CTkLabel(
            self.content_area,
            text="⚙️  서버 설정",
            font=ctk.CTkFont(size=28, weight="bold")
        )
        header.pack(pady=20, padx=20, anchor="w")

        scroll_frame = ctk.CTkScrollableFrame(self.content_area)
        scroll_frame.pack(fill="both", expand=True, padx=20, pady=(0, 20))

        # 네트워크 설정 카드
        network_card = self.create_card(scroll_frame, "🌐 네트워크 설정")
        network_card.pack(fill="x", pady=(0, 15))

        settings_frame = ctk.CTkFrame(network_card, fg_color="transparent")
        settings_frame.pack(fill="x", padx=20, pady=15)

        settings = [
            ("서버 IP", 'server_ip'),
            ("DHCP 시작", 'dhcp_range_start'),
            ("DHCP 끝", 'dhcp_range_end'),
            ("네트워크 인터페이스", 'network_interface'),
            ("NFS 루트", 'nfs_root'),
            ("TFTP 루트", 'tftp_root'),
        ]

        entries = {}

        for label_text, key in settings:
            row = ctk.CTkFrame(settings_frame, fg_color="transparent")
            row.pack(fill="x", pady=5)

            label = ctk.CTkLabel(row, text=f"{label_text}:", width=200, anchor="w", font=ctk.CTkFont(size=12, weight="bold"))
            label.pack(side="left", padx=5)

            entry = ctk.CTkEntry(row, width=300)
            entry.insert(0, self.config.get(key, ''))
            entry.pack(side="left", padx=5)
            entries[key] = entry

        # 저장 버튼
        save_btn = ctk.CTkButton(
            network_card,
            text="💾 설정 저장",
            command=lambda: self.save_server_settings(entries),
            height=40,
            fg_color="#4CAF50",
            hover_color="#45a049"
        )
        save_btn.pack(pady=15)

    def save_server_settings(self, entries):
        """서버 설정 저장"""
        for key, entry in entries.items():
            self.config[key] = entry.get()

        self.save_config()
        messagebox.showinfo("성공", "서버 설정이 저장되었습니다.")

    def show_service_management(self):
        """서비스 관리 화면"""
        self.clear_content_area()
        self.current_view = "services"  # 현재 뷰 설정

        header = ctk.CTkLabel(
            self.content_area,
            text="🚀 서비스 관리",
            font=ctk.CTkFont(size=28, weight="bold")
        )
        header.pack(pady=20, padx=20, anchor="w")

        scroll_frame = ctk.CTkScrollableFrame(self.content_area)
        scroll_frame.pack(fill="both", expand=True, padx=20, pady=(0, 20))

        services = [
            ('dnsmasq', 'DHCP/DNS/TFTP/PXE 서버'),
            ('nfs-kernel-server', 'NFS 파일 공유 서버'),
        ]

        for service, description in services:
            card = ctk.CTkFrame(scroll_frame, corner_radius=10)
            card.pack(fill="x", pady=(0, 15))

            # 서비스 정보
            info_frame = ctk.CTkFrame(card, fg_color="transparent")
            info_frame.pack(fill="x", padx=20, pady=15)

            name_label = ctk.CTkLabel(
                info_frame,
                text=service,
                font=ctk.CTkFont(size=18, weight="bold"),
                anchor="w"
            )
            name_label.pack(anchor="w")

            desc_label = ctk.CTkLabel(
                info_frame,
                text=description,
                font=ctk.CTkFont(size=12),
                text_color="gray",
                anchor="w"
            )
            desc_label.pack(anchor="w")

            # 상태 및 제어 버튼
            control_frame = ctk.CTkFrame(card, fg_color="transparent")
            control_frame.pack(fill="x", padx=20, pady=(0, 15))

            # 상태 체크
            result = subprocess.run(
                ['systemctl', 'is-active', service],
                capture_output=True,
                text=True
            )
            is_active = result.stdout.strip() == 'active'

            status_label = ctk.CTkLabel(
                control_frame,
                text=f"{'✅ 실행 중' if is_active else '❌ 중지됨'}",
                font=ctk.CTkFont(size=14, weight="bold"),
                text_color="green" if is_active else "red"
            )
            status_label.pack(side="left")

            # 버튼들
            btn_container = ctk.CTkFrame(control_frame, fg_color="transparent")
            btn_container.pack(side="right")

            start_btn = ctk.CTkButton(
                btn_container,
                text="▶️ 시작",
                width=80,
                command=lambda s=service: self.service_action(s, 'start'),
                fg_color="#4CAF50",
                hover_color="#45a049"
            )
            start_btn.pack(side="left", padx=2)

            stop_btn = ctk.CTkButton(
                btn_container,
                text="⏸️ 중지",
                width=80,
                command=lambda s=service: self.service_action(s, 'stop'),
                fg_color="#FF9800",
                hover_color="#F57C00"
            )
            stop_btn.pack(side="left", padx=2)

            restart_btn = ctk.CTkButton(
                btn_container,
                text="🔄 재시작",
                width=90,
                command=lambda s=service: self.service_action(s, 'restart')
            )
            restart_btn.pack(side="left", padx=2)

    def service_action(self, service, action):
        """서비스 제어"""
        try:
            result = self.run_sudo(['systemctl', action, service])

            if result.returncode == 0:
                messagebox.showinfo("성공", f"{service} 서비스가 {action} 되었습니다.")
                self.show_service_management()  # 새로고침
            else:
                # stderr를 디코드 (bytes -> str)
                error_msg = result.stderr.decode('utf-8', errors='ignore')
                messagebox.showerror("오류", f"서비스 {action} 실패:\n{error_msg}")
        except Exception as e:
            messagebox.showerror("오류", f"서비스 제어 오류:\n{str(e)}")

    def show_logs(self):
        """로그 확인 화면"""
        self.clear_content_area()
        self.current_view = "logs"  # 현재 뷰 설정

        header = ctk.CTkLabel(
            self.content_area,
            text="📝 시스템 로그",
            font=ctk.CTkFont(size=28, weight="bold")
        )
        header.pack(pady=20, padx=20, anchor="w")

        # 로그 선택
        log_frame = ctk.CTkFrame(self.content_area)
        log_frame.pack(fill="x", padx=20, pady=(0, 10))

        log_label = ctk.CTkLabel(log_frame, text="서비스:", font=ctk.CTkFont(size=12, weight="bold"))
        log_label.pack(side="left", padx=10)

        log_var = ctk.StringVar(value="dnsmasq")
        log_menu = ctk.CTkOptionMenu(
            log_frame,
            variable=log_var,
            values=["dnsmasq", "nfs-kernel-server"],
            command=lambda x: self.load_log(x, text_widget)
        )
        log_menu.pack(side="left", padx=10)

        refresh_btn = ctk.CTkButton(
            log_frame,
            text="🔄 새로고침",
            command=lambda: self.load_log(log_var.get(), text_widget),
            width=100
        )
        refresh_btn.pack(side="left", padx=10)

        # 로그 텍스트
        text_frame = ctk.CTkFrame(self.content_area)
        text_frame.pack(fill="both", expand=True, padx=20, pady=(0, 20))

        text_widget = ctk.CTkTextbox(text_frame, font=ctk.CTkFont(family="Courier", size=11))
        text_widget.pack(fill="both", expand=True, padx=2, pady=2)

        # 초기 로그 로드
        self.load_log("dnsmasq", text_widget)

    def load_log(self, service, text_widget):
        """로그 로드"""
        text_widget.delete("1.0", "end")
        text_widget.insert("1.0", f"로그를 불러오는 중...\n")

        def load():
            try:
                result = subprocess.run(
                    ['journalctl', '-u', service, '-n', '100', '--no-pager'],
                    capture_output=True,
                    text=True
                )

                self.root.after(0, lambda: text_widget.delete("1.0", "end"))
                self.root.after(0, lambda: text_widget.insert("1.0", result.stdout))
            except Exception as e:
                self.root.after(0, lambda: text_widget.delete("1.0", "end"))
                self.root.after(0, lambda: text_widget.insert("1.0", f"로그 로드 오류:\n{str(e)}"))

        threading.Thread(target=load, daemon=True).start()

    def show_initial_setup(self):
        """초기 설정 화면"""
        self.clear_content_area()
        self.current_view = "setup"  # 현재 뷰 설정

        header = ctk.CTkLabel(
            self.content_area,
            text="🔧 초기 설정 마법사",
            font=ctk.CTkFont(size=28, weight="bold")
        )
        header.pack(pady=20, padx=20, anchor="w")

        scroll_frame = ctk.CTkScrollableFrame(self.content_area)
        scroll_frame.pack(fill="both", expand=True, padx=20, pady=(0, 20))

        info_card = self.create_card(scroll_frame, "ℹ️  설정 안내")
        info_card.pack(fill="x", pady=(0, 15))

        info_text = """초기 설정은 다음 작업을 수행합니다:

1. 필요한 패키지 설치 확인
2. 네트워크 인터페이스 감지
3. dnsmasq 설정 생성
4. NFS 서버 설정
5. TFTP 부트 파일 준비
6. 서비스 시작

주의: 이 작업은 시스템 설정을 변경합니다. (sudo 인증 자동화됨)
"""

        info_label = ctk.CTkLabel(
            info_card,
            text=info_text,
            font=ctk.CTkFont(size=12),
            justify="left",
            anchor="w"
        )
        info_label.pack(padx=20, pady=15, fill="x")

        # 실행 버튼
        run_btn = ctk.CTkButton(
            info_card,
            text="🚀 초기 설정 실행",
            command=self.run_initial_setup,
            height=50,
            font=ctk.CTkFont(size=14, weight="bold"),
            fg_color="#4CAF50",
            hover_color="#45a049"
        )
        run_btn.pack(pady=15)

        # 진행 상황 표시
        self.setup_progress_frame = ctk.CTkFrame(scroll_frame, corner_radius=10)
        self.setup_progress_frame.pack(fill="x", pady=(0, 15))

        self.setup_log_text = ctk.CTkTextbox(
            self.setup_progress_frame,
            height=200,
            font=ctk.CTkFont(family="Courier", size=11)
        )
        self.setup_log_text.pack(fill="both", padx=10, pady=10)

    def run_initial_setup(self):
        """초기 설정 실행"""
        self.setup_log_text.delete("1.0", "end")
        self.setup_log_text.insert("1.0", "초기 설정을 시작합니다...\n\n")

        def setup():
            steps = [
                ("패키지 확인", self.check_packages),
                ("네트워크 설정", self.setup_network),
                ("dnsmasq 설정", self.setup_dnsmasq),
                ("NFS 설정", self.setup_nfs),
            ]

            for step_name, step_func in steps:
                self.log_setup(f"[{step_name}] 진행 중...")
                try:
                    step_func()
                    self.log_setup(f"[{step_name}] ✅ 완료\n")
                except Exception as e:
                    self.log_setup(f"[{step_name}] ❌ 오류: {str(e)}\n")

            self.log_setup("\n초기 설정이 완료되었습니다!")

        threading.Thread(target=setup, daemon=True).start()

    def log_setup(self, message):
        """설정 로그 출력"""
        self.root.after(0, lambda: self.setup_log_text.insert("end", message + "\n"))
        self.root.after(0, lambda: self.setup_log_text.see("end"))

    def check_packages(self):
        """패키지 확인"""
        packages = ['dnsmasq', 'nfs-kernel-server']
        for pkg in packages:
            result = subprocess.run(['dpkg', '-l', pkg], capture_output=True)
            if result.returncode != 0:
                self.log_setup(f"  {pkg} 설치 필요")

    def setup_network(self):
        """네트워크 설정"""
        self.log_setup(f"  서버 IP: {self.config['server_ip']}")
        self.log_setup(f"  인터페이스: {self.config['network_interface']}")

    def setup_dnsmasq(self):
        """dnsmasq 설정"""
        self.log_setup("  dnsmasq 설정 파일 생성 중...")

    def setup_nfs(self):
        """NFS 설정"""
        nfs_root = Path(self.config['nfs_root'])
        if not nfs_root.exists():
            self.log_setup(f"  NFS 루트 생성: {nfs_root}")

    def start_status_updates(self):
        """상태 업데이트 스레드 시작"""
        def update_loop():
            while self.running:
                try:
                    # 대시보드일 때만 업데이트
                    if self.current_view == "dashboard":
                        self.root.after(0, self.update_dashboard)
                except Exception as e:
                    # 에러 무시 (위젯이 삭제된 경우)
                    pass
                threading.Event().wait(2)  # 2초마다 업데이트

        threading.Thread(target=update_loop, daemon=True).start()

    def start_background_status_checker(self):
        """백그라운드에서 주기적으로 클라이언트 상태 갱신 및 dnsmasq.conf 모니터링"""
        def checker_loop():
            while self.running:
                try:
                    # 1. dnsmasq.conf 변경 감지 (CLI에서 클라이언트 추가 시 자동 반영)
                    if self.dnsmasq_conf.exists():
                        current_mtime = self.dnsmasq_conf.stat().st_mtime
                        if current_mtime != self.config_mtime:
                            print(f"dnsmasq.conf 변경 감지 - 자동 새로고침")
                            self.config_mtime = current_mtime

                            # 설정 파일 다시 로드 (dnsmasq.conf에서 클라이언트 읽기)
                            old_count = len(self.config.get('clients', []))
                            self.config = self.load_config()
                            new_count = len(self.config.get('clients', []))

                            # 클라이언트 관리 화면이 활성화되어 있으면 자동 새로고침
                            if self.current_view == "clients":
                                self.root.after(0, self._render_client_list)
                                print(f"클라이언트 목록 자동 새로고침 (클라이언트 수: {old_count} → {new_count})")

                    # 2. 클라이언트 상태 갱신
                    if self.config.get('clients'):
                        self.check_multiple_clients_status(self.config['clients'])
                except Exception as e:
                    print(f"Background status check error: {e}")
                threading.Event().wait(5)  # 5초마다 체크

        threading.Thread(target=checker_loop, daemon=True).start()

    def bind_mousewheel(self, widget):
        """마우스 휠 스크롤 바인딩"""
        def _on_mousewheel(event):
            # 스크롤 양 조정
            if event.num == 5 or event.delta < 0:
                # 아래로 스크롤
                widget._parent_canvas.yview_scroll(1, "units")
            elif event.num == 4 or event.delta > 0:
                # 위로 스크롤
                widget._parent_canvas.yview_scroll(-1, "units")

        # Linux/Unix (Button-4, Button-5)
        widget.bind_all("<Button-4>", _on_mousewheel)
        widget.bind_all("<Button-5>", _on_mousewheel)
        # Windows/Mac (MouseWheel)
        widget.bind_all("<MouseWheel>", _on_mousewheel)

    def copy_from_sd_dialog(self):
        """SD 카드에서 시스템 복사 다이얼로그"""
        if not self.config['clients']:
            messagebox.showwarning("경고", "등록된 클라이언트가 없습니다.\n먼저 클라이언트를 추가하세요.")
            return

        dialog = ctk.CTkToplevel(self.root)
        dialog.title("SD 카드에서 시스템 복사")
        dialog.geometry("700x600")

        # 중앙 배치
        dialog.update_idletasks()
        x = (dialog.winfo_screenwidth() // 2) - (700 // 2)
        y = (dialog.winfo_screenheight() // 2) - (600 // 2)
        dialog.geometry(f"700x600+{x}+{y}")

        # 다이얼로그가 완전히 렌더링된 후 grab 설정
        dialog.after(100, lambda: dialog.transient(self.root))
        dialog.after(100, lambda: dialog.grab_set())

        content = ctk.CTkFrame(dialog, fg_color=("gray92", "gray14"))
        content.pack(fill="both", expand=True, padx=20, pady=(20, 10))

        title = ctk.CTkLabel(content, text="SD 카드에서 시스템 복사", font=ctk.CTkFont(size=20, weight="bold"))
        title.pack(pady=(0, 10))

        info = ctk.CTkLabel(
            content,
            text="라즈베리파이 OS가 설치된 SD 카드를 NFS 루트로 복사합니다.\n시간이 오래 걸릴 수 있습니다 (5-10분).",
            font=ctk.CTkFont(size=12),
            text_color="gray"
        )
        info.pack(pady=(0, 20))

        # 클라이언트 선택
        client_frame = ctk.CTkFrame(content)
        client_frame.pack(fill="x", pady=(0, 15))

        client_label = ctk.CTkLabel(client_frame, text="대상 클라이언트:", font=ctk.CTkFont(size=12, weight="bold"))
        client_label.pack(anchor="w", padx=10, pady=(10, 5))

        client_var = ctk.StringVar(value=self.config['clients'][0]['serial'])
        client_menu = ctk.CTkOptionMenu(
            client_frame,
            variable=client_var,
            values=[c['serial'] for c in self.config['clients']],
            width=300
        )
        client_menu.pack(padx=10, pady=(0, 10))

        # SD 카드 감지 버튼
        detect_frame = ctk.CTkFrame(content)
        detect_frame.pack(fill="x", pady=(0, 15))

        detect_label = ctk.CTkLabel(detect_frame, text="SD 카드 파티션:", font=ctk.CTkFont(size=12, weight="bold"))
        detect_label.pack(anchor="w", padx=10, pady=(10, 5))

        device_text = ctk.CTkTextbox(detect_frame, height=150, font=ctk.CTkFont(family="Courier", size=10))
        device_text.pack(fill="both", padx=10, pady=(0, 10))

        def detect_devices():
            device_text.delete("1.0", "end")
            device_text.insert("1.0", "SD 카드 감지 중...\n")

            try:
                result = subprocess.run(
                    ['lsblk', '-o', 'NAME,SIZE,TYPE,MOUNTPOINT', '-p'],
                    capture_output=True,
                    text=True
                )
                device_text.delete("1.0", "end")
                device_text.insert("1.0", result.stdout)
            except Exception as e:
                device_text.delete("1.0", "end")
                device_text.insert("1.0", f"오류: {str(e)}")

        detect_btn = ctk.CTkButton(
            detect_frame,
            text="🔍 SD 카드 감지",
            command=detect_devices,
            width=150
        )
        detect_btn.pack(padx=10, pady=(0, 10))

        # 파티션 입력
        partition_frame = ctk.CTkFrame(content)
        partition_frame.pack(fill="x", pady=(0, 15))

        boot_label = ctk.CTkLabel(partition_frame, text="Boot 파티션 (예: /dev/sdb1):", anchor="w")
        boot_label.pack(fill="x", padx=10, pady=(10, 2))
        boot_entry = ctk.CTkEntry(partition_frame, placeholder_text="/dev/sdb1")
        boot_entry.pack(fill="x", padx=10, pady=(0, 10))

        root_label = ctk.CTkLabel(partition_frame, text="Root 파티션 (예: /dev/sdb2):", anchor="w")
        root_label.pack(fill="x", padx=10, pady=(5, 2))
        root_entry = ctk.CTkEntry(partition_frame, placeholder_text="/dev/sdb2")
        root_entry.pack(fill="x", padx=10, pady=(0, 10))

        # 진행 상황
        progress_label = ctk.CTkLabel(content, text="", font=ctk.CTkFont(size=11))
        progress_label.pack(pady=5)

        # 버튼 프레임 (dialog에 직접 추가 - content 밖)
        btn_frame = ctk.CTkFrame(dialog, fg_color="transparent")
        btn_frame.pack(fill="x", padx=20, pady=(0, 20))

        def start_copy():
            serial = client_var.get()
            boot_dev = boot_entry.get().strip()
            root_dev = root_entry.get().strip()

            if not boot_dev or not root_dev:
                messagebox.showerror("오류", "Boot 파티션과 Root 파티션을 모두 입력하세요.")
                return

            result = messagebox.askyesno(
                "확인",
                f"다음 내용으로 복사를 시작합니다:\n\n"
                f"클라이언트: {serial}\n"
                f"Boot: {boot_dev}\n"
                f"Root: {root_dev}\n\n"
                f"계속하시겠습니까?"
            )

            if not result:
                return

            # 복사 시작 (백그라운드)
            progress_label.configure(text="복사 중... 잠시만 기다려주세요 (5-10분 소요)")

            def copy_task():
                try:
                    nfs_path = Path(self.config['nfs_root']) / serial
                    tftp_path = Path(self.config['tftp_root']) / serial

                    # 디렉토리 생성
                    self.run_sudo(['mkdir', '-p', str(nfs_path), str(tftp_path)])

                    # 임시 마운트
                    temp_boot = f"/tmp/sd_boot_{serial}"
                    temp_root = f"/tmp/sd_root_{serial}"
                    self.run_sudo(['mkdir', '-p', temp_boot, temp_root])

                    # 마운트
                    self.run_sudo(['mount', boot_dev, temp_boot])
                    self.run_sudo(['mount', root_dev, temp_root])

                    # 복사
                    self.run_sudo(['cp', '-a', f"{temp_boot}/.", str(tftp_path)])
                    self.run_sudo(['rsync', '-aHAXx', '--info=progress2',
                                  f"{temp_root}/", f"{nfs_path}/"])

                    # 언마운트
                    self.run_sudo(['umount', temp_boot])
                    self.run_sudo(['umount', temp_root])
                    self.run_sudo(['rmdir', temp_boot, temp_root])

                    self.root.after(0, lambda: progress_label.configure(text="✅ 복사 완료!"))
                    self.root.after(0, lambda: messagebox.showinfo("완료", f"클라이언트 {serial}의 시스템 복사가 완료되었습니다!"))
                    self.root.after(0, dialog.destroy)

                except Exception as e:
                    self.root.after(0, lambda: progress_label.configure(text=f"❌ 오류 발생"))
                    self.root.after(0, lambda: messagebox.showerror("오류", f"복사 중 오류 발생:\n{str(e)}"))

            threading.Thread(target=copy_task, daemon=True).start()

        cancel_btn = ctk.CTkButton(
            btn_frame,
            text="취소",
            command=dialog.destroy,
            width=100,
            fg_color="gray",
            hover_color="darkgray"
        )
        cancel_btn.pack(side="right", padx=5)

        copy_btn = ctk.CTkButton(
            btn_frame,
            text="💾 복사 시작",
            command=start_copy,
            width=120,
            fg_color="#4CAF50",
            hover_color="#45a049"
        )
        copy_btn.pack(side="right", padx=5)

        # 초기 감지
        detect_devices()

    def on_closing(self):
        """프로그램 종료"""
        self.running = False
        self.root.quit()
        self.root.destroy()

    def setup_complete_pxe_client(self, serial: str, mac: str, ip: str, hostname: str):
        """완전한 PXE 클라이언트 설정 (CLI와 동일)"""
        # 프로그레스 다이얼로그 생성
        progress_dialog = ctk.CTkToplevel(self.root)
        progress_dialog.title("PXE 클라이언트 설정 중...")
        progress_dialog.geometry("600x400")

        dialog_x = (progress_dialog.winfo_screenwidth() // 2) - (600 // 2)
        dialog_y = (progress_dialog.winfo_screenheight() // 2) - (400 // 2)
        progress_dialog.geometry(f"600x400+{dialog_x}+{dialog_y}")

        progress_dialog.after(100, lambda: progress_dialog.transient(self.root))
        progress_dialog.after(100, lambda: progress_dialog.grab_set())

        content = ctk.CTkFrame(progress_dialog, fg_color=("gray92", "gray14"))
        content.pack(fill="both", expand=True, padx=20, pady=20)

        title = ctk.CTkLabel(content, text=f"클라이언트 {serial} 설정 중",
                            font=ctk.CTkFont(size=18, weight="bold"))
        title.pack(pady=(0, 20))

        # 로그 텍스트 영역
        log_text = ctk.CTkTextbox(content, height=250, width=550)
        log_text.pack(fill="both", expand=True, pady=(0, 10))

        def log(message):
            """로그 추가"""
            log_text.insert("end", message + "\n")
            log_text.see("end")
            progress_dialog.update()

        # 백그라운드에서 실행
        def setup_task():
            try:
                nfs_path = Path(self.config['nfs_root']) / serial
                tftp_path = Path(self.config['tftp_root']) / serial

                # 1. 디렉토리 생성
                log("📁 디렉토리 생성 중...")
                self.run_sudo(['mkdir', '-p', str(nfs_path)])
                self.run_sudo(['mkdir', '-p', str(tftp_path)])
                self.run_sudo(['chmod', '755', str(nfs_path)])
                self.run_sudo(['chmod', '755', str(tftp_path)])
                log("✅ 디렉토리 생성 완료")

                # 2. DHCP 설정
                log("\n📡 DHCP 설정 업데이트 중...")
                self.create_client_config(serial, mac, ip, hostname)
                log("✅ DHCP 설정 완료")

                # 3. NFS exports 설정
                log("\n📂 NFS exports 설정 중...")
                self.update_nfs_exports(serial)
                log("✅ NFS exports 완료")

                # 4. TFTP 부트 파일 설정
                log("\n🚀 TFTP 부트 파일 설정 중...")
                self.setup_tftp_boot_files(serial, ip, hostname)
                log("✅ TFTP 부트 파일 완료")

                log(f"\n✅ PXE 부팅 설정 완료!")
                log(f"  - NFS: {nfs_path}")
                log(f"  - TFTP: {tftp_path}")
                log(f"  - 고정 IP: {ip} (MAC: {mac})")

                # 5. 기존 클라이언트에서 시스템 복사
                existing_clients = [c for c in self.config['clients'] if c['serial'] != serial]
                if existing_clients:
                    log(f"\n🔍 기존 클라이언트 찾는 중...")
                    for client in existing_clients:
                        source_nfs = Path(self.config['nfs_root']) / client['serial']
                        if source_nfs.exists() and (source_nfs / 'etc').exists():
                            log(f"📋 기존 클라이언트({client['serial']})에서 시스템 복사 시작...")
                            self.copy_system_from_existing(client['serial'], serial, mac, ip, hostname, log)
                            break
                    else:
                        log("\n⚠️  시스템 파일이 없습니다.")
                        log("   '💾 SD 복사' 메뉴에서 수동으로 복사하세요.")
                else:
                    log("\n⚠️  첫 번째 클라이언트입니다.")
                    log("   '💾 SD 복사' 메뉴에서 SD 카드로부터 복사하세요.")

                # 완료
                self.root.after(0, lambda: messagebox.showinfo("완료", f"클라이언트 {serial} 설정이 완료되었습니다!"))
                self.root.after(0, lambda: progress_dialog.destroy())
                self.root.after(0, self.refresh_client_list)

            except Exception as e:
                error_msg = f"설정 중 오류 발생:\n{str(e)}"
                log(f"\n❌ {error_msg}")
                self.root.after(0, lambda: messagebox.showerror("오류", error_msg))

        threading.Thread(target=setup_task, daemon=True).start()

    def update_nfs_exports(self, serial: str):
        """NFS exports 파일 업데이트"""
        nfs_path = f"{self.config['nfs_root']}/{serial}"
        export_line = f"{nfs_path} *(rw,sync,no_subtree_check,no_root_squash)\n"

        # 현재 exports 읽기
        result = subprocess.run(['cat', '/etc/exports'], capture_output=True, text=True)
        current_exports = result.stdout

        # 이미 있는지 확인
        if nfs_path not in current_exports:
            # 임시 파일 생성
            temp_exports = '/tmp/exports_append.tmp'
            with open(temp_exports, 'w') as f:
                f.write(export_line)

            # 추가
            self.run_sudo(['bash', '-c', f'cat {temp_exports} >> /etc/exports'])
            os.remove(temp_exports)

            # NFS 서비스 재시작
            self.run_sudo(['exportfs', '-ra'])
            self.run_sudo(['systemctl', 'restart', 'nfs-kernel-server'])

    def setup_tftp_boot_files(self, serial: str, ip: str, hostname: str):
        """TFTP 부트 파일 설정"""
        tftp_path = Path(self.config['tftp_root']) / serial
        nfs_path = Path(self.config['nfs_root']) / serial

        # cmdline.txt
        cmdline = f"console=serial0,115200 console=tty1 root=/dev/nfs nfsroot={self.config['server_ip']}:{nfs_path},vers=3 rw ip={ip}:::{self.config['server_ip'].rsplit('.', 1)[0]}.255:255.255.255.0:{hostname}:eth0:off elevator=deadline rootwait"

        temp_cmdline = '/tmp/cmdline.txt'
        with open(temp_cmdline, 'w') as f:
            f.write(cmdline)
        self.run_sudo(['cp', temp_cmdline, str(tftp_path / 'cmdline.txt')])
        os.remove(temp_cmdline)

        # config.txt
        config = f"""# RPI PXE Boot Configuration
# Client: {serial}
# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

initramfs initrd.img followkernel
kernel=kernel8.img
"""
        temp_config = '/tmp/config.txt'
        with open(temp_config, 'w') as f:
            f.write(config)
        self.run_sudo(['cp', temp_config, str(tftp_path / 'config.txt')])
        os.remove(temp_config)

    def copy_system_from_existing(self, source_serial: str, target_serial: str, mac: str, ip: str, hostname: str, log_func):
        """기존 클라이언트에서 시스템 자동 복사"""
        source_nfs = Path(self.config['nfs_root']) / source_serial
        source_tftp = Path(self.config['tftp_root']) / source_serial
        target_nfs = Path(self.config['nfs_root']) / target_serial
        target_tftp = Path(self.config['tftp_root']) / target_serial

        try:
            # Boot 파일 복사
            log_func("  📁 Boot 파일 복사 중...")
            self.run_sudo(['cp', '-a', f"{source_tftp}/.", str(target_tftp)])

            # Root 파일시스템 복사 (rsync)
            log_func("  💾 Root 파일시스템 복사 중 (5-10분 소요)...")
            result = self.run_sudo(['rsync', '-aHAXx', '--info=progress2',
                                   f"{source_nfs}/", f"{target_nfs}/"])

            # sudo 권한 설정
            log_func("  🔐 sudo 권한 설정 중...")
            self.run_sudo(['chmod', '4755', str(target_nfs / 'usr/bin/sudo')])

            # SSH 설정
            log_func("  🔑 SSH 설정 중...")
            # 기존 호스트 키 삭제
            ssh_dir = target_nfs / 'etc/ssh'
            self.run_sudo(['bash', '-c', f'rm -f {ssh_dir}/ssh_host_*'])

            # 새 호스트 키 생성
            self.run_sudo(['chroot', str(target_nfs), 'dpkg-reconfigure', 'openssh-server'])

            # SSH 활성화
            self.run_sudo(['chroot', str(target_nfs), 'systemctl', 'enable', 'ssh'])

            log_func("  ✅ 시스템 복사 완료!")

        except Exception as e:
            log_func(f"  ❌ 복사 중 오류: {e}")
            raise

    def run(self):
        """GUI 실행"""
        self.root.mainloop()


def main():
    """메인 함수"""
    # Root 권한 확인
    if os.geteuid() != 0:
        print("ℹ️  정보: sudo 인증이 자동으로 처리됩니다.")
        print("   시스템 변경 작업 시 자동으로 권한이 상승됩니다.\n")

    app = RPIPXEManagerGUI()
    app.run()


if __name__ == "__main__":
    main()
