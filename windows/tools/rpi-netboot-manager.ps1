param(
    [ValidateSet("menu", "status", "server-setup", "lite-provider-start", "lite-provider-stop", "install-services", "configure-services", "prepare-rpi4-eeprom-sd", "prepare-sd", "copy-boot", "prepare-rpi4-rootfs", "prepare-zero2w-gadget-sd", "verify", "sync-tftp", "firewall", "restore-network", "docs")]
    [string] $Task = "menu",

    [string] $Config = ".\lab-10.73.json",
    [string] $LegacyBackup = "C:\Users\test\Documents\workspace\rpi-pxe-manager\clients_backup.json",
    [string] $Generated = ".\generated\lab-10.73",
    [string] $SdDriveLetter = "S",
    [ValidateSet("pi4")]
    [string] $Model = "pi4",
    [switch] $Yes
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    if (-not (Test-Admin)) {
        throw "This task needs administrator rights. Run RPI-Netboot-Manager-Admin.exe."
    }
}

function Invoke-Step {
    param(
        [string] $Name,
        [scriptblock] $Action
    )
    Write-Output ""
    Write-Output "== $Name =="
    & $Action
}

function Invoke-Tool {
    param(
        [string] $Script,
        [string[]] $Arguments = @()
    )
    $path = Join-Path $ProjectRoot $Script
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Tool failed: $Script"
    }
}

function Read-ConfigObject {
    if (-not (Test-Path -LiteralPath $Config)) {
        throw "Config not found: $Config"
    }
    return Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Confirm-Destructive {
    param([string] $Message)
    if ($Yes) { return $true }
    Write-Host ""
    Write-Host $Message -ForegroundColor Yellow
    $answer = Read-Host "Type YES to continue"
    return $answer -eq "YES"
}

function Write-Check {
    param(
        [ValidateSet("정상", "주의", "필요", "오류")]
        [string] $Status,
        [string] $Item,
        [string] $Detail
    )
    Write-Output ("[{0}] {1} - {2}" -f $Status, $Item, $Detail)
}

function Format-Size {
    param([UInt64] $Bytes)
    if ($Bytes -ge 1GB) { return "{0:N1}GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1}MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N1}KB" -f ($Bytes / 1KB) }
    return "$Bytes bytes"
}

function Test-Folder {
    param([string] $Path)
    return (Test-Path -LiteralPath $Path -PathType Container)
}

function Get-FolderCount {
    param([string] $Path)
    if (-not (Test-Folder $Path)) { return 0 }
    return @(Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue).Count
}

function Get-FileCount {
    param([string] $Path)
    if (-not (Test-Folder $Path)) { return 0 }
    return @(Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue).Count
}

function Test-UdpListener {
    param([int] $Port)
    return [bool](Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue)
}

function Test-TcpListener {
    param([int] $Port)
    return [bool](Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue)
}

function Get-UdpListeners {
    param([int] $Port)
    return @(Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue)
}

function Get-TcpListeners {
    param([int] $Port)
    return @(Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue)
}

function Backup-File {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $backup = "$Path.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $Path -Destination $backup -Force
    return $backup
}

function Restart-LabService {
    param([string] $Name)
    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Check "주의" $Name "서비스가 설치되어 있지 않습니다."
        return
    }
    Restart-Service -Name $Name -Force
    Start-Sleep -Milliseconds 800
    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    Write-Check "정상" $Name "상태: $($service.Status)"
}

function Invoke-RegAdd {
    param(
        [string] $Key,
        [string] $Name,
        [string] $Type,
        [string] $Value
    )
    & reg.exe add $Key /v $Name /t $Type /d $Value /f | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Registry update failed: $Key $Name"
    }
}

function Show-Status {
    $cfg = if (Test-Path -LiteralPath $Config) { Read-ConfigObject } else { $null }
    $routerAddress = if ($cfg -and $cfg.router_ip) { [string]$cfg.router_ip } else { "10.73.0.1" }
    $serverAddressExpected = if ($cfg -and $cfg.server_ip) { [string]$cfg.server_ip } else { "10.73.0.10" }

    Write-Output "상태 확인은 Raspberry Pi 4 네트워크 부팅 전에 필요한 7가지를 봅니다."
    Write-Output "정책: 네트워크 부팅 대상은 RPi4만입니다. Zero 2 W는 SD boot + USB gadget으로 준비합니다."
    Write-Output "1. D: 저장소와 S: SD카드"
    Write-Output "2. 서버 PC 이더넷 IP와 공유기 연결"
    Write-Output "3. lab 설정 파일과 TFTP/rootfs 폴더"
    Write-Output "4. DHCP/TFTP/NFS 서비스 포트"
    Write-Output "5. 무료 Lite provider 실행 상태"
    Write-Output "6. haneWIN provider 설정 상태"
    Write-Output "7. 지금 다음에 눌러야 할 버튼"

    Invoke-Step "1. 저장소 / SD카드" {
        $d = Get-Volume -DriveLetter D -ErrorAction SilentlyContinue
        if ($d -and $d.FileSystemLabel -eq "rpi" -and $d.FileSystem -eq "NTFS" -and $d.DriveType -eq "Fixed") {
            Write-Check "정상" "D: 저장소" "라벨 rpi, NTFS, 고정 디스크, 남은 공간 $(Format-Size ([UInt64]$d.SizeRemaining))"
        } elseif ($d) {
            Write-Check "오류" "D: 저장소" "기대값은 rpi/NTFS/Fixed인데 실제는 '$($d.FileSystemLabel)' '$($d.FileSystem)' '$($d.DriveType)'"
        } else {
            Write-Check "오류" "D: 저장소" "D: 드라이브가 없습니다. SD카드가 D:를 차지했는지 확인해야 합니다."
        }

        $sd = Get-Volume -DriveLetter $SdDriveLetter -ErrorAction SilentlyContinue
        if ($sd -and $sd.DriveType -eq "Removable") {
            Write-Check "정상" "$SdDriveLetter`: SD카드 후보" "$($sd.FileSystem) 이동식 드라이브, 크기 $(Format-Size ([UInt64]$sd.Size))"
        } elseif ($sd) {
            Write-Check "주의" "$SdDriveLetter`: 드라이브" "이동식 드라이브가 아닙니다. SD EEPROM 쓰기 전에 대상이 맞는지 확인하세요."
        } else {
            $eepromVolume = Get-Volume -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.DriveType -eq "Removable" -and
                    $_.FileSystem -eq "FAT32" -and
                    $_.Size -gt 64MB -and
                    $_.Size -lt 512MB
                } |
                Sort-Object Size |
                Select-Object -First 1
            if ($eepromVolume) {
                $letter = if ($eepromVolume.DriveLetter) { "$($eepromVolume.DriveLetter):" } else { "드라이브 문자 없음" }
                Write-Check "정상" "EEPROM SD카드" "작은 FAT32 이동식 파티션 $(Format-Size ([UInt64]$eepromVolume.Size)) ($letter). Pi 4 EEPROM 이미지가 쓰인 상태로 보입니다."
            } else {
                Write-Check "주의" "$SdDriveLetter`: SD카드" "현재 보이지 않습니다. SD EEPROM을 쓸 때 다시 꽂고 상태 확인을 다시 누르세요."
            }
        }
    }

    Invoke-Step "2. 네트워크" {
        $serverAddress = Get-NetIPAddress -AddressFamily IPv4 -IPAddress $serverAddressExpected -ErrorAction SilentlyContinue |
            Where-Object { $_.PrefixLength -eq 24 } |
            Select-Object -First 1
        if ($serverAddress) {
            Write-Check "정상" "서버 IP" "$($serverAddress.InterfaceAlias)에 $serverAddressExpected/24 적용됨"
        } else {
            Write-Check "오류" "서버 IP" "유선 이더넷에 $serverAddressExpected/24가 필요합니다. '서버 PC 자동 준비'를 누르세요."
        }

        $routerOk = Test-Connection -ComputerName $routerAddress -Count 1 -Quiet -ErrorAction SilentlyContinue
        if ($routerOk) {
            Write-Check "정상" "공유기 연결" "$routerAddress ping 성공"
        } else {
            Write-Check "오류" "공유기 연결" "$routerAddress ping 실패. ipTIME 관리 IP와 유선 연결을 확인하세요."
        }

        $wifi = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Wi-Fi" -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike "169.254.*" } |
            Select-Object -First 1
        if ($wifi) {
            Write-Check "정상" "인터넷용 Wi-Fi" "$($wifi.IPAddress) 사용 중"
        } else {
            Write-Check "주의" "인터넷용 Wi-Fi" "Wi-Fi IPv4가 보이지 않습니다. 서비스 설치 다운로드가 필요하면 인터넷 연결을 확인하세요."
        }
    }

    Invoke-Step "3. 설정 / 폴더" {
        if (-not $cfg) {
            Write-Check "오류" "lab 설정" "$Config 파일이 없습니다. '서버 PC 자동 준비'가 필요합니다."
            return
        }

        Write-Check "정상" "lab 설정" "등록된 Pi 클라이언트 $(@($cfg.clients).Count)대, 서버 IP $($cfg.server_ip), 공유기 $($cfg.router_ip)"

        foreach ($folder in @($cfg.tftp_root, $cfg.nfs_root, $cfg.iscsi_root, "D:\downloads")) {
            if (Test-Folder $folder) {
                Write-Check "정상" $folder "폴더 있음"
            } else {
                Write-Check "필요" $folder "폴더 없음. '서버 PC 자동 준비'를 누르세요."
            }
        }

        $tftpDirs = Get-FolderCount $cfg.tftp_root
        $rootfsDirs = Get-FolderCount $cfg.nfs_root
        Write-Check "정상" "TFTP 클라이언트 폴더" "${tftpDirs}개. 각 Pi serial별 폴더입니다."
        Write-Check "주의" "rootfs 클라이언트 폴더" "${rootfsDirs}개. 폴더는 있지만 실제 Linux rootfs 파일은 아직 별도 복제가 필요합니다."

        $bootFiles = 0
        if (Test-Folder $cfg.tftp_root) {
            $bootFiles = @(Get-ChildItem -LiteralPath $cfg.tftp_root -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "^(start4\.elf|fixup4\.dat|kernel.*\.img|.*\.dtb)$" }).Count
        }
        if ($bootFiles -gt 0) {
            Write-Check "정상" "TFTP 실제 부팅 파일" "$bootFiles개 발견"
        } else {
            Write-Check "필요" "TFTP 실제 부팅 파일" "현재 cmdline/config 중심입니다. 첫 Pi의 boot partition 파일을 D:\tftp\<serial>에 채워야 합니다."
        }
    }

    Invoke-Step "4. 부팅 서비스 포트" {
        $dhcpListeners = @(Get-UdpListeners 67)
        if ($dhcpListeners.Count -gt 0) {
            $addresses = @($dhcpListeners | ForEach-Object { $_.LocalAddress }) -join ", "
            Write-Check "정상" "DHCP UDP 67" "서비스가 대기 중입니다. 주소: $addresses"
            $otherDhcp = @($dhcpListeners | Where-Object {
                $_.LocalAddress -ne $serverAddressExpected -and
                $_.LocalAddress -ne "0.0.0.0" -and
                $_.LocalAddress -ne "::"
            })
            if ($otherDhcp.Count -gt 0) {
                $otherAddresses = @($otherDhcp | ForEach-Object { $_.LocalAddress }) -join ", "
                Write-Check "주의" "DHCP 바인딩" "DHCP가 부팅망이 아닌 주소($otherAddresses)에도 떠 있습니다. Wi-Fi/인터넷망에 DHCP 응답이 나가지 않게 서비스 설정에서 이더넷 ${serverAddressExpected}만 사용하도록 제한하세요."
            }
        } else {
            Write-Check "필요" "DHCP UDP 67" "아직 대기 중인 서비스가 없습니다. DHCP 서버 설치/설정이 필요합니다."
        }
        $tftpListeners = @(Get-UdpListeners 69)
        if ($tftpListeners.Count -gt 0) {
            $addresses = @($tftpListeners | ForEach-Object { $_.LocalAddress }) -join ", "
            Write-Check "정상" "TFTP UDP 69" "서비스가 대기 중입니다. 주소: $addresses"
        } else {
            Write-Check "필요" "TFTP UDP 69" "아직 대기 중인 서비스가 없습니다. TFTP 서버 설치/설정이 필요합니다."
        }
        $nfsListeners = @(Get-TcpListeners 2049)
        if ($nfsListeners.Count -gt 0) {
            $addresses = @($nfsListeners | ForEach-Object { $_.LocalAddress }) -join ", "
            Write-Check "정상" "NFS TCP 2049" "서비스가 대기 중입니다. 주소: $addresses"
        } else {
            Write-Check "필요" "NFS TCP 2049" "아직 대기 중인 서비스가 없습니다. rootfs 부팅에는 NFS 설정이 필요합니다."
        }
        $iscsiListeners = @(Get-TcpListeners 3260)
        if ($iscsiListeners.Count -gt 0) {
            $addresses = @($iscsiListeners | ForEach-Object { $_.LocalAddress }) -join ", "
            Write-Check "정상" "iSCSI TCP 3260" "서비스가 대기 중입니다. 주소: $addresses"
        } else {
            Write-Check "주의" "iSCSI TCP 3260" "현재 NFS 방식이면 필수는 아닙니다."
        }
    }

    Invoke-Step "5. 무료 Lite provider 상태" {
        $litePidPath = "D:\tools\rpi-netboot\run\rpi-boot-lite.pid"
        $nfsPidPath = "D:\tools\rpi-netboot\run\winnfsd.pid"
        $liteExe = "D:\tools\rpi-netboot\bin\RpiBootServiceLite.exe"
        $nfsExe = "D:\tools\rpi-netboot\winnfsd\WinNFSd.exe"

        if (Test-Path -LiteralPath $liteExe) {
            Write-Check "정상" "내장 DHCP/TFTP 파일" $liteExe
        } else {
            Write-Check "필요" "내장 DHCP/TFTP 파일" "아직 준비되지 않았습니다. '무료 부팅 서비스 시작'을 누르면 자동 빌드됩니다."
        }

        if (Test-Path -LiteralPath $nfsExe) {
            Write-Check "정상" "WinNFSd 파일" $nfsExe
        } else {
            Write-Check "필요" "WinNFSd 파일" "아직 준비되지 않았습니다. '무료 부팅 서비스 시작'을 누르면 다운로드합니다."
        }

        foreach ($entry in @(
            @{ Name = "내장 DHCP/TFTP"; Path = $litePidPath },
            @{ Name = "WinNFSd"; Path = $nfsPidPath }
        )) {
            if (Test-Path -LiteralPath $entry.Path) {
                $pidText = (Get-Content -LiteralPath $entry.Path -Raw -ErrorAction SilentlyContinue).Trim()
                $proc = if ($pidText) { Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue } else { $null }
                if ($proc) {
                    Write-Check "정상" $entry.Name "실행 중 PID $pidText"
                } else {
                    Write-Check "주의" $entry.Name "PID 파일은 있지만 프로세스가 없습니다. '무료 부팅 서비스 시작'을 다시 누르세요."
                }
            } else {
                Write-Check "필요" $entry.Name "실행 중이 아닙니다. haneWIN 대신 쓰려면 '무료 부팅 서비스 시작'을 누르세요."
            }
        }
    }

    Invoke-Step "6. haneWIN provider 설정" {
        $dhcpIni = "C:\Program Files\dhcp\DHCPsrv.ini"
        if (Test-Path -LiteralPath $dhcpIni) {
            $dhcpText = Get-Content -LiteralPath $dhcpIni -Raw -ErrorAction SilentlyContinue
            if ($dhcpText -match [regex]::Escape("172.30.1.5")) {
                Write-Check "주의" "DHCP 설정" "Wi-Fi 주소 172.30.1.5 프로필이 남아 있습니다. haneWIN을 계속 쓰려면 'haneWIN 설정 적용'을 누르세요."
            } elseif ($dhcpText -match [regex]::Escape($serverAddressExpected)) {
                Write-Check "정상" "DHCP 설정" "이더넷 $serverAddressExpected 중심 설정입니다."
            } else {
                Write-Check "주의" "DHCP 설정" "서버 IP $serverAddressExpected 설정을 확인해야 합니다."
            }
            if ($dhcpText -match "DefaultOptions=43 32") {
                Write-Check "정상" "DHCP Option 43" "Raspberry Pi Boot vendor option 설정이 들어 있습니다."
            } else {
                Write-Check "필요" "DHCP Option 43" "haneWIN으로 Pi가 TFTP 요청을 시작하려면 Raspberry Pi Boot vendor option이 필요합니다. 무료 provider를 쓰려면 '무료 부팅 서비스 시작'을 누르세요."
            }
        } else {
            Write-Check "주의" "haneWIN DHCP 설정" "haneWIN 설정 파일이 없습니다. haneWIN은 빠른 검증용 30일 평가판 provider입니다."
        }

        $tftpRoot = $null
        try {
            $tftpReg = Get-ItemProperty -Path "HKLM:\SOFTWARE\haneWIN\TFTPsrv" -ErrorAction Stop
            $tftpRoot = [string]$tftpReg.RootDirectory
        } catch {
            $tftpRoot = $null
        }
        if ($cfg -and $tftpRoot -eq [string]$cfg.tftp_root) {
            Write-Check "정상" "TFTP root" "$tftpRoot"
        } elseif ($cfg) {
            Write-Check "필요" "TFTP root" "현재 '$tftpRoot'. haneWIN 기대값은 '$($cfg.tftp_root)'입니다. haneWIN을 계속 쓰려면 'haneWIN 설정 적용'을 누르세요."
        }

        $exports = "C:\Program Files\nfsd\exports"
        if (Test-Path -LiteralPath $exports) {
            $exportsText = Get-Content -LiteralPath $exports -Raw -ErrorAction SilentlyContinue
            if ($cfg -and $exportsText -match [regex]::Escape([string]$cfg.nfs_root) -and $exportsText -match "-name:rpi") {
                Write-Check "정상" "NFS export" "$($cfg.nfs_root) -> /rpi"
            } else {
                Write-Check "필요" "NFS export" "아직 D:\rootfs -> /rpi 설정이 아닙니다. haneWIN을 계속 쓰려면 'haneWIN 설정 적용'을 누르세요."
            }
        } else {
            Write-Check "주의" "haneWIN NFS export" "haneWIN NFS exports 파일이 없습니다. haneWIN 대신 무료 Lite provider를 사용할 수 있습니다."
        }
    }

    Invoke-Step "7. 다음에 할 일" {
        if (-not (Test-Admin)) {
            Write-Check "주의" "관리자 권한" "설치/SD 쓰기/방화벽 작업을 누르면 관리자 모드로 다시 열어야 합니다."
        }
        Write-Output "권장 순서:"
        Write-Output "1. 무료 부팅 서비스 시작 버튼으로 내장 DHCP/TFTP + WinNFSd provider 실행"
        Write-Output "2. haneWIN 평가판을 쓰는 경우에만 haneWIN 설치/설정 버튼 사용"
        Write-Output "3. SD카드에 EEPROM 쓰기 버튼으로 Pi 4 network boot EEPROM 준비"
        Write-Output "4. 첫 Pi의 Raspberry Pi OS boot 파티션을 꽂고 '첫 Pi 부팅파일 복사' 실행"
        Write-Output "5. 'RPi4 netboot rootfs 준비'로 Linux helper 스크립트 생성 후 D:\rootfs\<serial>에 복제"
        Write-Output "6. Zero 2 W가 필요하면 별도 SD카드에 'Zero 2 W SD boot + USB gadget 준비' 실행"
        Write-Output "7. 전체 상태 다시 확인 후 Pi 4 한 대만 네트워크 부팅 테스트"
    }
}

function Invoke-ServerSetup {
    Assert-Admin
    Invoke-Step "Fix drive letters" {
        Invoke-Tool "tools\fix-rpi-drive-letters.ps1"
    }
    Invoke-Step "Set Ethernet to 10.73.0.10" {
        Invoke-Tool "tools\set-ethernet-10.73.ps1"
    }
    Invoke-Step "Create D: storage folders" {
        foreach ($path in @("D:\tftp", "D:\rootfs", "D:\iscsi", "D:\downloads", "D:\templates", "D:\templates\golden", "D:\backups", "D:\logs", "D:\tools")) {
            New-Item -ItemType Directory -Force -Path $path | Out-Null
        }
        Get-ChildItem -Force D:\ | Select-Object Name,Mode,LastWriteTime | Format-Table -AutoSize
    }
    Invoke-Step "Regenerate lab config and plan" {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\rpi-win-netboot.ps1" import-legacy `
            -Backup $LegacyBackup `
            -Config $Config `
            -ServerIp 10.73.0.10 `
            -RouterIp 10.73.0.1 `
            -ProjectRoot "D:\" `
            -TftpRoot "D:\tftp" `
            -RootfsRoot "D:\rootfs" `
            -IscsiRoot "D:\iscsi"
        if ($LASTEXITCODE -ne 0) { throw "import-legacy failed" }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\rpi-win-netboot.ps1" generate -Config $Config -Out $Generated
        if ($LASTEXITCODE -ne 0) { throw "generate failed" }
    }
    Invoke-SyncTftp
    Invoke-Firewall
    Invoke-Verify
}

function Invoke-InstallServices {
    Assert-Admin
    Invoke-Step "Install haneWIN DHCP/TFTP/NFS packages with winget" {
        $packages = @(
            "haneWIN.DHCPServer",
            "haneWIN.TFTPServer",
            "haneWIN.NFSServer"
        )
        foreach ($package in $packages) {
            Write-Host "Installing/checking $package"
            & winget install --id $package --exact --accept-package-agreements --accept-source-agreements
            if ($LASTEXITCODE -ne 0) {
                Write-Host "winget returned $LASTEXITCODE for $package. It may already be installed or the installer may have been cancelled." -ForegroundColor Yellow
            }
        }
    }
    Invoke-Firewall
    Invoke-Step "Generated service configuration files" {
        Write-Host "DHCP/TFTP profile:"
        Write-Host (Resolve-Path "$Generated\windows\hanewin-dhcp-profile.md")
        Write-Host "NFS export:"
        Write-Host (Resolve-Path "$Generated\windows\hanewin-nfs-exports.txt")
        Write-Host ""
        Get-Content "$Generated\windows\hanewin-nfs-exports.txt"
    }
}

function Invoke-LiteProviderStart {
    Invoke-Step "무료 Lite provider 준비/시작" {
        Invoke-Tool "tools\lite-provider.ps1" @("start", "-Config", $Config)
    }
}

function Invoke-LiteProviderStop {
    Invoke-Step "무료 Lite provider 중지" {
        Invoke-Tool "tools\lite-provider.ps1" @("stop", "-Config", $Config)
    }
}

function Invoke-ConfigureServices {
    Assert-Admin
    $cfg = Read-ConfigObject
    $serverIp = [string]$cfg.server_ip
    $routerIp = [string]$cfg.router_ip
    $tftpRoot = [string]$cfg.tftp_root
    $rootfsRoot = [string]$cfg.nfs_root
    $profileName = "If-1_0.10"
    $dhcpDir = "C:\Program Files\dhcp"
    $tftpReg = "HKLM\SOFTWARE\haneWIN\TFTPsrv"
    $nfsReg = "HKLM\SOFTWARE\haneWIN\nfsd"

    Invoke-Step "0. 서비스 설정 변경 준비" {
        foreach ($serviceName in @("DHCPservice", "TFTPService", "NFSserver")) {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service -and $service.Status -ne "Stopped") {
                Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                Write-Check "정상" $serviceName "설정 변경을 위해 잠시 중지했습니다."
            } elseif ($service) {
                Write-Check "정상" $serviceName "이미 중지 상태입니다."
            } else {
                Write-Check "주의" $serviceName "서비스가 설치되어 있지 않습니다."
            }
        }
    }

    Invoke-Step "1. DHCP를 이더넷 전용으로 설정" {
        $iniPath = Join-Path $dhcpDir "DHCPsrv.ini"
        if (-not (Test-Path -LiteralPath $iniPath)) {
            throw "haneWIN DHCP 설정 파일을 찾을 수 없습니다: $iniPath"
        }
        $backup = Backup-File $iniPath
        if ($backup) { Write-Check "정상" "DHCP 설정 백업" $backup }

        $lines = @(
            "[$profileName]",
            "InterfaceIP=$serverIp",
            "GatewayIP=$routerIp",
            "DNS1IP=$routerIp",
            "SubnetMask=255.255.255.0",
            "BaseIP=10.73.0.200",
            "Range=40",
            "NextIP=$serverIp",
            "BootName=$serverIp",
            "UseOpt=1",
            "DefaultOptions=43 32 6 1 3 10 4 0 80 88 69 9 20 0 0 17 82 97 115 112 98 101 114 114 121 32 80 105 32 66 111 111 116 255",
            "SendOptions=43",
            "",
            "[DHCPsrv]",
            "Profile0=$profileName",
            "Used=1"
        )
        Set-Content -LiteralPath $iniPath -Value $lines -Encoding ASCII
        Write-Check "정상" "DHCP 바인딩" "Wi-Fi 프로필 제거, 이더넷 $serverIp 전용"
        Write-Check "정상" "DHCP 부팅 서버" "Next Server IP: $serverIp, Gateway/DNS: $routerIp"
    }

    Invoke-Step "2. 등록된 Pi 예약 IP 적용" {
        $clients = @($cfg.clients)
        $ethersPath = Join-Path $dhcpDir "ethers"
        if (Test-Path -LiteralPath $ethersPath) {
            $backup = Backup-File $ethersPath
            if ($backup) { Write-Check "정상" "DHCP 예약 목록 백업" $backup }
        }
        $stamp = [DateTimeOffset]::Now.ToUnixTimeSeconds()
        $etherLines = foreach ($client in $clients) {
            $mac = [string]$client.mac
            $ip = [string]$client.ip
            if ($mac -and $ip) {
                "$mac`t$ip`t:$stamp`t$profileName"
            }
        }
        Set-Content -LiteralPath $ethersPath -Value $etherLines -Encoding ASCII

        $dynamicPath = Join-Path $dhcpDir "dynamic"
        if (Test-Path -LiteralPath $dynamicPath) {
            $backup = Backup-File $dynamicPath
            if ($backup) { Write-Check "정상" "DHCP 동적 임대 백업" $backup }
            Set-Content -LiteralPath $dynamicPath -Value @() -Encoding ASCII
        }
        Write-Check "정상" "DHCP 정적 등록" "$($clients.Count)대 예약 IP 적용. 현재 테스트 Pi 88:a2:9e:4f:a9:b1은 10.73.0.155입니다."
    }

    Invoke-Step "3. TFTP root 설정" {
        if (-not (Test-Path -LiteralPath $tftpRoot)) {
            New-Item -ItemType Directory -Force -Path $tftpRoot | Out-Null
        }
        Invoke-RegAdd $tftpReg "RootDirectory" "REG_SZ" $tftpRoot
        Invoke-RegAdd $tftpReg "Address" "REG_SZ" $serverIp
        Invoke-RegAdd $tftpReg "Port" "REG_DWORD" "69"
        Write-Check "정상" "TFTP root" "$tftpRoot"
        Write-Check "정상" "TFTP 바인딩" "${serverIp}:69"
    }

    Invoke-Step "4. NFS export 설정" {
        $exports = "C:\Program Files\nfsd\exports"
        if (-not (Test-Path -LiteralPath (Split-Path -Parent $exports))) {
            throw "haneWIN NFS 폴더를 찾을 수 없습니다: $(Split-Path -Parent $exports)"
        }
        if (-not (Test-Path -LiteralPath $rootfsRoot)) {
            New-Item -ItemType Directory -Force -Path $rootfsRoot | Out-Null
        }
        if (Test-Path -LiteralPath $exports) {
            $backup = Backup-File $exports
            if ($backup) { Write-Check "정상" "NFS exports 백업" $backup }
        }
        $exportLines = @(
            "# Generated by RPI Netboot Manager",
            "# Raspberry Pi root filesystems are exported as /rpi/<serial>.",
            "$rootfsRoot -name:rpi -alldirs -i32 -maproot:0:0"
        )
        Set-Content -LiteralPath $exports -Value $exportLines -Encoding ASCII
        Invoke-RegAdd $nfsReg "SaveAttr" "REG_DWORD" "1"
        Write-Check "정상" "NFS export" "$rootfsRoot -> /rpi"
        Write-Check "정상" "NFS NTFS 속성" "uid/gid/권한 저장 옵션 활성화"
    }

    Invoke-Step "5. 서비스 재시작" {
        Restart-LabService "DHCPservice"
        Restart-LabService "TFTPService"
        Restart-LabService "NFSserver"
    }

    Invoke-Verify
}

function Invoke-PrepareRpi4EepromSd {
    Assert-Admin
    Invoke-Step "List disks before writing SD" {
        Invoke-Tool "tools\rpi-sd-card.ps1" @("list")
    }
    if (-not (Confirm-Destructive "This will erase the SD card at drive $SdDriveLetter`: and write the Raspberry Pi 4 network-boot EEPROM image. Zero 2 W is not a netboot target.")) {
        Write-Host "Cancelled."
        return
    }
    Invoke-Step "Write Raspberry Pi 4 EEPROM network boot image to SD" {
        Invoke-Tool "tools\rpi-sd-card.ps1" @("prepare-eeprom-network", "-Model", "pi4", "-DriveLetter", $SdDriveLetter, "-IUnderstand")
    }
}

function Invoke-PrepareSd {
    Invoke-PrepareRpi4EepromSd
}

function Invoke-SyncTftp {
    Invoke-Step "Sync generated TFTP files" {
        Invoke-Tool "tools\sync-generated-tftp.ps1" @("-Config", $Config, "-GeneratedTftp", "$Generated\tftp")
    }
}

function Invoke-CopyBootFiles {
    Invoke-Step "첫 Pi boot 파티션 파일을 TFTP 폴더로 복사" {
        Invoke-Tool "tools\copy-first-pi-boot-files.ps1" @("-Config", $Config, "-GeneratedTftp", "$Generated\tftp")
    }
}

function Invoke-PrepareRpi4Rootfs {
    Invoke-Step "RPi4 netboot rootfs 준비" {
        Invoke-Tool "tools\rootfs-helper.ps1" @("make-script", "-Config", $Config)
    }
}

function Invoke-PrepareZero2WGadgetSd {
    Invoke-Step "Zero 2 W SD boot + USB gadget 준비" {
        if (-not (Confirm-Destructive "This will patch Raspberry Pi OS boot files on drive $SdDriveLetter`: for Zero 2 W SD boot + USB gadget. It will not make Zero 2 W a netboot target.")) {
            Write-Host "Cancelled."
            return
        }
        Invoke-Tool "tools\zero2w-gadget-sd.ps1" @("apply", "-DriveLetter", $SdDriveLetter, "-Yes")
    }
}

function Invoke-Firewall {
    Assert-Admin
    Invoke-Step "Apply Windows firewall rules" {
        Invoke-Tool "$Generated\windows\01-firewall.ps1"
    }
}

function Invoke-RestoreNetwork {
    Assert-Admin
    Invoke-Step "Restore Ethernet DHCP" {
        Invoke-Tool "tools\restore-ethernet-dhcp.ps1"
    }
}

function Invoke-Verify {
    Show-Status
    Invoke-Step "8. TFTP 설정 파일 검증" {
        Invoke-Tool "tools\sync-generated-tftp.ps1" @("-Config", $Config, "-GeneratedTftp", "$Generated\tftp", "-VerifyOnly")
    }
}

function Open-Docs {
    Invoke-Step "Documents" {
        $docs = @(
            "docs\automation.md",
            "docs\progress-and-usage.md",
            "docs\sd-card-prep.md",
            "docs\rpi4-netboot-manager.md"
        )
        foreach ($doc in $docs) {
            $path = Join-Path $ProjectRoot $doc
            if (Test-Path -LiteralPath $path) {
                Write-Host $path
            }
        }
    }
}

function Show-Menu {
    while ($true) {
        Write-Host ""
        Write-Host "RPI Netboot Manager" -ForegroundColor Cyan
        Write-Host "Project: $ProjectRoot"
        Write-Host "Admin:   $(if (Test-Admin) { 'yes' } else { 'no' })"
        Write-Host ""
        Write-Host "1. Status / current state"
        Write-Host "2. Setup Windows server PC for 10.73 netboot"
        Write-Host "3. Start free Lite provider (built-in DHCP/TFTP + WinNFSd)"
        Write-Host "4. Stop free Lite provider"
        Write-Host "5. Install haneWIN trial DHCP/TFTP/NFS tools"
        Write-Host "6. Configure haneWIN boot service settings"
        Write-Host "7. Prepare RPi4 Network Boot EEPROM SD card"
        Write-Host "8. Copy first Pi boot partition files to TFTP"
        Write-Host "9. Prepare RPi4 netboot rootfs helper"
        Write-Host "10. Prepare Zero 2 W SD boot + USB gadget SD"
        Write-Host "11. Verify lab / services / generated files"
        Write-Host "12. Sync generated TFTP files to D:\tftp"
        Write-Host "13. Apply Windows firewall rules"
        Write-Host "14. Restore Ethernet DHCP"
        Write-Host "15. Show docs"
        Write-Host "0. Exit"
        Write-Host ""
        $choice = Read-Host "Select"
        try {
            switch ($choice) {
                "1" { Show-Status }
                "2" { Invoke-ServerSetup }
                "3" { Invoke-LiteProviderStart }
                "4" { Invoke-LiteProviderStop }
                "5" { Invoke-InstallServices }
                "6" { Invoke-ConfigureServices }
                "7" { Invoke-PrepareRpi4EepromSd }
                "8" { Invoke-CopyBootFiles }
                "9" { Invoke-PrepareRpi4Rootfs }
                "10" { Invoke-PrepareZero2WGadgetSd }
                "11" { Invoke-Verify }
                "12" { Invoke-SyncTftp }
                "13" { Invoke-Firewall }
                "14" { Invoke-RestoreNetwork }
                "15" { Open-Docs }
                "0" { return }
                default { Write-Host "Unknown selection." -ForegroundColor Yellow }
            }
        } catch {
            Write-Host ""
            Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        }
        Write-Host ""
        Read-Host "Press Enter to continue"
    }
}

switch ($Task) {
    "menu" { Show-Menu }
    "status" { Show-Status }
    "server-setup" { Invoke-ServerSetup }
    "lite-provider-start" { Invoke-LiteProviderStart }
    "lite-provider-stop" { Invoke-LiteProviderStop }
    "install-services" { Invoke-InstallServices }
    "configure-services" { Invoke-ConfigureServices }
    "prepare-rpi4-eeprom-sd" { Invoke-PrepareRpi4EepromSd }
    "prepare-sd" { Invoke-PrepareSd }
    "copy-boot" { Invoke-CopyBootFiles }
    "prepare-rpi4-rootfs" { Invoke-PrepareRpi4Rootfs }
    "prepare-zero2w-gadget-sd" { Invoke-PrepareZero2WGadgetSd }
    "verify" { Invoke-Verify }
    "sync-tftp" { Invoke-SyncTftp }
    "firewall" { Invoke-Firewall }
    "restore-network" { Invoke-RestoreNetwork }
    "docs" { Open-Docs }
}







