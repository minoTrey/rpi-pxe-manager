const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const cors = require('cors');
const bodyParser = require('body-parser');
const { exec, spawn } = require('child_process');
const fs = require('fs-extra');
const path = require('path');
const session = require('express-session');

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

const PORT = process.env.PORT || 3000;
const SCRIPTS_PATH = path.join(__dirname, '../../');

app.use(cors());
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, 'public')));

app.use(session({
  secret: 'rpi-pxe-secret-key',
  resave: false,
  saveUninitialized: true
}));

const executeScript = (scriptName, args = []) => {
  return new Promise((resolve, reject) => {
    const scriptPath = path.join(SCRIPTS_PATH, scriptName);
    const child = spawn('sudo', ['bash', scriptPath, ...args]);
    
    let output = '';
    let errorOutput = '';
    
    child.stdout.on('data', (data) => {
      output += data.toString();
      io.emit('script-output', { script: scriptName, data: data.toString() });
    });
    
    child.stderr.on('data', (data) => {
      errorOutput += data.toString();
      io.emit('script-error', { script: scriptName, data: data.toString() });
    });
    
    child.on('close', (code) => {
      if (code === 0) {
        resolve({ success: true, output, error: errorOutput });
      } else {
        reject({ success: false, output, error: errorOutput, code });
      }
    });
  });
};

const getSystemStatus = async () => {
  try {
    const status = {
      server: {},
      clients: [],
      services: {}
    };
    
    const checkService = (serviceName) => {
      return new Promise((resolve) => {
        exec(`systemctl is-active ${serviceName}`, (error, stdout) => {
          resolve(stdout.trim() === 'active');
        });
      });
    };
    
    status.services.dnsmasq = await checkService('dnsmasq');
    status.services.nfs = await checkService('nfs-kernel-server');
    
    if (await fs.pathExists('/etc/dnsmasq.conf')) {
      const dnsmasqConf = await fs.readFile('/etc/dnsmasq.conf', 'utf-8');
      const ipMatch = dnsmasqConf.match(/dhcp-range=([^,]+),([^,]+)/);
      if (ipMatch) {
        status.server.dhcpRange = `${ipMatch[1]} - ${ipMatch[2]}`;
      }
    }
    
    const netplanFile = '/etc/netplan/01-netcfg.yaml';
    if (await fs.pathExists(netplanFile)) {
      const netplanConf = await fs.readFile(netplanFile, 'utf-8');
      const ipMatch = netplanConf.match(/addresses:\s*\[\s*([^\]]+)\s*\]/);
      if (ipMatch) {
        status.server.ip = ipMatch[1].trim();
      }
    }
    
    if (await fs.pathExists('rpi_serials.txt')) {
      const serials = await fs.readFile('rpi_serials.txt', 'utf-8');
      const serialList = serials.trim().split('\n').filter(s => s);
      
      for (const serial of serialList) {
        const clientInfo = {
          serial,
          hostname: `rpi4-${serial}`,
          ip: '',
          online: false
        };
        
        if (await fs.pathExists('rpi_ips.txt')) {
          const ips = await fs.readFile('rpi_ips.txt', 'utf-8');
          const ipMatch = ips.match(new RegExp(`${serial}:\\s*([^\\n]+)`));
          if (ipMatch) {
            clientInfo.ip = ipMatch[1];
            
            const pingResult = await new Promise((resolve) => {
              exec(`ping -c 1 -W 1 ${clientInfo.ip}`, (error) => {
                resolve(!error);
              });
            });
            clientInfo.online = pingResult;
          }
        }
        
        status.clients.push(clientInfo);
      }
    }
    
    return status;
  } catch (error) {
    console.error('Error getting system status:', error);
    return null;
  }
};

app.get('/api/status', async (req, res) => {
  const status = await getSystemStatus();
  res.json(status);
});

app.post('/api/setup-server', async (req, res) => {
  try {
    const result = await executeScript('setup_server.sh');
    res.json(result);
  } catch (error) {
    res.status(500).json(error);
  }
});

app.post('/api/setup-client', async (req, res) => {
  const { serial, sdCard } = req.body;
  try {
    const result = await executeScript('setup_client.sh', [serial, sdCard]);
    res.json(result);
  } catch (error) {
    res.status(500).json(error);
  }
});

app.post('/api/create-client', async (req, res) => {
  const { sourceSerial, newSerial, macAddress } = req.body;
  try {
    const args = [sourceSerial, newSerial];
    if (macAddress) args.push(macAddress);
    const result = await executeScript('create_new_client.sh', args);
    res.json(result);
  } catch (error) {
    res.status(500).json(error);
  }
});

app.get('/api/mounted-sdcards', async (req, res) => {
  exec('lsblk -J -o NAME,MOUNTPOINT,SIZE,TYPE', (error, stdout) => {
    if (error) {
      res.status(500).json({ error: error.message });
      return;
    }
    
    try {
      const data = JSON.parse(stdout);
      const sdCards = [];
      
      data.blockdevices.forEach(device => {
        if (device.type === 'disk' && device.name.startsWith('sd')) {
          device.children?.forEach(child => {
            if (child.mountpoint && child.mountpoint.includes('/media')) {
              sdCards.push({
                device: `/dev/${child.name}`,
                mountpoint: child.mountpoint,
                size: child.size
              });
            }
          });
        }
      });
      
      res.json(sdCards);
    } catch (e) {
      res.status(500).json({ error: 'Failed to parse device information' });
    }
  });
});

app.get('/api/logs/:service', (req, res) => {
  const service = req.params.service;
  const validServices = ['dnsmasq', 'nfs-kernel-server'];
  
  if (!validServices.includes(service)) {
    res.status(400).json({ error: 'Invalid service' });
    return;
  }
  
  exec(`sudo journalctl -u ${service} -n 100 --no-pager`, (error, stdout) => {
    if (error) {
      res.status(500).json({ error: error.message });
      return;
    }
    res.json({ logs: stdout });
  });
});

io.on('connection', (socket) => {
  console.log('Client connected');
  
  socket.on('disconnect', () => {
    console.log('Client disconnected');
  });
  
  socket.on('get-status', async () => {
    const status = await getSystemStatus();
    socket.emit('status-update', status);
  });
});

const statusInterval = setInterval(async () => {
  const status = await getSystemStatus();
  io.emit('status-update', status);
}, 5000);

server.listen(PORT, () => {
  console.log(`RPI PXE Manager Server running on port ${PORT}`);
});