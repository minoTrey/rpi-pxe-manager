#!/usr/bin/env python3
"""
RPI PXE Manager - PyQt5 GUI
"""

import os
import sys
import subprocess
import json
import re
import threading
import time
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional
from concurrent.futures import ThreadPoolExecutor

from PyQt5.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QPushButton, QFrame, QScrollArea, QTableWidget, QTableWidgetItem,
    QHeaderView, QMessageBox, QInputDialog, QDialog, QFormLayout,
    QLineEdit, QComboBox, QTextEdit, QProgressBar, QStackedWidget,
    QSplitter, QGroupBox, QTabWidget, QDialogButtonBox, QFileDialog,
    QGridLayout, QSizePolicy, QSpacerItem, QCheckBox
)
from PyQt5.QtCore import Qt, QTimer, QThread, pyqtSignal, QSize
from PyQt5.QtGui import QFont, QColor, QPalette, QIcon

try:
    import psutil
except ImportError:
    subprocess.run([sys.executable, '-m', 'pip', 'install', 'psutil', '--user', '--break-system-packages'],
                   capture_output=True)
    import psutil

try:
    import netifaces
except ImportError:
    subprocess.run([sys.executable, '-m', 'pip', 'install', 'netifaces', '--user', '--break-system-packages'],
                   capture_output=True)
    import netifaces


class PingThread(QThread):
    """클라이언트 ping 체크 스레드"""
    result_ready = pyqtSignal(str, bool)  # ip, is_online

    def __init__(self, clients: List[dict]):
        super().__init__()
        self.clients = clients
        self.running = True

    def ping_host(self, ip: str) -> tuple:
        try:
            result = subprocess.run(
                ['ping', '-c', '1', '-W', '1', ip],
                capture_output=True, timeout=2
            )
            return ip, result.returncode == 0
        except:
            return ip, False

    def run(self):
        with ThreadPoolExecutor(max_workers=20) as executor:
            ips = [c.get('ip', '') for c in self.clients if c.get('ip')]
            results = executor.map(self.ping_host, ips)
            for ip, is_online in results:
                if self.running:
                    self.result_ready.emit(ip, is_online)

    def stop(self):
        self.running = False


class StatusUpdateThread(QThread):
    """시스템 상태 업데이트 스레드"""
    status_updated = pyqtSignal(dict)

    def __init__(self):
        super().__init__()
        self.running = True

    def run(self):
        while self.running:
            status = {
                'cpu': psutil.cpu_percent(interval=1),
                'memory': psutil.virtual_memory().percent,
                'disk': psutil.disk_usage('/').percent
            }
            self.status_updated.emit(status)
            time.sleep(2)

    def stop(self):
        self.running = False


class ClientCard(QFrame):
    """클라이언트 카드 위젯"""
    edit_clicked = pyqtSignal(dict)
    delete_clicked = pyqtSignal(dict)
    detail_clicked = pyqtSignal(dict)

    def __init__(self, client: dict, index: int):
        super().__init__()
        self.client = client
        self.index = index
        self.is_online = None
        self.init_ui()

    def init_ui(self):
        self.setObjectName("client_card")
        self.setFixedHeight(60)

        layout = QHBoxLayout(self)
        layout.setContentsMargins(12, 8, 12, 8)
        layout.setSpacing(10)

        # 상태 표시등
        self.status_indicator = QLabel("●")
        self.status_indicator.setObjectName("status_pending")
        self.status_indicator.setFixedWidth(16)
        layout.addWidget(self.status_indicator)

        # 번호
        num_label = QLabel(f"{self.index}")
        num_label.setObjectName("card_num")
        num_label.setFixedWidth(28)
        num_label.setAlignment(Qt.AlignCenter)
        layout.addWidget(num_label)

        # 호스트명
        hostname = self.client.get('hostname', self.client.get('serial', 'N/A'))
        host_label = QLabel(hostname)
        host_label.setObjectName("card_hostname")
        host_label.setFixedWidth(120)
        layout.addWidget(host_label)

        # IP
        ip_label = QLabel(self.client.get('ip', 'N/A'))
        ip_label.setObjectName("card_detail")
        ip_label.setFixedWidth(110)
        layout.addWidget(ip_label)

        # MAC
        mac_label = QLabel(self.client.get('mac', 'N/A'))
        mac_label.setObjectName("card_detail")
        layout.addWidget(mac_label, 1)

        # 버튼 영역
        detail_btn = QPushButton("상세")
        detail_btn.setObjectName("card_btn")
        detail_btn.setFixedSize(55, 28)
        detail_btn.clicked.connect(lambda: self.detail_clicked.emit(self.client))
        layout.addWidget(detail_btn)

        edit_btn = QPushButton("편집")
        edit_btn.setObjectName("card_btn")
        edit_btn.setFixedSize(55, 28)
        edit_btn.clicked.connect(lambda: self.edit_clicked.emit(self.client))
        layout.addWidget(edit_btn)

        del_btn = QPushButton("삭제")
        del_btn.setObjectName("card_btn_danger")
        del_btn.setFixedSize(55, 28)
        del_btn.clicked.connect(lambda: self.delete_clicked.emit(self.client))
        layout.addWidget(del_btn)

    def set_status(self, is_online: bool):
        self.is_online = is_online
        if is_online:
            self.status_indicator.setText("●")
            self.status_indicator.setObjectName("status_online")
            self.status_indicator.setToolTip("온라인")
        else:
            self.status_indicator.setText("○")
            self.status_indicator.setObjectName("status_offline")
            self.status_indicator.setToolTip("오프라인")
        self.status_indicator.setStyle(self.status_indicator.style())


class RPIPXEManagerGUI(QMainWindow):
    def __init__(self):
        super().__init__()

        self.config_file = Path.home() / '.rpi_pxe_config.json'
        self.project_dir = Path(__file__).parent.resolve()
        self.clients_backup_file = self.project_dir / 'clients_backup.json'
        self.config = self.load_config()
        self.client_cards = {}
        self.client_status = {}
        self.ping_thread = None

        self.init_ui()
        self.start_status_thread()

    def load_config(self) -> dict:
        config = {
            'server_ip': '192.168.0.10',
            'dhcp_range_start': '192.168.0.100',
            'dhcp_range_end': '192.168.0.200',
            'network_interface': 'eth0',
            'nfs_root': '/media/polygom3d/rpi-client',
            'tftp_root': '/tftpboot',
            'clients': []
        }

        if self.config_file.exists():
            try:
                with open(self.config_file, 'r') as f:
                    saved = json.load(f)
                config.update(saved)
            except:
                pass

        config['clients'] = self.parse_clients_from_dnsmasq()
        return config

    def parse_clients_from_dnsmasq(self) -> List[dict]:
        clients = []
        dnsmasq_conf = Path('/etc/dnsmasq.conf')

        if not dnsmasq_conf.exists():
            return clients

        try:
            with open(dnsmasq_conf, 'r') as f:
                content = f.read()

            pattern = r'dhcp-host=([0-9a-fA-F:]+),([0-9.]+),([^,\n]+)'
            matches = re.findall(pattern, content)

            for mac, ip, hostname in matches:
                clients.append({
                    'serial': hostname,
                    'hostname': hostname,
                    'mac': mac.lower(),
                    'ip': ip,
                    'boot_mode': 'nfs'
                })
        except Exception as e:
            print(f"dnsmasq.conf 읽기 오류: {e}")

        return clients

    def save_config(self):
        try:
            with open(self.config_file, 'w') as f:
                json.dump(self.config, f, indent=2)
        except Exception as e:
            print(f"설정 저장 실패: {e}")

    def init_ui(self):
        self.setWindowTitle("RPI PXE Manager")
        self.setGeometry(100, 100, 1400, 900)
        self.setMinimumSize(1200, 700)

        self.set_dark_theme()

        main_widget = QWidget()
        self.setCentralWidget(main_widget)

        main_layout = QHBoxLayout(main_widget)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)

        sidebar = self.create_sidebar()
        main_layout.addWidget(sidebar)

        self.content_stack = QStackedWidget()
        main_layout.addWidget(self.content_stack, 1)

        self.create_pages()
        self.show_dashboard()

    def set_dark_theme(self):
        self.setStyleSheet("""
            QMainWindow, QWidget {
                background-color: #0d1117;
                color: #c9d1d9;
                font-family: 'NanumGothic', 'Malgun Gothic', sans-serif;
                font-size: 13px;
            }

            QFrame#sidebar {
                background-color: #161b22;
                border-right: 1px solid #30363d;
            }

            QPushButton {
                background-color: #21262d;
                border: 1px solid #30363d;
                padding: 10px 16px;
                border-radius: 6px;
                color: #c9d1d9;
                font-weight: 500;
            }
            QPushButton:hover {
                background-color: #30363d;
                border-color: #8b949e;
            }
            QPushButton:pressed {
                background-color: #484f58;
            }

            QPushButton#sidebar_btn {
                background-color: transparent;
                border: none;
                text-align: left;
                padding: 12px 20px;
                border-radius: 0;
                border-left: 3px solid transparent;
                font-size: 14px;
            }
            QPushButton#sidebar_btn:hover {
                background-color: #21262d;
            }
            QPushButton#sidebar_btn:checked {
                background-color: #1f6feb20;
                border-left: 3px solid #58a6ff;
                color: #58a6ff;
            }

            QPushButton#primary_btn {
                background-color: #238636;
                border-color: #238636;
                color: white;
            }
            QPushButton#primary_btn:hover {
                background-color: #2ea043;
            }

            QPushButton#danger_btn {
                background-color: #da3633;
                border-color: #da3633;
                color: white;
            }
            QPushButton#danger_btn:hover {
                background-color: #f85149;
            }

            QLabel#title {
                font-size: 22px;
                font-weight: bold;
                color: #58a6ff;
            }
            QLabel#section_title {
                font-size: 18px;
                font-weight: bold;
                color: #c9d1d9;
                padding: 5px 0;
            }
            QLabel#subtitle {
                font-size: 13px;
                color: #8b949e;
            }

            QFrame#client_card {
                background-color: #161b22;
                border: 1px solid #30363d;
                border-radius: 8px;
            }
            QFrame#client_card:hover {
                border-color: #58a6ff;
            }

            QLabel#card_num {
                font-size: 14px;
                font-weight: bold;
                color: #8b949e;
                background-color: #21262d;
                border-radius: 4px;
                padding: 4px;
            }
            QLabel#card_hostname {
                font-size: 15px;
                font-weight: bold;
                color: #c9d1d9;
            }
            QLabel#card_detail {
                font-size: 13px;
                color: #c9d1d9;
                font-family: 'D2Coding', 'Consolas', 'Monaco', monospace;
            }

            QLabel#status_online {
                color: #58a6ff;
                font-size: 14px;
                font-weight: bold;
            }
            QLabel#status_offline {
                color: #f0883e;
                font-size: 14px;
            }
            QLabel#status_pending {
                color: #8b949e;
                font-size: 14px;
            }

            QPushButton#card_btn {
                background-color: #21262d;
                border: 1px solid #30363d;
                padding: 2px 6px;
                font-size: 11px;
            }
            QPushButton#card_btn_danger {
                background-color: #21262d;
                border: 1px solid #da3633;
                color: #f85149;
                padding: 2px 6px;
                font-size: 11px;
            }
            QPushButton#card_btn_danger:hover {
                background-color: #da3633;
                color: white;
            }

            QGroupBox {
                border: 1px solid #30363d;
                border-radius: 8px;
                margin-top: 12px;
                padding: 15px;
                font-weight: bold;
                background-color: #161b22;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 15px;
                padding: 0 8px;
                color: #c9d1d9;
            }

            QLineEdit, QComboBox, QTextEdit {
                background-color: #0d1117;
                border: 1px solid #30363d;
                border-radius: 6px;
                padding: 10px;
                color: #c9d1d9;
            }
            QLineEdit:focus, QComboBox:focus {
                border-color: #58a6ff;
            }

            QProgressBar {
                border: none;
                border-radius: 4px;
                background-color: #21262d;
                text-align: center;
                height: 8px;
            }
            QProgressBar::chunk {
                border-radius: 4px;
                background-color: #58a6ff;
            }

            QScrollArea {
                border: none;
                background-color: transparent;
            }
            QScrollBar:vertical {
                background-color: #0d1117;
                width: 10px;
                border-radius: 5px;
            }
            QScrollBar::handle:vertical {
                background-color: #30363d;
                border-radius: 5px;
                min-height: 20px;
            }
            QScrollBar::handle:vertical:hover {
                background-color: #484f58;
            }
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
                height: 0;
            }

            QFrame#stat_card {
                background-color: #161b22;
                border: 1px solid #30363d;
                border-radius: 8px;
                padding: 15px;
            }
            QLabel#stat_value {
                font-size: 28px;
                font-weight: bold;
                color: #58a6ff;
            }
            QLabel#stat_label {
                font-size: 13px;
                color: #8b949e;
            }
        """)

    def create_sidebar(self) -> QFrame:
        sidebar = QFrame()
        sidebar.setObjectName("sidebar")
        sidebar.setFixedWidth(220)

        layout = QVBoxLayout(sidebar)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        # 헤더
        header = QFrame()
        header_layout = QVBoxLayout(header)
        header_layout.setContentsMargins(20, 25, 20, 25)

        title = QLabel("RPI PXE Manager")
        title.setObjectName("title")
        header_layout.addWidget(title)

        version = QLabel("v2.7")
        version.setObjectName("subtitle")
        header_layout.addWidget(version)

        layout.addWidget(header)

        # 메뉴
        self.sidebar_buttons = []
        menu_items = [
            ("대시보드", self.show_dashboard),
            ("클라이언트 관리", self.show_clients),
            ("서버 설정", self.show_settings),
            ("서비스 관리", self.show_services),
            ("로그 확인", self.show_logs),
            ("초기 설정", self.show_setup),
        ]

        for text, callback in menu_items:
            btn = QPushButton(text)
            btn.setObjectName("sidebar_btn")
            btn.setCheckable(True)
            btn.clicked.connect(callback)
            layout.addWidget(btn)
            self.sidebar_buttons.append(btn)

        layout.addStretch()

        # 종료 버튼
        exit_btn = QPushButton("종료")
        exit_btn.setObjectName("danger_btn")
        exit_btn.clicked.connect(self.close)
        exit_btn.setFixedHeight(40)
        layout.addWidget(exit_btn)

        return sidebar

    def set_active_button(self, index: int):
        for i, btn in enumerate(self.sidebar_buttons):
            btn.setChecked(i == index)

    def create_pages(self):
        self.dashboard_page = self.create_dashboard_page()
        self.content_stack.addWidget(self.dashboard_page)

        self.clients_page = self.create_clients_page()
        self.content_stack.addWidget(self.clients_page)

        self.settings_page = self.create_settings_page()
        self.content_stack.addWidget(self.settings_page)

        self.services_page = self.create_services_page()
        self.content_stack.addWidget(self.services_page)

        self.logs_page = self.create_logs_page()
        self.content_stack.addWidget(self.logs_page)

        self.setup_page = self.create_setup_page()
        self.content_stack.addWidget(self.setup_page)

    def create_stat_card(self, title: str, value: str, color: str = "#58a6ff") -> QFrame:
        card = QFrame()
        card.setObjectName("stat_card")
        card.setFixedHeight(100)

        layout = QVBoxLayout(card)
        layout.setContentsMargins(20, 15, 20, 15)

        value_label = QLabel(value)
        value_label.setObjectName("stat_value")
        value_label.setStyleSheet(f"color: {color};")
        layout.addWidget(value_label)

        title_label = QLabel(title)
        title_label.setObjectName("stat_label")
        layout.addWidget(title_label)

        return card

    def create_dashboard_page(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(30, 30, 30, 30)
        layout.setSpacing(20)

        # 헤더
        header = QLabel("대시보드")
        header.setObjectName("section_title")
        layout.addWidget(header)

        # 통계 카드
        stats_layout = QHBoxLayout()
        stats_layout.setSpacing(15)

        self.cpu_card = self.create_stat_card("CPU 사용률", "0%")
        stats_layout.addWidget(self.cpu_card)

        self.mem_card = self.create_stat_card("메모리 사용률", "0%", "#3fb950")
        stats_layout.addWidget(self.mem_card)

        self.disk_card = self.create_stat_card("디스크 사용률", "0%", "#f0883e")
        stats_layout.addWidget(self.disk_card)

        client_count = len(self.config.get('clients', []))
        self.client_card_stat = self.create_stat_card("등록된 클라이언트", str(client_count), "#a371f7")
        stats_layout.addWidget(self.client_card_stat)

        layout.addLayout(stats_layout)

        # 하단 정보
        info_layout = QHBoxLayout()
        info_layout.setSpacing(15)

        # 네트워크 정보
        network_group = QGroupBox("네트워크 정보")
        network_layout = QFormLayout(network_group)
        network_layout.setSpacing(10)

        self.net_interface_label = QLabel(self.config.get('network_interface', 'N/A'))
        self.net_ip_label = QLabel(self.config.get('server_ip', 'N/A'))
        self.nfs_label = QLabel(self.config.get('nfs_root', 'N/A'))

        network_layout.addRow("인터페이스:", self.net_interface_label)
        network_layout.addRow("서버 IP:", self.net_ip_label)
        network_layout.addRow("NFS 경로:", self.nfs_label)

        info_layout.addWidget(network_group)

        # 서비스 상태
        service_group = QGroupBox("서비스 상태")
        service_layout = QVBoxLayout(service_group)
        service_layout.setSpacing(8)

        self.service_labels = {}
        for service in ['dnsmasq', 'nfs-kernel-server']:
            h_layout = QHBoxLayout()
            name_label = QLabel(service)
            status_label = QLabel("확인 중...")
            status_label.setAlignment(Qt.AlignRight)
            h_layout.addWidget(name_label)
            h_layout.addWidget(status_label)
            service_layout.addLayout(h_layout)
            self.service_labels[service] = status_label

        info_layout.addWidget(service_group)

        layout.addLayout(info_layout)
        layout.addStretch()

        return page

    def create_clients_page(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(30, 30, 30, 30)
        layout.setSpacing(15)

        # 헤더
        header_layout = QHBoxLayout()

        title_layout = QVBoxLayout()
        title = QLabel("클라이언트 관리")
        title.setObjectName("section_title")
        title_layout.addWidget(title)

        self.client_count_label = QLabel(f"총 {len(self.config.get('clients', []))}개 등록됨")
        self.client_count_label.setObjectName("subtitle")
        title_layout.addWidget(self.client_count_label)

        header_layout.addLayout(title_layout)
        header_layout.addStretch()

        # 정렬 옵션
        sort_label = QLabel("정렬:")
        sort_label.setObjectName("subtitle")
        header_layout.addWidget(sort_label)

        self.sort_combo = QComboBox()
        self.sort_combo.addItems(["IP 순", "호스트명 순", "온라인 우선", "오프라인 우선"])
        self.sort_combo.setFixedWidth(120)
        self.sort_combo.currentTextChanged.connect(self.sort_clients)
        header_layout.addWidget(self.sort_combo)

        # 버튼들
        add_btn = QPushButton("+ 추가")
        add_btn.setObjectName("primary_btn")
        add_btn.clicked.connect(self.add_client)
        header_layout.addWidget(add_btn)

        refresh_btn = QPushButton("새로고침")
        refresh_btn.clicked.connect(self.refresh_clients)
        header_layout.addWidget(refresh_btn)

        ping_btn = QPushButton("상태 확인")
        ping_btn.clicked.connect(self.check_all_clients_status)
        header_layout.addWidget(ping_btn)

        backup_btn = QPushButton("백업/복원")
        backup_btn.clicked.connect(self.show_backup_dialog)
        header_layout.addWidget(backup_btn)

        layout.addLayout(header_layout)

        # 열 헤더
        col_header = QFrame()
        col_header.setStyleSheet("background-color: #161b22; border-radius: 4px; padding: 5px;")
        col_header_layout = QHBoxLayout(col_header)
        col_header_layout.setContentsMargins(12, 8, 12, 8)
        col_header_layout.setSpacing(10)

        headers = [
            ("", 16),
            ("#", 28),
            ("호스트명", 120),
            ("IP 주소", 110),
            ("MAC 주소", 0),
            ("", 120)
        ]
        for text, width in headers:
            lbl = QLabel(text)
            lbl.setStyleSheet("color: #8b949e; font-weight: bold; font-size: 12px;")
            if width > 0:
                lbl.setFixedWidth(width)
            else:
                col_header_layout.addWidget(lbl, 1)
                continue
            col_header_layout.addWidget(lbl)

        layout.addWidget(col_header)

        # 클라이언트 리스트 (스크롤)
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)

        self.clients_container = QWidget()
        self.clients_layout = QVBoxLayout(self.clients_container)
        self.clients_layout.setContentsMargins(0, 0, 10, 0)
        self.clients_layout.setSpacing(6)
        self.clients_layout.addStretch()

        scroll.setWidget(self.clients_container)
        layout.addWidget(scroll)

        self.refresh_clients()

        return page

    def create_settings_page(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(30, 30, 30, 30)
        layout.setSpacing(20)

        title = QLabel("서버 설정")
        title.setObjectName("section_title")
        layout.addWidget(title)

        form_group = QGroupBox("네트워크 설정")
        form_layout = QFormLayout(form_group)
        form_layout.setSpacing(15)

        self.server_ip_edit = QLineEdit(self.config.get('server_ip', ''))
        form_layout.addRow("서버 IP:", self.server_ip_edit)

        self.interface_edit = QLineEdit(self.config.get('network_interface', ''))
        form_layout.addRow("네트워크 인터페이스:", self.interface_edit)

        self.nfs_root_edit = QLineEdit(self.config.get('nfs_root', ''))
        form_layout.addRow("NFS 루트:", self.nfs_root_edit)

        self.tftp_root_edit = QLineEdit(self.config.get('tftp_root', ''))
        form_layout.addRow("TFTP 루트:", self.tftp_root_edit)

        layout.addWidget(form_group)

        save_btn = QPushButton("설정 저장")
        save_btn.setObjectName("primary_btn")
        save_btn.setFixedWidth(150)
        save_btn.clicked.connect(self.save_settings)
        layout.addWidget(save_btn)

        layout.addStretch()

        return page

    def create_services_page(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(30, 30, 30, 30)
        layout.setSpacing(20)

        title = QLabel("서비스 관리")
        title.setObjectName("section_title")
        layout.addWidget(title)

        services = [
            ('dnsmasq', 'DHCP/DNS/TFTP/PXE 서버'),
            ('nfs-kernel-server', 'NFS 파일 공유 서버'),
        ]

        self.service_status_labels = {}

        for service_name, description in services:
            group = QGroupBox(f"{service_name}")
            group_layout = QHBoxLayout(group)

            desc_label = QLabel(description)
            desc_label.setObjectName("subtitle")
            group_layout.addWidget(desc_label)

            group_layout.addStretch()

            status_label = QLabel("확인 중...")
            self.service_status_labels[service_name] = status_label
            group_layout.addWidget(status_label)

            start_btn = QPushButton("시작")
            start_btn.setObjectName("primary_btn")
            start_btn.setFixedWidth(80)
            start_btn.clicked.connect(lambda checked, s=service_name: self.control_service(s, 'start'))
            group_layout.addWidget(start_btn)

            stop_btn = QPushButton("중지")
            stop_btn.setFixedWidth(80)
            stop_btn.clicked.connect(lambda checked, s=service_name: self.control_service(s, 'stop'))
            group_layout.addWidget(stop_btn)

            restart_btn = QPushButton("재시작")
            restart_btn.setFixedWidth(80)
            restart_btn.clicked.connect(lambda checked, s=service_name: self.control_service(s, 'restart'))
            group_layout.addWidget(restart_btn)

            layout.addWidget(group)

        layout.addStretch()

        return page

    def create_logs_page(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(30, 30, 30, 30)
        layout.setSpacing(15)

        title = QLabel("로그 확인")
        title.setObjectName("section_title")
        layout.addWidget(title)

        select_layout = QHBoxLayout()
        select_layout.addWidget(QLabel("서비스:"))

        self.log_service_combo = QComboBox()
        self.log_service_combo.addItems(['dnsmasq', 'nfs-kernel-server'])
        self.log_service_combo.setFixedWidth(200)
        self.log_service_combo.currentTextChanged.connect(self.load_log)
        select_layout.addWidget(self.log_service_combo)

        refresh_log_btn = QPushButton("새로고침")
        refresh_log_btn.clicked.connect(lambda: self.load_log(self.log_service_combo.currentText()))
        select_layout.addWidget(refresh_log_btn)

        select_layout.addStretch()
        layout.addLayout(select_layout)

        self.log_text = QTextEdit()
        self.log_text.setReadOnly(True)
        self.log_text.setStyleSheet("font-family: 'D2Coding', 'Consolas', monospace; font-size: 12px;")
        layout.addWidget(self.log_text)

        return page

    def create_setup_page(self) -> QWidget:
        page = QWidget()
        layout = QVBoxLayout(page)
        layout.setContentsMargins(30, 30, 30, 30)
        layout.setSpacing(20)

        title = QLabel("초기 설정 / 마이그레이션")
        title.setObjectName("section_title")
        layout.addWidget(title)

        # NFS 설정 섹션
        nfs_group = QGroupBox("NFS 설정 관리")
        nfs_layout = QVBoxLayout(nfs_group)

        nfs_info = QLabel(
            "등록된 클라이언트 정보를 기반으로 NFS exports와 cmdline.txt를 설정합니다."
        )
        nfs_info.setWordWrap(True)
        nfs_info.setObjectName("subtitle")
        nfs_layout.addWidget(nfs_info)

        # 현재 설정 표시
        form_layout = QFormLayout()
        form_layout.setSpacing(10)

        self.current_nfs_label = QLabel(self.config.get('nfs_root', '/media/polygom3d/rpi-client'))
        self.current_nfs_label.setStyleSheet("color: #58a6ff; font-weight: bold;")
        form_layout.addRow("현재 NFS 경로:", self.current_nfs_label)

        self.client_count_setup_label = QLabel(str(len(self.config.get('clients', []))))
        self.client_count_setup_label.setStyleSheet("color: #58a6ff; font-weight: bold;")
        form_layout.addRow("등록된 클라이언트:", self.client_count_setup_label)

        nfs_layout.addLayout(form_layout)

        # 버튼들
        btn_layout = QHBoxLayout()

        gen_exports_btn = QPushButton("exports 생성/적용")
        gen_exports_btn.setObjectName("primary_btn")
        gen_exports_btn.clicked.connect(self.generate_exports)
        btn_layout.addWidget(gen_exports_btn)

        update_cmdline_btn = QPushButton("cmdline.txt 경로 수정")
        update_cmdline_btn.setObjectName("primary_btn")
        update_cmdline_btn.clicked.connect(self.show_cmdline_update_dialog)
        btn_layout.addWidget(update_cmdline_btn)

        nfs_layout.addLayout(btn_layout)

        layout.addWidget(nfs_group)

        # 기존 초기 설정 섹션
        info_group = QGroupBox("CLI 초기 설정")
        info_layout = QVBoxLayout(info_group)

        info_text = QLabel(
            "CLI에서 './pxe' 실행 후 메뉴 6번 '초기 설정 마법사'를 이용하세요."
        )
        info_text.setWordWrap(True)
        info_layout.addWidget(info_text)

        run_setup_btn = QPushButton("터미널에서 초기 설정 실행")
        run_setup_btn.clicked.connect(self.run_setup_wizard)
        info_layout.addWidget(run_setup_btn)

        layout.addWidget(info_group)

        # 로그 출력
        self.setup_log = QTextEdit()
        self.setup_log.setReadOnly(True)
        self.setup_log.setMinimumHeight(200)
        layout.addWidget(self.setup_log)

        return page

    # ========== 페이지 표시 ==========

    def show_dashboard(self):
        self.content_stack.setCurrentWidget(self.dashboard_page)
        self.set_active_button(0)
        self.update_dashboard()

    def show_clients(self):
        self.content_stack.setCurrentWidget(self.clients_page)
        self.set_active_button(1)

    def show_settings(self):
        self.content_stack.setCurrentWidget(self.settings_page)
        self.set_active_button(2)

    def show_services(self):
        self.content_stack.setCurrentWidget(self.services_page)
        self.set_active_button(3)
        self.update_service_status()

    def show_logs(self):
        self.content_stack.setCurrentWidget(self.logs_page)
        self.set_active_button(4)
        self.load_log(self.log_service_combo.currentText())

    def show_setup(self):
        self.content_stack.setCurrentWidget(self.setup_page)
        self.set_active_button(5)

    # ========== 기능 ==========

    def start_status_thread(self):
        self.status_thread = StatusUpdateThread()
        self.status_thread.status_updated.connect(self.on_status_updated)
        self.status_thread.start()

    def on_status_updated(self, status: dict):
        cpu_val = self.cpu_card.findChild(QLabel, "stat_value")
        if cpu_val:
            cpu_val.setText(f"{status['cpu']:.0f}%")

        mem_val = self.mem_card.findChild(QLabel, "stat_value")
        if mem_val:
            mem_val.setText(f"{status['memory']:.0f}%")

        disk_val = self.disk_card.findChild(QLabel, "stat_value")
        if disk_val:
            disk_val.setText(f"{status['disk']:.0f}%")

    def update_dashboard(self):
        self.net_interface_label.setText(self.config.get('network_interface', 'N/A'))
        self.net_ip_label.setText(self.config.get('server_ip', 'N/A'))
        self.nfs_label.setText(self.config.get('nfs_root', 'N/A'))

        client_val = self.client_card_stat.findChild(QLabel, "stat_value")
        if client_val:
            client_val.setText(str(len(self.config.get('clients', []))))

        self.update_service_status()

    def update_service_status(self):
        for service, label in self.service_labels.items():
            try:
                result = subprocess.run(['systemctl', 'is-active', service],
                                       capture_output=True, text=True, timeout=5)
                if result.stdout.strip() == 'active':
                    label.setStyleSheet("color: #3fb950; font-weight: bold;")
                    label.setText("● 실행 중")
                else:
                    label.setStyleSheet("color: #f85149; font-weight: bold;")
                    label.setText("● 중지됨")
            except:
                label.setStyleSheet("color: #8b949e;")
                label.setText("● 알 수 없음")

        for service, label in self.service_status_labels.items():
            try:
                result = subprocess.run(['systemctl', 'is-active', service],
                                       capture_output=True, text=True, timeout=5)
                if result.stdout.strip() == 'active':
                    label.setStyleSheet("color: #3fb950; font-weight: bold;")
                    label.setText("실행 중")
                else:
                    label.setStyleSheet("color: #f85149; font-weight: bold;")
                    label.setText("중지됨")
            except:
                label.setStyleSheet("color: #8b949e;")
                label.setText("알 수 없음")

    def refresh_clients(self, keep_status=False):
        print("[클라이언트] 목록 새로고침")
        self.config['clients'] = self.parse_clients_from_dnsmasq()

        # 기존 상태 저장
        if keep_status:
            for ip, card in self.client_cards.items():
                if card.is_online is not None:
                    self.client_status[ip] = card.is_online

        # 정렬
        clients = self.get_sorted_clients()

        # 기존 카드 제거
        while self.clients_layout.count() > 1:
            item = self.clients_layout.takeAt(0)
            if item.widget():
                item.widget().deleteLater()

        self.client_cards.clear()

        for i, client in enumerate(clients):
            card = ClientCard(client, i + 1)
            card.detail_clicked.connect(self.show_client_detail)
            card.edit_clicked.connect(self.edit_client)
            card.delete_clicked.connect(self.delete_client)
            self.clients_layout.insertWidget(i, card)
            ip = client.get('ip', '')
            self.client_cards[ip] = card

            # 기존 상태 복원
            if ip in self.client_status:
                card.set_status(self.client_status[ip])

        self.client_count_label.setText(f"총 {len(clients)}개 등록됨")

        # 상태 체크 (keep_status가 아닐 때만)
        if not keep_status:
            self.check_all_clients_status()

    def get_sorted_clients(self) -> list:
        clients = self.config.get('clients', [])
        sort_option = self.sort_combo.currentText() if hasattr(self, 'sort_combo') else "IP 순"

        if sort_option == "IP 순":
            return sorted(clients, key=lambda c: self.ip_to_number(c.get('ip', '0.0.0.0')))
        elif sort_option == "호스트명 순":
            return sorted(clients, key=lambda c: c.get('hostname', '').lower())
        elif sort_option == "온라인 우선":
            return sorted(clients, key=lambda c: (
                0 if self.client_status.get(c.get('ip', '')) == True else 1,
                self.ip_to_number(c.get('ip', '0.0.0.0'))
            ))
        elif sort_option == "오프라인 우선":
            return sorted(clients, key=lambda c: (
                0 if self.client_status.get(c.get('ip', '')) == False else 1,
                self.ip_to_number(c.get('ip', '0.0.0.0'))
            ))
        return clients

    def sort_clients(self):
        self.refresh_clients(keep_status=True)

    def check_all_clients_status(self):
        print(f"[상태] 클라이언트 상태 확인 시작 ({len(self.config.get('clients', []))}개)")
        if self.ping_thread and self.ping_thread.isRunning():
            self.ping_thread.stop()
            self.ping_thread.wait()

        clients = self.config.get('clients', [])
        if not clients:
            return

        self.ping_thread = PingThread(clients)
        self.ping_thread.result_ready.connect(self.on_ping_result)
        self.ping_thread.start()

    def on_ping_result(self, ip: str, is_online: bool):
        self.client_status[ip] = is_online
        if ip in self.client_cards:
            self.client_cards[ip].set_status(is_online)

    def ip_to_number(self, ip: str) -> int:
        try:
            parts = ip.split('.')
            return int(parts[0]) * 256**3 + int(parts[1]) * 256**2 + int(parts[2]) * 256 + int(parts[3])
        except:
            return 0

    def add_client(self):
        dialog = QDialog(self)
        dialog.setWindowTitle("새 클라이언트 추가")
        dialog.setMinimumWidth(400)
        dialog.setStyleSheet(self.styleSheet())

        layout = QFormLayout(dialog)
        layout.setSpacing(15)

        serial_edit = QLineEdit()
        serial_edit.setPlaceholderText("8자리 시리얼 번호")
        layout.addRow("시리얼:", serial_edit)

        mac_edit = QLineEdit()
        mac_edit.setPlaceholderText("aa:bb:cc:dd:ee:ff")
        layout.addRow("MAC 주소:", mac_edit)

        ip_edit = QLineEdit()
        ip_edit.setPlaceholderText("자동 할당시 비워두세요")
        layout.addRow("IP 주소:", ip_edit)

        btn_layout = QHBoxLayout()
        ok_btn = QPushButton("추가")
        ok_btn.setObjectName("primary_btn")
        ok_btn.clicked.connect(dialog.accept)

        cancel_btn = QPushButton("취소")
        cancel_btn.clicked.connect(dialog.reject)

        btn_layout.addWidget(cancel_btn)
        btn_layout.addWidget(ok_btn)
        layout.addRow(btn_layout)

        if dialog.exec_() == QDialog.Accepted:
            serial = serial_edit.text().strip()
            mac = mac_edit.text().strip()
            ip = ip_edit.text().strip()

            if not serial or not mac:
                QMessageBox.warning(self, "오류", "시리얼과 MAC 주소는 필수입니다.")
                return

            if not ip:
                ip = self.get_next_ip()

            QMessageBox.information(self, "알림",
                f"클라이언트 추가:\n시리얼: {serial}\nMAC: {mac}\nIP: {ip}\n\n"
                "CLI에서 './pxe' 실행 후 클라이언트 추가 메뉴를 이용하세요.")

    def get_next_ip(self) -> str:
        used_ips = [c.get('ip', '') for c in self.config.get('clients', [])]
        base = '.'.join(self.config.get('server_ip', '192.168.0.10').split('.')[:3])

        for i in range(100, 200):
            ip = f"{base}.{i}"
            if ip not in used_ips:
                return ip
        return f"{base}.100"

    def show_client_detail(self, client: dict):
        """클라이언트 상세 정보 다이얼로그"""
        hostname = client.get('hostname', client.get('serial', 'N/A'))
        ip = client.get('ip', '')
        print(f"[상세] 클라이언트 상세 보기: {hostname} ({ip})")

        dialog = QDialog(self)
        dialog.setWindowTitle(f"클라이언트 상세 - {hostname}")
        dialog.setMinimumSize(600, 500)
        dialog.setStyleSheet(self.styleSheet())

        layout = QVBoxLayout(dialog)
        layout.setSpacing(15)

        ip = client.get('ip', '')
        serial = client.get('serial', hostname)
        is_online = self.client_status.get(ip, False)

        # 기본 정보
        info_group = QGroupBox("기본 정보")
        info_layout = QFormLayout(info_group)
        info_layout.setSpacing(8)

        info_layout.addRow("시리얼:", QLabel(serial))
        info_layout.addRow("호스트명:", QLabel(hostname))
        info_layout.addRow("IP 주소:", QLabel(ip))
        info_layout.addRow("MAC 주소:", QLabel(client.get('mac', 'N/A')))

        status_label = QLabel("● 온라인" if is_online else "○ 오프라인")
        status_label.setStyleSheet(f"color: {'#3fb950' if is_online else '#f85149'}; font-weight: bold;")
        info_layout.addRow("상태:", status_label)

        layout.addWidget(info_group)

        # 파일 시스템 정보
        fs_group = QGroupBox("파일 시스템")
        fs_layout = QFormLayout(fs_group)
        fs_layout.setSpacing(8)

        tftp_root = self.config.get('tftp_root', '/tftpboot')
        nfs_root = self.config.get('nfs_root', '/media/polygom3d/rpi-client')

        tftp_path = f"{tftp_root}/{serial}"
        nfs_path = f"{nfs_root}/{serial}"

        tftp_exists = Path(tftp_path).exists()
        nfs_exists = Path(nfs_path).exists()

        tftp_label = QLabel(f"{'✓ 존재' if tftp_exists else '✗ 없음'} ({tftp_path})")
        tftp_label.setStyleSheet(f"color: {'#3fb950' if tftp_exists else '#f85149'};")
        fs_layout.addRow("TFTP:", tftp_label)

        nfs_label = QLabel(f"{'✓ 존재' if nfs_exists else '✗ 없음'} ({nfs_path})")
        nfs_label.setStyleSheet(f"color: {'#3fb950' if nfs_exists else '#f85149'};")
        fs_layout.addRow("NFS:", nfs_label)

        # cmdline.txt 내용
        cmdline_path = f"{tftp_path}/cmdline.txt"
        if Path(cmdline_path).exists():
            try:
                with open(cmdline_path, 'r') as f:
                    cmdline_content = f.read().strip()[:100] + "..."
            except:
                cmdline_content = "읽기 실패"
        else:
            cmdline_content = "파일 없음"
        fs_layout.addRow("cmdline:", QLabel(cmdline_content))

        layout.addWidget(fs_group)

        # 온라인일 경우 시스템 정보 표시
        if is_online:
            sys_group = QGroupBox("시스템 정보 (SSH)")
            sys_layout = QVBoxLayout(sys_group)

            self.sys_info_text = QTextEdit()
            self.sys_info_text.setReadOnly(True)
            self.sys_info_text.setMaximumHeight(200)
            self.sys_info_text.setPlainText("정보 수집 중...")
            sys_layout.addWidget(self.sys_info_text)

            refresh_btn = QPushButton("정보 새로고침")
            refresh_btn.clicked.connect(lambda: self.fetch_client_system_info(ip))
            sys_layout.addWidget(refresh_btn)

            layout.addWidget(sys_group)

            # 자동으로 정보 수집
            QTimer.singleShot(100, lambda: self.fetch_client_system_info(ip))

            # 관리 버튼
            manage_layout = QHBoxLayout()

            reboot_btn = QPushButton("재부팅")
            reboot_btn.clicked.connect(lambda: self.reboot_client(client))
            manage_layout.addWidget(reboot_btn)

            shutdown_btn = QPushButton("종료")
            shutdown_btn.setObjectName("danger_btn")
            shutdown_btn.clicked.connect(lambda: self.shutdown_client(client))
            manage_layout.addWidget(shutdown_btn)

            ssh_btn = QPushButton("SSH 터미널")
            ssh_btn.clicked.connect(lambda: self.open_ssh_terminal(client))
            manage_layout.addWidget(ssh_btn)

            layout.addLayout(manage_layout)
        else:
            offline_label = QLabel("클라이언트가 오프라인 상태입니다.\n시스템 정보를 수집할 수 없습니다.")
            offline_label.setStyleSheet("color: #8b949e; padding: 20px;")
            offline_label.setAlignment(Qt.AlignCenter)
            layout.addWidget(offline_label)

        # 닫기 버튼
        close_btn = QPushButton("닫기")
        close_btn.clicked.connect(dialog.close)
        layout.addWidget(close_btn)

        dialog.exec_()

    def fetch_client_system_info(self, ip: str):
        """SSH로 클라이언트 시스템 정보 수집"""
        print(f"[SSH] 시스템 정보 수집 중: {ip}")
        try:
            # 여러 명령어를 한번에 실행
            commands = [
                "echo '=== 시스템 정보 ==='",
                "uname -a",
                "echo ''",
                "echo '=== 업타임 ==='",
                "uptime",
                "echo ''",
                "echo '=== CPU 정보 ==='",
                "cat /proc/cpuinfo | grep -E '^(model name|Hardware|Revision)' | head -3",
                "echo ''",
                "echo '=== 메모리 ==='",
                "free -h | head -2",
                "echo ''",
                "echo '=== 디스크 ==='",
                "df -h / | tail -1",
                "echo ''",
                "echo '=== 온도 ==='",
                "vcgencmd measure_temp 2>/dev/null || echo 'N/A'",
                "echo ''",
                "echo '=== IP 주소 ==='",
                "hostname -I"
            ]

            cmd = "; ".join(commands)
            result = subprocess.run(
                ['sshpass', '-p', 'raspberry', 'ssh',
                 '-o', 'StrictHostKeyChecking=no', '-o', 'ConnectTimeout=5',
                 f'pi@{ip}', cmd],
                capture_output=True, text=True, timeout=15
            )

            if result.returncode == 0:
                self.sys_info_text.setPlainText(result.stdout)
            else:
                self.sys_info_text.setPlainText(f"오류: {result.stderr}")

        except subprocess.TimeoutExpired:
            self.sys_info_text.setPlainText("연결 시간 초과")
        except Exception as e:
            self.sys_info_text.setPlainText(f"오류: {e}")

    def edit_client(self, client: dict):
        """클라이언트 편집 다이얼로그"""
        hostname = client.get('hostname', '')
        ip = client.get('ip', '')
        print(f"[편집] 클라이언트 편집: {hostname} ({ip})")

        dialog = QDialog(self)
        dialog.setWindowTitle(f"클라이언트 편집 - {hostname}")
        dialog.setMinimumWidth(450)
        dialog.setStyleSheet(self.styleSheet())

        layout = QVBoxLayout(dialog)
        layout.setSpacing(15)

        form = QFormLayout()
        form.setSpacing(10)

        serial_edit = QLineEdit(client.get('serial', ''))
        serial_edit.setReadOnly(True)
        serial_edit.setStyleSheet("background-color: #21262d;")
        form.addRow("시리얼:", serial_edit)

        hostname_edit = QLineEdit(client.get('hostname', ''))
        form.addRow("호스트명:", hostname_edit)

        mac_edit = QLineEdit(client.get('mac', ''))
        form.addRow("MAC 주소:", mac_edit)

        ip_edit = QLineEdit(client.get('ip', ''))
        form.addRow("IP 주소:", ip_edit)

        layout.addLayout(form)

        # 온라인 상태면 관리 버튼 추가
        ip = client.get('ip', '')
        if self.client_status.get(ip) == True:
            manage_group = QGroupBox("온라인 클라이언트 관리")
            manage_layout = QHBoxLayout(manage_group)

            reboot_btn = QPushButton("재부팅")
            reboot_btn.clicked.connect(lambda: self.reboot_client(client, dialog))
            manage_layout.addWidget(reboot_btn)

            shutdown_btn = QPushButton("종료")
            shutdown_btn.setObjectName("danger_btn")
            shutdown_btn.clicked.connect(lambda: self.shutdown_client(client, dialog))
            manage_layout.addWidget(shutdown_btn)

            ssh_btn = QPushButton("SSH 터미널")
            ssh_btn.clicked.connect(lambda: self.open_ssh_terminal(client))
            manage_layout.addWidget(ssh_btn)

            layout.addWidget(manage_group)

        # 버튼
        btn_layout = QHBoxLayout()

        save_btn = QPushButton("저장")
        save_btn.setObjectName("primary_btn")
        save_btn.clicked.connect(lambda: self.save_client_edit(
            client, hostname_edit.text(), mac_edit.text(), ip_edit.text(), dialog))
        btn_layout.addWidget(save_btn)

        cancel_btn = QPushButton("취소")
        cancel_btn.clicked.connect(dialog.reject)
        btn_layout.addWidget(cancel_btn)

        layout.addLayout(btn_layout)
        dialog.exec_()

    def save_client_edit(self, client: dict, new_hostname: str, new_mac: str, new_ip: str, dialog: QDialog):
        """클라이언트 편집 저장 - dnsmasq.conf 수정"""
        print(f"[저장] 클라이언트 정보 저장: {new_hostname} ({new_ip})")
        old_mac = client.get('mac', '')
        old_ip = client.get('ip', '')
        old_hostname = client.get('hostname', '')

        new_hostname = new_hostname.strip()
        new_mac = new_mac.strip().lower()
        new_ip = new_ip.strip()

        if not new_hostname or not new_mac or not new_ip:
            QMessageBox.warning(self, "오류", "모든 필드를 입력하세요.")
            return

        # 변경 사항 없으면 종료
        if old_mac == new_mac and old_ip == new_ip and old_hostname == new_hostname:
            dialog.accept()
            return

        try:
            # dnsmasq.conf 읽기
            result = subprocess.run(['sudo', 'cat', '/etc/dnsmasq.conf'],
                                   capture_output=True, text=True, timeout=10)
            content = result.stdout

            # 기존 라인 찾아서 교체
            old_line = f"dhcp-host={old_mac},{old_ip},{old_hostname}"
            new_line = f"dhcp-host={new_mac},{new_ip},{new_hostname}"

            if old_line in content:
                content = content.replace(old_line, new_line)
            else:
                # 다른 형식으로 찾기 시도
                import re
                pattern = rf"dhcp-host={re.escape(old_mac)},[^,\n]+,[^\n]+"
                content = re.sub(pattern, new_line, content)

            # 임시 파일에 저장 후 복사
            temp_file = '/tmp/dnsmasq.conf.tmp'
            with open(temp_file, 'w') as f:
                f.write(content)

            subprocess.run(['sudo', 'cp', temp_file, '/etc/dnsmasq.conf'], check=True, timeout=10)

            # dnsmasq 재시작
            subprocess.run(['sudo', 'systemctl', 'restart', 'dnsmasq'], check=True, timeout=30)

            QMessageBox.information(self, "완료", "클라이언트 정보가 수정되었습니다.")
            dialog.accept()
            self.refresh_clients()

        except Exception as e:
            QMessageBox.warning(self, "오류", f"수정 실패: {e}")

    def delete_client(self, client: dict):
        """클라이언트 삭제"""
        hostname = client.get('hostname', client.get('serial', ''))
        serial = client.get('serial', hostname)
        mac = client.get('mac', '')
        ip = client.get('ip', '')
        print(f"[삭제] 클라이언트 삭제 다이얼로그: {hostname} ({ip})")

        # 삭제 옵션 다이얼로그
        dialog = QDialog(self)
        dialog.setWindowTitle("클라이언트 삭제")
        dialog.setMinimumWidth(400)
        dialog.setStyleSheet(self.styleSheet())

        layout = QVBoxLayout(dialog)
        layout.setSpacing(15)

        info = QLabel(f"클라이언트 '{hostname}'를 삭제합니다.\n\n삭제할 항목을 선택하세요:")
        info.setWordWrap(True)
        layout.addWidget(info)

        chk_dnsmasq = QCheckBox("dnsmasq 설정 (DHCP 예약)")
        chk_dnsmasq.setChecked(True)
        layout.addWidget(chk_dnsmasq)

        chk_exports = QCheckBox("NFS exports 설정")
        chk_exports.setChecked(True)
        layout.addWidget(chk_exports)

        chk_tftpboot = QCheckBox(f"TFTP 부팅 파일 (/tftpboot/{serial})")
        chk_tftpboot.setChecked(False)
        layout.addWidget(chk_tftpboot)

        chk_nfs = QCheckBox(f"NFS 루트 파일시스템 ({self.config.get('nfs_root')}/{serial})")
        chk_nfs.setChecked(False)
        chk_nfs.setStyleSheet("color: #f85149;")
        layout.addWidget(chk_nfs)

        warning = QLabel("⚠️ 파일시스템 삭제는 복구할 수 없습니다!")
        warning.setStyleSheet("color: #f85149; font-weight: bold;")
        layout.addWidget(warning)

        btn_layout = QHBoxLayout()

        delete_btn = QPushButton("삭제")
        delete_btn.setObjectName("danger_btn")
        delete_btn.clicked.connect(lambda: self.execute_delete(
            client, chk_dnsmasq.isChecked(), chk_exports.isChecked(),
            chk_tftpboot.isChecked(), chk_nfs.isChecked(), dialog))
        btn_layout.addWidget(delete_btn)

        cancel_btn = QPushButton("취소")
        cancel_btn.clicked.connect(dialog.reject)
        btn_layout.addWidget(cancel_btn)

        layout.addLayout(btn_layout)
        dialog.exec_()

    def execute_delete(self, client: dict, del_dnsmasq: bool, del_exports: bool,
                       del_tftpboot: bool, del_nfs: bool, dialog: QDialog):
        """실제 삭제 실행"""
        hostname = client.get('hostname', client.get('serial', ''))
        serial = client.get('serial', hostname)
        mac = client.get('mac', '')
        ip = client.get('ip', '')
        nfs_root = self.config.get('nfs_root', '/media/polygom3d/rpi-client')
        tftp_root = self.config.get('tftp_root', '/tftpboot')

        print(f"[삭제] 삭제 실행: {hostname} - dnsmasq={del_dnsmasq}, exports={del_exports}, tftp={del_tftpboot}, nfs={del_nfs}")

        errors = []

        try:
            # 1. dnsmasq.conf에서 제거
            if del_dnsmasq:
                result = subprocess.run(['sudo', 'cat', '/etc/dnsmasq.conf'],
                                       capture_output=True, text=True)
                lines = result.stdout.split('\n')
                new_lines = [l for l in lines if not (mac in l and ip in l)]

                temp_file = '/tmp/dnsmasq.conf.tmp'
                with open(temp_file, 'w') as f:
                    f.write('\n'.join(new_lines))
                subprocess.run(['sudo', 'cp', temp_file, '/etc/dnsmasq.conf'], check=True)
                subprocess.run(['sudo', 'systemctl', 'restart', 'dnsmasq'], timeout=30)

            # 2. /etc/exports에서 제거
            if del_exports:
                result = subprocess.run(['sudo', 'cat', '/etc/exports'],
                                       capture_output=True, text=True)
                lines = result.stdout.split('\n')
                new_lines = [l for l in lines if serial not in l]

                temp_file = '/tmp/exports.tmp'
                with open(temp_file, 'w') as f:
                    f.write('\n'.join(new_lines))
                subprocess.run(['sudo', 'cp', temp_file, '/etc/exports'], check=True)
                subprocess.run(['sudo', 'exportfs', '-ra'], timeout=30)

            # 3. tftpboot 삭제
            if del_tftpboot:
                tftp_path = f"{tftp_root}/{serial}"
                result = subprocess.run(['sudo', 'rm', '-rf', tftp_path], capture_output=True, text=True)
                if result.returncode != 0:
                    errors.append(f"TFTP 삭제 실패: {result.stderr}")

            # 4. NFS 루트 삭제
            if del_nfs:
                nfs_path = f"{nfs_root}/{serial}"
                reply = QMessageBox.warning(self, "최종 확인",
                    f"정말로 {nfs_path}를 삭제하시겠습니까?\n\n이 작업은 복구할 수 없습니다!",
                    QMessageBox.Yes | QMessageBox.No)
                if reply == QMessageBox.Yes:
                    result = subprocess.run(['sudo', 'rm', '-rf', nfs_path], capture_output=True, text=True)
                    if result.returncode != 0:
                        errors.append(f"NFS 삭제 실패: {result.stderr}")

            if errors:
                QMessageBox.warning(self, "경고", "일부 항목 삭제 실패:\n" + '\n'.join(errors))
            else:
                QMessageBox.information(self, "완료", f"클라이언트 '{hostname}'가 삭제되었습니다.")

            dialog.accept()
            self.refresh_clients()

        except Exception as e:
            QMessageBox.warning(self, "오류", f"삭제 실패: {e}")

    def reboot_client(self, client: dict, dialog: QDialog = None):
        """클라이언트 재부팅"""
        ip = client.get('ip', '')
        hostname = client.get('hostname', '')
        print(f"[재부팅] 재부팅 요청: {hostname} ({ip})")

        reply = QMessageBox.question(self, "재부팅 확인",
            f"'{hostname}' ({ip})를 재부팅하시겠습니까?",
            QMessageBox.Yes | QMessageBox.No)

        if reply == QMessageBox.Yes:
            try:
                result = subprocess.run(
                    ['sshpass', '-p', 'raspberry', 'ssh',
                     '-o', 'StrictHostKeyChecking=no', '-o', 'ConnectTimeout=5',
                     f'pi@{ip}', 'sudo reboot'],
                    capture_output=True, text=True, timeout=15
                )
                QMessageBox.information(self, "완료", f"'{hostname}' 재부팅 명령을 전송했습니다.")
            except subprocess.TimeoutExpired:
                QMessageBox.information(self, "완료", f"'{hostname}' 재부팅 명령을 전송했습니다.")
            except Exception as e:
                QMessageBox.warning(self, "오류", f"재부팅 실패: {e}")

    def shutdown_client(self, client: dict, dialog: QDialog = None):
        """클라이언트 종료"""
        ip = client.get('ip', '')
        hostname = client.get('hostname', '')
        print(f"[종료] 종료 요청: {hostname} ({ip})")

        reply = QMessageBox.question(self, "종료 확인",
            f"'{hostname}' ({ip})를 종료하시겠습니까?",
            QMessageBox.Yes | QMessageBox.No)

        if reply == QMessageBox.Yes:
            try:
                result = subprocess.run(
                    ['sshpass', '-p', 'raspberry', 'ssh',
                     '-o', 'StrictHostKeyChecking=no', '-o', 'ConnectTimeout=5',
                     f'pi@{ip}', 'sudo shutdown -h now'],
                    capture_output=True, text=True, timeout=15
                )
                QMessageBox.information(self, "완료", f"'{hostname}' 종료 명령을 전송했습니다.")
            except subprocess.TimeoutExpired:
                QMessageBox.information(self, "완료", f"'{hostname}' 종료 명령을 전송했습니다.")
            except Exception as e:
                QMessageBox.warning(self, "오류", f"종료 실패: {e}")

    def open_ssh_terminal(self, client: dict):
        """SSH 터미널 열기"""
        ip = client.get('ip', '')
        hostname = client.get('hostname', '')
        print(f"[SSH] 터미널 열기: {hostname} ({ip})")
        try:
            # gnome-terminal에서 sshpass 사용
            subprocess.Popen(['gnome-terminal', '--', 'sshpass', '-p', 'raspberry', 'ssh',
                            '-o', 'StrictHostKeyChecking=no', f'pi@{ip}'])
        except FileNotFoundError:
            try:
                subprocess.Popen(['xterm', '-e', f'sshpass -p raspberry ssh -o StrictHostKeyChecking=no pi@{ip}'])
            except FileNotFoundError:
                QMessageBox.warning(self, "오류",
                    f"터미널을 열 수 없습니다.\n\n수동으로 연결하세요:\nsshpass -p raspberry ssh pi@{ip}")

    def show_backup_dialog(self):
        dialog = QDialog(self)
        dialog.setWindowTitle("클라이언트 백업/복원")
        dialog.setMinimumWidth(450)
        dialog.setStyleSheet(self.styleSheet())

        layout = QVBoxLayout(dialog)
        layout.setSpacing(15)

        backup = self.load_clients_backup()
        if backup:
            info = f"백업 날짜: {backup.get('backup_date', 'N/A')}\n"
            info += f"클라이언트 수: {len(backup.get('clients', []))}개"
        else:
            info = "저장된 백업이 없습니다."

        info_label = QLabel(info)
        layout.addWidget(info_label)

        btn_layout = QHBoxLayout()

        save_btn = QPushButton("현재 설정 백업")
        save_btn.setObjectName("primary_btn")
        save_btn.clicked.connect(lambda: self.save_backup(dialog))
        btn_layout.addWidget(save_btn)

        restore_btn = QPushButton("백업에서 복원")
        restore_btn.clicked.connect(lambda: self.restore_backup(dialog))
        btn_layout.addWidget(restore_btn)

        layout.addLayout(btn_layout)

        close_btn = QPushButton("닫기")
        close_btn.clicked.connect(dialog.close)
        layout.addWidget(close_btn)

        dialog.exec_()

    def load_clients_backup(self) -> dict:
        if self.clients_backup_file.exists():
            try:
                with open(self.clients_backup_file, 'r') as f:
                    return json.load(f)
            except:
                pass
        return None

    def save_backup(self, dialog):
        backup_data = {
            'backup_date': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'server_ip': self.config.get('server_ip', ''),
            'nfs_root': self.config.get('nfs_root', ''),
            'clients': self.config.get('clients', [])
        }

        try:
            with open(self.clients_backup_file, 'w') as f:
                json.dump(backup_data, f, indent=2, ensure_ascii=False)
            QMessageBox.information(self, "완료", "백업이 저장되었습니다.")
            dialog.close()
        except Exception as e:
            QMessageBox.warning(self, "오류", f"백업 저장 실패: {e}")

    def restore_backup(self, dialog):
        backup = self.load_clients_backup()
        if not backup:
            QMessageBox.warning(self, "오류", "복원할 백업이 없습니다.")
            return

        reply = QMessageBox.question(self, "확인",
            f"백업에서 {len(backup.get('clients', []))}개 클라이언트를 복원하시겠습니까?",
            QMessageBox.Yes | QMessageBox.No)

        if reply == QMessageBox.Yes:
            self.config['clients'] = backup['clients']
            self.save_config()
            QMessageBox.information(self, "완료", "복원되었습니다.")
            dialog.close()
            self.refresh_clients()

    def save_settings(self):
        self.config['server_ip'] = self.server_ip_edit.text()
        self.config['network_interface'] = self.interface_edit.text()
        self.config['nfs_root'] = self.nfs_root_edit.text()
        self.config['tftp_root'] = self.tftp_root_edit.text()

        self.save_config()
        QMessageBox.information(self, "완료", "설정이 저장되었습니다.")

    def control_service(self, service: str, action: str):
        print(f"[서비스] {service} {action}")
        try:
            subprocess.run(['sudo', 'systemctl', action, service], check=True, timeout=30)
            print(f"[서비스] {service} {action} 완료")
            QMessageBox.information(self, "완료", f"{service} {action} 완료")
            self.update_service_status()
        except subprocess.CalledProcessError as e:
            QMessageBox.warning(self, "오류", f"서비스 제어 실패: {e}")
        except Exception as e:
            QMessageBox.warning(self, "오류", f"오류: {e}")

    def load_log(self, service: str):
        try:
            result = subprocess.run(
                ['journalctl', '-u', service, '-n', '100', '--no-pager'],
                capture_output=True, text=True, timeout=10
            )
            self.log_text.setPlainText(result.stdout or "로그가 없습니다.")
        except Exception as e:
            self.log_text.setPlainText(f"로그 로드 실패: {e}")

    def run_setup_wizard(self):
        self.setup_log.clear()
        self.setup_log.append("터미널에서 다음 명령어를 실행하세요:\n")
        self.setup_log.append("  ./pxe\n")
        self.setup_log.append("그 후 메뉴 6번 '초기 설정 마법사'를 선택하세요.")

    # ========== NFS 설정 기능 ==========

    def generate_exports(self):
        """등록된 클라이언트 기반으로 /etc/exports 생성"""
        print("[NFS] exports 생성 시작")
        clients = self.config.get('clients', [])
        nfs_root = self.config.get('nfs_root', '/media/polygom3d/rpi-client')

        if not clients:
            QMessageBox.warning(self, "오류", "등록된 클라이언트가 없습니다.")
            return

        self.setup_log.clear()
        self.setup_log.append("NFS exports 생성 시작...")
        self.setup_log.append(f"NFS 경로: {nfs_root}")
        self.setup_log.append(f"클라이언트 수: {len(clients)}")
        self.setup_log.append("-" * 50)

        # exports 라인 생성
        export_lines = []
        for client in clients:
            serial = client.get('serial', client.get('hostname', ''))
            if serial:
                line = f"{nfs_root}/{serial} *(rw,sync,no_subtree_check,no_root_squash)"
                export_lines.append(line)
                self.setup_log.append(line)

        if not export_lines:
            QMessageBox.warning(self, "오류", "생성할 export 설정이 없습니다.")
            return

        self.setup_log.append("-" * 50)

        # 확인 다이얼로그
        reply = QMessageBox.question(self, "확인",
            f"{len(export_lines)}개의 NFS export 설정을 /etc/exports에 추가하시겠습니까?\n\n"
            "기존 설정에 추가됩니다.",
            QMessageBox.Yes | QMessageBox.No)

        if reply != QMessageBox.Yes:
            self.setup_log.append("\n취소됨")
            return

        try:
            # 임시 파일에 저장
            temp_file = '/tmp/new_exports.txt'
            with open(temp_file, 'w') as f:
                f.write('\n'.join(export_lines) + '\n')

            # sudo로 /etc/exports에 추가
            result = subprocess.run(
                ['sudo', 'sh', '-c', f'cat {temp_file} >> /etc/exports'],
                capture_output=True, text=True, timeout=30
            )

            if result.returncode != 0:
                self.setup_log.append(f"오류: {result.stderr}")
                QMessageBox.warning(self, "오류", f"exports 적용 실패:\n{result.stderr}")
                return

            self.setup_log.append("\n/etc/exports에 추가 완료")

            # exportfs -ra 실행
            result = subprocess.run(
                ['sudo', 'exportfs', '-ra'],
                capture_output=True, text=True, timeout=30
            )

            if result.returncode == 0:
                self.setup_log.append("NFS exports 리로드 완료 (exportfs -ra)")
            else:
                self.setup_log.append(f"exportfs 경고: {result.stderr}")

            self.setup_log.append(f"\n완료! {len(export_lines)}개 설정 적용됨")
            QMessageBox.information(self, "완료",
                f"{len(export_lines)}개의 NFS export 설정이 적용되었습니다.")

        except Exception as e:
            self.setup_log.append(f"오류: {e}")
            QMessageBox.warning(self, "오류", str(e))

    def show_cmdline_update_dialog(self):
        """cmdline.txt 경로 수정 다이얼로그"""
        print("[NFS] cmdline.txt 경로 수정 다이얼로그 열기")
        dialog = QDialog(self)
        dialog.setWindowTitle("cmdline.txt NFS 경로 수정")
        dialog.setMinimumWidth(500)
        dialog.setStyleSheet(self.styleSheet())

        layout = QVBoxLayout(dialog)
        layout.setSpacing(15)

        info = QLabel("모든 클라이언트의 cmdline.txt에서 NFS 경로를 일괄 변경합니다.")
        info.setWordWrap(True)
        layout.addWidget(info)

        form = QFormLayout()

        self.old_path_edit = QLineEdit()
        self.old_path_edit.setPlaceholderText("예: /media/rpi-client")
        form.addRow("기존 경로:", self.old_path_edit)

        self.new_path_edit = QLineEdit()
        self.new_path_edit.setText(self.config.get('nfs_root', '/media/polygom3d/rpi-client'))
        form.addRow("새 경로:", self.new_path_edit)

        layout.addLayout(form)

        btn_layout = QHBoxLayout()

        apply_btn = QPushButton("적용")
        apply_btn.setObjectName("primary_btn")
        apply_btn.clicked.connect(lambda: self.update_cmdline_paths(dialog))
        btn_layout.addWidget(apply_btn)

        cancel_btn = QPushButton("취소")
        cancel_btn.clicked.connect(dialog.reject)
        btn_layout.addWidget(cancel_btn)

        layout.addLayout(btn_layout)

        dialog.exec_()

    def update_cmdline_paths(self, dialog):
        """cmdline.txt NFS 경로 일괄 업데이트"""
        old_path = self.old_path_edit.text().strip()
        new_path = self.new_path_edit.text().strip()
        tftp_root = self.config.get('tftp_root', '/tftpboot')
        print(f"[NFS] cmdline.txt 경로 업데이트: {old_path} -> {new_path}")

        if not old_path or not new_path:
            QMessageBox.warning(self, "오류", "기존 경로와 새 경로를 모두 입력하세요.")
            return

        if old_path == new_path:
            QMessageBox.warning(self, "오류", "기존 경로와 새 경로가 같습니다.")
            return

        self.setup_log.clear()
        self.setup_log.append("cmdline.txt 업데이트 시작...")
        self.setup_log.append(f"경로 변환: {old_path} → {new_path}")
        self.setup_log.append("-" * 50)

        try:
            # tftpboot 디렉토리에서 모든 cmdline.txt 찾기
            result = subprocess.run(
                ['sudo', 'find', tftp_root, '-name', 'cmdline.txt'],
                capture_output=True, text=True, timeout=30
            )

            cmdline_files = [f for f in result.stdout.strip().split('\n') if f]

            if not cmdline_files:
                self.setup_log.append("cmdline.txt 파일을 찾을 수 없습니다.")
                QMessageBox.warning(self, "오류", "cmdline.txt 파일이 없습니다.")
                return

            self.setup_log.append(f"총 {len(cmdline_files)}개의 cmdline.txt 파일 발견\n")

            updated_count = 0
            for filepath in cmdline_files:
                # sed로 경로 변경
                result = subprocess.run(
                    ['sudo', 'sed', '-i', f's|{old_path}|{new_path}|g', filepath],
                    capture_output=True, text=True, timeout=10
                )

                if result.returncode == 0:
                    updated_count += 1
                    short_path = filepath.replace(tftp_root + '/', '')
                    self.setup_log.append(f"  ✓ {short_path}")
                else:
                    self.setup_log.append(f"  ✗ {filepath}: {result.stderr}")

            self.setup_log.append(f"\n총 {updated_count}/{len(cmdline_files)}개 파일 업데이트 완료!")

            QMessageBox.information(self, "완료",
                f"{updated_count}개의 cmdline.txt 파일이 업데이트되었습니다.")

            dialog.accept()

        except Exception as e:
            self.setup_log.append(f"오류: {e}")
            QMessageBox.warning(self, "오류", str(e))

    def closeEvent(self, event):
        if hasattr(self, 'status_thread'):
            self.status_thread.stop()
            self.status_thread.wait()

        if self.ping_thread and self.ping_thread.isRunning():
            self.ping_thread.stop()
            self.ping_thread.wait()

        event.accept()


def main():
    app = QApplication(sys.argv)

    font = QFont("NanumGothic", 11)
    app.setFont(font)

    window = RPIPXEManagerGUI()
    window.show()

    sys.exit(app.exec_())


if __name__ == "__main__":
    main()
