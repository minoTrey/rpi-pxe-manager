[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("prepare", "start", "stop", "start-attempt", "finish-attempt", "status", "restore-winnfsd")]
    [string] $Command = "status",

    [string] $Config = ".\windows\lab-10.73.json",
    [string] $Serial = "d80c0b88",
    [string] $Mac = "88:a2:9e:4f:a9:b1",
    [string] $PiIp = "10.73.0.155",
    [string] $ToolsRoot = "D:\tools\rpi-netboot",
    [string] $OutRoot = "D:\logs\netboot-harness",
    [ValidateSet("Portable", "Service")]
    [string] $Mode = "Portable",
    [string] $PortableRoot = "D:\tools\rpi-netboot\hanewin-portable",
    [string] $ConsoleText = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$NfsdRoot = "C:\Program Files\nfsd"
$EffectiveNfsdRoot = if ($Mode -eq "Portable") { $PortableRoot } else { $NfsdRoot }
$ExportsPath = Join-Path $EffectiveNfsdRoot "exports"
$WinNfsdPidPath = Join-Path $ToolsRoot "run\winnfsd.pid"
$HaneWinPidPath = Join-Path $ToolsRoot "run\hanewin-portable-nfsd.pid"
$StatePath = Join-Path $ToolsRoot "config\hanewin-nfs-provider-state.json"
$PortableStdoutLog = "D:\logs\hanewin-portable.stdout.log"
$PortableStderrLog = "D:\logs\hanewin-portable.stderr.log"

function Write-Check {
    param([string] $State, [string] $Name, [string] $Detail)
    "[{0}] {1} - {2}" -f $State, $Name, $Detail
}

function Read-LabConfig {
    if (-not (Test-Path -LiteralPath $Config)) {
        throw "Config not found: $Config"
    }
    Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Save-Json {
    param([object] $Data, [string] $Path, [int] $Depth = 8)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $Data | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Ensure-HaneWinPortable {
    if ($Mode -ne "Portable") { return }
    if (-not (Test-Path -LiteralPath $NfsdRoot)) {
        throw "haneWIN NFS folder not found: $NfsdRoot"
    }
    New-Item -ItemType Directory -Force -Path $PortableRoot | Out-Null
    foreach ($name in @("nfsd.exe", "pmapd.exe")) {
        $source = Join-Path $NfsdRoot $name
        $dest = Join-Path $PortableRoot $name
        if (-not (Test-Path -LiteralPath $source)) {
            throw "haneWIN binary not found: $source"
        }
        if (-not (Test-Path -LiteralPath $dest)) {
            Copy-Item -LiteralPath $source -Destination $dest -Force
        }
    }
    Write-Check "OK" "portable haneWIN" $PortableRoot
}

function Get-Paths {
    $cfg = Read-LabConfig
    $tftpRoot = if ($cfg.tftp_root) { [string]$cfg.tftp_root } else { "D:\tftp" }
    $rootfsRoot = if ($cfg.nfs_root) { [string]$cfg.nfs_root } else { "D:\rootfs" }
    $serverIp = if ($cfg.server_ip) { [string]$cfg.server_ip } else { "10.73.0.10" }
    [pscustomobject]@{
        RootfsRoot = $rootfsRoot
        Tftp = Join-Path $tftpRoot $Serial
        Cmdline = Join-Path (Join-Path $tftpRoot $Serial) "cmdline.txt"
        ServerIp = $serverIp
    }
}

function Stop-WinNfsdOnly {
    $stoppedPids = @{}
    if (Test-Path -LiteralPath $WinNfsdPidPath) {
        $pidText = (Get-Content -LiteralPath $WinNfsdPidPath -Raw -ErrorAction SilentlyContinue).Trim()
        if ($pidText) {
            $proc = Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue
            if ($proc) {
                try {
                    Stop-Process -Id $proc.Id -Force
                } catch {
                    $wmiProcess = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction Stop
                    $wmiResult = $wmiProcess | Invoke-CimMethod -MethodName Terminate -Arguments @{} -ErrorAction Stop
                    if ($wmiResult.ReturnValue -ne 0) {
                        throw "WinNFSd WMI terminate failed for PID $($proc.Id), return=$($wmiResult.ReturnValue)"
                    }
                }
                $stoppedPids[[string]$proc.Id] = $true
                Write-Check "OK" "WinNFSd stop" "PID $($proc.Id)"
            }
        }
    }
    foreach ($proc in @(Get-Process -Name "WinNFSd" -ErrorAction SilentlyContinue)) {
        if ($stoppedPids.ContainsKey([string]$proc.Id)) { continue }
        try {
            Stop-Process -Id $proc.Id -Force
        } catch {
            $wmiProcess = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction Stop
            $wmiResult = $wmiProcess | Invoke-CimMethod -MethodName Terminate -Arguments @{} -ErrorAction Stop
            if ($wmiResult.ReturnValue -ne 0) {
                throw "WinNFSd WMI terminate failed for PID $($proc.Id), return=$($wmiResult.ReturnValue)"
            }
        }
        Write-Check "OK" "WinNFSd stop" "PID $($proc.Id)"
    }
    Remove-Item -LiteralPath $WinNfsdPidPath -Force -ErrorAction SilentlyContinue
}

function Backup-Cmdline {
    param([string] $Cmdline)
    if (-not (Test-Path -LiteralPath $Cmdline)) {
        throw "cmdline.txt not found: $Cmdline"
    }
    $backup = "{0}.backup-hanewin-{1}" -f $Cmdline, (Get-Date -Format "yyyyMMdd-HHmmss")
    Copy-Item -LiteralPath $Cmdline -Destination $backup
    $backup
}

function Set-WinNfsdCmdline {
    $paths = Get-Paths
    $line = "console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=$($paths.ServerIp):/rpi/$Serial,vers=3,tcp rw ip=dhcp rootwait elevator=deadline init=/usr/sbin/init"
    Set-Content -LiteralPath $paths.Cmdline -Value $line -Encoding ASCII -NoNewline
    Write-Check "OK" "cmdline" $line
}

function Configure-HaneWin {
    Ensure-HaneWinPortable
    if (-not (Test-Path -LiteralPath $EffectiveNfsdRoot)) {
        throw "haneWIN NFS folder not found: $EffectiveNfsdRoot"
    }
    $paths = Get-Paths
    if (-not (Test-Path -LiteralPath $paths.RootfsRoot)) {
        throw "rootfs root not found: $($paths.RootfsRoot)"
    }
    $backup = $null
    if (Test-Path -LiteralPath $ExportsPath) {
        $backup = "{0}.backup-{1}" -f $ExportsPath, (Get-Date -Format "yyyyMMdd-HHmmss")
        Copy-Item -LiteralPath $ExportsPath -Destination $backup
    }
    $lines = @(
        "# Generated by RPI Netboot Manager haneWIN NFS provider",
        "# NFS-only A/B test. DHCP/TFTP stay on RpiBootServiceLite.",
        "# -exec forces executable bits; SaveAttr stores uid/gid/mode on NTFS.",
        "$($paths.RootfsRoot) -name:rpi -alldirs -i32 -maproot:0:0 -exec -range 10.73.0.0 10.73.0.255"
    )
    Set-Content -LiteralPath $ExportsPath -Value $lines -Encoding ASCII
    try {
        reg add "HKLM\SOFTWARE\haneWIN\nfsd" /v SaveAttr /t REG_DWORD /d 1 /f | Out-Null
        Write-Check "OK" "haneWIN SaveAttr" "registry enabled"
    } catch {
        Write-Check "WARN" "haneWIN SaveAttr" "registry not changed: $($_.Exception.Message)"
    }
    foreach ($rule in @(
        @{ Name = "RPI Netboot haneWIN SunRPC Portmap"; Program = (Join-Path $EffectiveNfsdRoot "pmapd.exe") },
        @{ Name = "RPI Netboot haneWIN NFS Server"; Program = (Join-Path $EffectiveNfsdRoot "nfsd.exe") }
    )) {
        try {
            $existingRule = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
            if (-not $existingRule) {
                New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound -Action Allow -Program $rule.Program -Profile Any -RemoteAddress LocalSubnet | Out-Null
            }
            Write-Check "OK" "firewall" $rule.Name
        } catch {
            Write-Check "WARN" "firewall" "$($rule.Name): $($_.Exception.Message)"
        }
    }
    Save-Json ([pscustomobject]@{
        provider = "haneWIN"
        mode = $Mode
        root = $EffectiveNfsdRoot
        exports = $ExportsPath
        backup = $backup
        rootfsRoot = $paths.RootfsRoot
        serverIp = $paths.ServerIp
        serial = $Serial
        updatedAt = (Get-Date).ToString("o")
    }) $StatePath
    Write-Check "OK" "haneWIN exports" "$($paths.RootfsRoot) -> /rpi"
    if ($backup) { Write-Check "OK" "exports backup" $backup }
}

function Start-HaneWinNfs {
    Stop-WinNfsdOnly
    Stop-HaneWinNfs
    if ($Mode -eq "Portable") {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $HaneWinPidPath) | Out-Null
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $PortableStdoutLog) | Out-Null
        $exe = Join-Path $EffectiveNfsdRoot "nfsd.exe"
        $cmd = 'cd /d "{0}" && "{1}" -debug -portmap 1>> "{2}" 2>> "{3}"' -f $EffectiveNfsdRoot, $exe, $PortableStdoutLog, $PortableStderrLog
        Start-Process -FilePath $env:ComSpec -ArgumentList @("/c", $cmd) -WindowStyle Hidden | Out-Null
        Start-Sleep -Seconds 2
        $started = @(Get-CimInstance Win32_Process -Filter "name = 'nfsd.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.ExecutablePath -and ([string]::Equals($_.ExecutablePath, $exe, [StringComparison]::OrdinalIgnoreCase)) } |
            Sort-Object ProcessId -Descending |
            Select-Object -First 1)
        if (-not $started) {
            $tail = if (Test-Path -LiteralPath $PortableStderrLog) { Get-Content -LiteralPath $PortableStderrLog -Tail 40 -ErrorAction SilentlyContinue } else { @() }
            throw "portable haneWIN nfsd exited early. $($tail -join ' ')"
        }
        Set-Content -LiteralPath $HaneWinPidPath -Value $started.ProcessId -Encoding ASCII
        Write-Check "OK" "haneWIN portable" "PID $($started.ProcessId), log=$PortableStdoutLog"
    } else {
        foreach ($svc in @("PMAPDaemon", "NFSserver")) {
            $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($service) {
                if ($service.Status -ne "Running") {
                    Start-Service -Name $svc
                }
                Write-Check "OK" $svc ((Get-Service -Name $svc).Status)
            } else {
                Write-Check "WARN" $svc "service not found"
            }
        }
    }
}

function Stop-HaneWinNfs {
    if (Test-Path -LiteralPath $HaneWinPidPath) {
        $pidText = (Get-Content -LiteralPath $HaneWinPidPath -Raw -ErrorAction SilentlyContinue).Trim()
        if ($pidText) {
            $proc = Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue
            if ($proc) {
                Stop-Process -Id $proc.Id -Force
                Write-Check "OK" "haneWIN portable stop" "PID $($proc.Id)"
            }
        }
        Remove-Item -LiteralPath $HaneWinPidPath -Force -ErrorAction SilentlyContinue
    }
    foreach ($proc in @(Get-CimInstance Win32_Process -Filter "name = 'nfsd.exe'" -ErrorAction SilentlyContinue)) {
        if ($proc.ExecutablePath -and ([string]::Equals($proc.ExecutablePath, (Join-Path $EffectiveNfsdRoot "nfsd.exe"), [StringComparison]::OrdinalIgnoreCase))) {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
            Write-Check "OK" "haneWIN portable stop" "PID $($proc.ProcessId)"
        }
    }
    foreach ($svc in @("NFSserver", "PMAPDaemon")) {
        $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($service -and $service.Status -ne "Stopped") {
            Stop-Service -Name $svc -Force
            Write-Check "OK" $svc "stopped"
        }
    }
}

function Show-Status {
    Write-Check "INFO" "exports" $ExportsPath
    if (Test-Path -LiteralPath $ExportsPath) { Get-Content -LiteralPath $ExportsPath -Raw -Encoding ASCII }
    if (Test-Path -LiteralPath $HaneWinPidPath) {
        Write-Check "INFO" "portable pid" ((Get-Content -LiteralPath $HaneWinPidPath -Raw -Encoding ASCII).Trim())
    }
    Get-Service NFSserver,PMAPDaemon -ErrorAction SilentlyContinue | Select-Object Name,Status,StartType | Format-Table -AutoSize | Out-String
    Get-NetTCPConnection -LocalPort 111,2049 -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort,State,OwningProcess | Format-Table -AutoSize | Out-String
    Get-NetUDPEndpoint -LocalPort 111,2049 -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort,OwningProcess | Format-Table -AutoSize | Out-String
    $paths = Get-Paths
    if (Test-Path -LiteralPath $paths.Cmdline) {
        Write-Check "INFO" "cmdline" ((Get-Content -LiteralPath $paths.Cmdline -Raw -Encoding ASCII).Trim())
    }
}

function Invoke-Harness {
    param([string] $HarnessCommand)
    $script = Join-Path $PSScriptRoot "netboot-harness.ps1"
    $args = @(
        $HarnessCommand,
        "-Config", $Config,
        "-Serial", $Serial,
        "-Mac", $Mac,
        "-PiIp", $PiIp,
        "-Provider", "haneWIN",
        "-InitVariant", "busybox-static",
        "-OutRoot", $OutRoot
    )
    if (-not [string]::IsNullOrWhiteSpace($ConsoleText)) {
        $args += @("-ConsoleText", $ConsoleText)
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script @args
}

switch ($Command) {
    "prepare" {
        Configure-HaneWin
        Show-Status
    }
    "start" {
        Configure-HaneWin
        Start-HaneWinNfs
        Show-Status
    }
    "stop" {
        Stop-HaneWinNfs
        Show-Status
    }
    "start-attempt" {
        Configure-HaneWin
        Start-HaneWinNfs
        $paths = Get-Paths
        $backup = Backup-Cmdline $paths.Cmdline
        Set-WinNfsdCmdline
        Write-Check "OK" "cmdline backup" $backup
        Invoke-Harness "start-attempt"
    }
    "finish-attempt" {
        Invoke-Harness "finish-attempt"
    }
    "restore-winnfsd" {
        Stop-HaneWinNfs
        Set-WinNfsdCmdline
        Write-Check "NEXT" "Lite provider" "Start the free Lite provider again with the GUI button or lite-provider.ps1 start."
    }
    "status" {
        Show-Status
    }
}
