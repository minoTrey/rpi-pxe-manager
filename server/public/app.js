const socket = io();

const elements = {
    serverIp: document.getElementById('server-ip'),
    dhcpRange: document.getElementById('dhcp-range'),
    dnsmasqStatus: document.getElementById('dnsmasq-status'),
    nfsStatus: document.getElementById('nfs-status'),
    clientsList: document.getElementById('clients-list'),
    consoleOutput: document.getElementById('console-output'),
    setupServerBtn: document.getElementById('setup-server-btn'),
    setupClientBtn: document.getElementById('setup-client-btn'),
    createClientBtn: document.getElementById('create-client-btn'),
    setupClientModal: document.getElementById('setup-client-modal'),
    createClientModal: document.getElementById('create-client-modal'),
    setupClientForm: document.getElementById('setup-client-form'),
    createClientForm: document.getElementById('create-client-form'),
    sdCardSelect: document.getElementById('sd-card-select'),
    sourceClientSelect: document.getElementById('source-client-select')
};

function updateStatus(status) {
    if (!status) return;
    
    if (status.server) {
        elements.serverIp.textContent = `서버 IP: ${status.server.ip || '미설정'}`;
        elements.dhcpRange.textContent = `DHCP 범위: ${status.server.dhcpRange || '미설정'}`;
    }
    
    if (status.services) {
        elements.dnsmasqStatus.className = `status-indicator ${status.services.dnsmasq ? 'active' : 'inactive'}`;
        elements.nfsStatus.className = `status-indicator ${status.services.nfs ? 'active' : 'inactive'}`;
    }
    
    if (status.clients) {
        updateClientsList(status.clients);
    }
}

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
                <div class="client-ip">IP: ${client.ip}</div>
            </div>
            <div class="client-status ${client.online ? 'online' : 'offline'}"></div>
        </div>
    `).join('');
    
    elements.sourceClientSelect.innerHTML = '<option value="">클라이언트 선택...</option>' +
        clients.map(client => `<option value="${client.serial}">${client.hostname} (${client.ip})</option>`).join('');
}

function addConsoleMessage(message, type = 'info') {
    const timestamp = new Date().toLocaleTimeString();
    const messageDiv = document.createElement('div');
    messageDiv.style.color = type === 'error' ? '#e74c3c' : '#ecf0f1';
    messageDiv.textContent = `[${timestamp}] ${message}`;
    elements.consoleOutput.appendChild(messageDiv);
    elements.consoleOutput.scrollTop = elements.consoleOutput.scrollHeight;
}

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
    }
}

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

elements.createClientBtn.addEventListener('click', async () => {
    const response = await fetch('/api/status');
    const status = await response.json();
    
    if (!status.clients || status.clients.length === 0) {
        alert('복사할 클라이언트가 없습니다. 먼저 첫 클라이언트를 설정해주세요.');
        return;
    }
    
    elements.createClientModal.style.display = 'block';
});

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

document.querySelectorAll('.close').forEach(closeBtn => {
    closeBtn.addEventListener('click', (e) => {
        e.target.closest('.modal').style.display = 'none';
    });
});

window.addEventListener('click', (e) => {
    if (e.target.classList.contains('modal')) {
        e.target.style.display = 'none';
    }
});

socket.on('connect', () => {
    addConsoleMessage('서버에 연결되었습니다');
    socket.emit('get-status');
});

socket.on('disconnect', () => {
    addConsoleMessage('서버 연결이 끊어졌습니다', 'error');
});

socket.on('status-update', (status) => {
    updateStatus(status);
});

socket.on('script-output', (data) => {
    addConsoleMessage(`[${data.script}] ${data.data}`);
});

socket.on('script-error', (data) => {
    addConsoleMessage(`[${data.script}] ${data.data}`, 'error');
});

async function loadInitialStatus() {
    try {
        const response = await fetch('/api/status');
        const status = await response.json();
        updateStatus(status);
    } catch (error) {
        addConsoleMessage('초기 상태 로드 실패', 'error');
    }
}

loadInitialStatus();