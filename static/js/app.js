const socket = io();

// DOM 요소들
const elements = {
    serverIp: document.getElementById('server-ip'),
    dhcpRange: document.getElementById('dhcp-range'),
    interface: document.getElementById('interface'),
    dnsmasqStatus: document.getElementById('dnsmasq-status'),
    nfsStatus: document.getElementById('nfs-status'),
    cpuUsage: document.getElementById('cpu-usage'),
    cpuPercent: document.getElementById('cpu-percent'),
    memoryUsage: document.getElementById('memory-usage'),
    memoryPercent: document.getElementById('memory-percent'),
    diskUsage: document.getElementById('disk-usage'),
    diskPercent: document.getElementById('disk-percent'),
    clientsList: document.getElementById('clients-list'),
    consoleOutput: document.getElementById('console-output'),
    setupServerBtn: document.getElementById('setup-server-btn'),
    setupClientBtn: document.getElementById('setup-client-btn'),
    createClientBtn: document.getElementById('create-client-btn'),
    configBtn: document.getElementById('config-btn'),
    clearConsoleBtn: document.getElementById('clear-console'),
    viewDnsmasqLog: document.getElementById('view-dnsmasq-log'),
    viewNfsLog: document.getElementById('view-nfs-log'),
    setupClientModal: document.getElementById('setup-client-modal'),
    createClientModal: document.getElementById('create-client-modal'),
    configModal: document.getElementById('config-modal'),
    logModal: document.getElementById('log-modal'),
    setupClientForm: document.getElementById('setup-client-form'),
    createClientForm: document.getElementById('create-client-form'),
    configForm: document.getElementById('config-form'),
    sdCardSelect: document.getElementById('sd-card-select'),
    sourceClientSelect: document.getElementById('source-client-select'),
    refreshSdcardsBtn: document.getElementById('refresh-sdcards')
};

// 상태 업데이트
function updateStatus(status) {
    if (!status) return;
    
    // 서버 정보
    if (status.server) {
        elements.serverIp.textContent = `서버 IP: ${status.server.ip || '미설정'}`;
        elements.dhcpRange.textContent = `DHCP 범위: ${status.server.dhcp_range || '미설정'}`;
        elements.interface.textContent = `인터페이스: ${status.server.interface || '미설정'}`;
        
        // 리소스 사용량
        updateResourceBar(elements.cpuUsage, elements.cpuPercent, status.server.cpu_percent);
        updateResourceBar(elements.memoryUsage, elements.memoryPercent, status.server.memory_percent);
        updateResourceBar(elements.diskUsage, elements.diskPercent, status.server.disk_usage);
    }
    
    // 서비스 상태
    if (status.services) {
        elements.dnsmasqStatus.className = `status-indicator ${status.services.dnsmasq ? 'active' : 'inactive'}`;
        elements.nfsStatus.className = `status-indicator ${status.services.nfs ? 'active' : 'inactive'}`;
    }
    
    // 클라이언트 목록
    if (status.clients) {
        updateClientsList(status.clients);
    }
}

// 리소스 바 업데이트
function updateResourceBar(fillElement, textElement, percent) {
    const value = percent || 0;
    fillElement.style.width = `${value}%`;
    textElement.textContent = `${Math.round(value)}%`;
    
    // 색상 변경
    if (value > 80) {
        fillElement.style.backgroundColor = '#e74c3c';
    } else if (value > 60) {
        fillElement.style.backgroundColor = '#f39c12';
    } else {
        fillElement.style.backgroundColor = '#3498db';
    }
}

// 클라이언트 목록 업데이트
function updateClientsList(clients) {
    if (clients.length === 0) {
        elements.clientsList.innerHTML = '<div class="loading">등록된 클라이언트가 없습니다</div>';
        return;
    }
    
    elements.clientsList.innerHTML = clients.map(client => `
        <div class="client-item">
            <div class="client-info">
                <div class="client-hostname">${client.hostname}</div>
                <div class="client-serial">시리얼: ${client.serial}</div>
                <div class="client-ip">IP: ${client.ip || '미할당'}</div>
            </div>
            <div class="client-status ${client.online ? 'online' : 'offline'}" 
                 title="${client.online ? '온라인' : '오프라인'}"></div>
        </div>
    `).join('');
    
    // 소스 클라이언트 선택 옵션 업데이트
    elements.sourceClientSelect.innerHTML = '<option value="">클라이언트 선택...</option>' +
        clients.map(client => `<option value="${client.serial}">${client.hostname} (${client.ip || '미할당'})</option>`).join('');
}

// 콘솔 메시지 추가
function addConsoleMessage(message, type = 'info') {
    const timestamp = new Date().toLocaleTimeString();
    const line = document.createElement('div');
    line.className = `console-line ${type}`;
    line.textContent = `[${timestamp}] ${message}`;
    elements.consoleOutput.appendChild(line);
    elements.consoleOutput.scrollTop = elements.consoleOutput.scrollHeight;
}

// SD 카드 목록 로드
async function loadSDCards() {
    try {
        const response = await fetch('/api/mounted-sdcards');
        const sdCards = await response.json();
        
        if (sdCards.length === 0) {
            elements.sdCardSelect.innerHTML = '<option value="">SD 카드를 찾을 수 없습니다</option>';
        } else {
            elements.sdCardSelect.innerHTML = sdCards.map(card => 
                `<option value="${card.mountpoint}">${card.device} - ${card.mountpoint} (${card.size})</option>`
            ).join('');
        }
    } catch (error) {
        elements.sdCardSelect.innerHTML = '<option value="">SD 카드 검색 실패</option>';
        addConsoleMessage('SD 카드 검색 중 오류가 발생했습니다', 'error');
    }
}

// 설정 로드
async function loadConfig() {
    try {
        const response = await fetch('/api/config');
        const config = await response.json();
        
        document.getElementById('config-server-ip').value = config.server_ip || '';
        document.getElementById('config-dhcp-start').value = config.dhcp_range_start || '';
        document.getElementById('config-dhcp-end').value = config.dhcp_range_end || '';
        document.getElementById('config-interface').value = config.interface || '';
    } catch (error) {
        addConsoleMessage('설정 로드 실패', 'error');
    }
}

// API 요청 실행
async function executeAction(url, data = {}) {
    try {
        const response = await fetch(url, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(data)
        });
        
        const result = await response.json();
        
        if (result.success) {
            addConsoleMessage('작업이 성공적으로 완료되었습니다', 'success');
        } else {
            addConsoleMessage(`오류: ${result.error}`, 'error');
        }
        
        return result;
    } catch (error) {
        addConsoleMessage(`요청 실패: ${error.message}`, 'error');
        return { success: false, error: error.message };
    }
}

// 서비스 로그 보기
async function viewServiceLog(service) {
    try {
        const response = await fetch(`/api/logs/${service}`);
        const data = await response.json();
        
        document.getElementById('log-title').textContent = `${service.toUpperCase()} 서비스 로그`;
        document.getElementById('log-content').textContent = data.logs || '로그를 불러올 수 없습니다';
        elements.logModal.style.display = 'block';
    } catch (error) {
        addConsoleMessage(`로그 로드 실패: ${error.message}`, 'error');
    }
}

// 이벤트 리스너들
elements.setupServerBtn.addEventListener('click', async () => {
    if (!confirm('서버 초기 설정을 시작하시겠습니까? 이 작업은 네트워크 설정을 변경합니다.')) {
        return;
    }
    
    elements.setupServerBtn.disabled = true;
    addConsoleMessage('서버 설정을 시작합니다...');
    
    await executeAction('/api/setup-server');
    
    elements.setupServerBtn.disabled = false;
});

elements.setupClientBtn.addEventListener('click', () => {
    loadSDCards();
    elements.setupClientModal.style.display = 'block';
});

elements.createClientBtn.addEventListener('click', () => {
    elements.createClientModal.style.display = 'block';
});

elements.configBtn.addEventListener('click', () => {
    loadConfig();
    elements.configModal.style.display = 'block';
});

elements.clearConsoleBtn.addEventListener('click', () => {
    elements.consoleOutput.innerHTML = '';
    addConsoleMessage('콘솔이 지워졌습니다', 'info');
});

elements.viewDnsmasqLog.addEventListener('click', () => {
    viewServiceLog('dnsmasq');
});

elements.viewNfsLog.addEventListener('click', () => {
    viewServiceLog('nfs-kernel-server');
});

elements.refreshSdcardsBtn.addEventListener('click', () => {
    loadSDCards();
});

// 폼 제출 처리
elements.setupClientForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    
    const serial = document.getElementById('client-serial').value;
    const sdCard = document.getElementById('sd-card-select').value;
    
    if (!serial || !sdCard) {
        alert('모든 필드를 입력해주세요.');
        return;
    }
    
    elements.setupClientModal.style.display = 'none';
    addConsoleMessage(`클라이언트 ${serial} 설정을 시작합니다...`);
    
    await executeAction('/api/setup-client', { serial, sdCard });
});

elements.createClientForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    
    const sourceSerial = document.getElementById('source-client-select').value;
    const newSerial = document.getElementById('new-client-serial').value;
    const macAddress = document.getElementById('new-client-mac').value;
    
    if (!sourceSerial || !newSerial) {
        alert('필수 필드를 입력해주세요.');
        return;
    }
    
    elements.createClientModal.style.display = 'none';
    addConsoleMessage(`새 클라이언트 ${newSerial} 생성을 시작합니다...`);
    
    await executeAction('/api/create-client', { sourceSerial, newSerial, macAddress });
});

elements.configForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    
    const config = {
        server_ip: document.getElementById('config-server-ip').value,
        dhcp_range_start: document.getElementById('config-dhcp-start').value,
        dhcp_range_end: document.getElementById('config-dhcp-end').value,
        interface: document.getElementById('config-interface').value
    };
    
    elements.configModal.style.display = 'none';
    
    try {
        const response = await fetch('/api/config', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(config)
        });
        
        const result = await response.json();
        if (result.success) {
            addConsoleMessage('설정이 저장되었습니다', 'success');
        }
    } catch (error) {
        addConsoleMessage('설정 저장 실패', 'error');
    }
});

// 모달 닫기 버튼들
document.querySelectorAll('.close').forEach(closeBtn => {
    closeBtn.addEventListener('click', (e) => {
        e.target.closest('.modal').style.display = 'none';
    });
});

document.querySelectorAll('.cancel-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
        e.target.closest('.modal').style.display = 'none';
    });
});

// 모달 바깥 클릭시 닫기
window.addEventListener('click', (e) => {
    if (e.target.classList.contains('modal')) {
        e.target.style.display = 'none';
    }
});

// Socket.IO 이벤트 핸들러
socket.on('connect', () => {
    addConsoleMessage('서버에 연결되었습니다', 'success');
    socket.emit('get_status');
});

socket.on('disconnect', () => {
    addConsoleMessage('서버 연결이 끊어졌습니다', 'error');
});

socket.on('status_update', (status) => {
    updateStatus(status);
});

socket.on('script_output', (data) => {
    addConsoleMessage(`[${data.script}] ${data.data}`);
});

socket.on('script_error', (data) => {
    addConsoleMessage(`[${data.script}] ${data.data}`, 'error');
});

// 초기 상태 로드
async function loadInitialStatus() {
    try {
        const response = await fetch('/api/status');
        const status = await response.json();
        updateStatus(status);
    } catch (error) {
        addConsoleMessage('초기 상태 로드 실패', 'error');
    }
}

// 페이지 로드시 실행
loadInitialStatus();