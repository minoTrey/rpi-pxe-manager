param(
    [ValidateSet("menu", "status", "server-setup", "lite-provider-start", "prepare-rpi4-os-sd", "prepare-rpi4-eeprom-sd", "prepare-sd", "prepare-zero2w-gadget-sd", "verify", "docs")]
    [string] $Task = "menu",

    [string] $Config = ".\lab-10.73.json",
    [string] $LegacyBackup = "C:\Users\test\Documents\workspace\rpi-pxe-manager\clients_backup.json",
    [string] $Generated = ".\generated\lab-10.73",
    [string] $StorageRoot = "",
    [string] $SdDriveLetter = "S",
    [int] $SdDiskNumber = -1,
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
        throw "This task needs administrator rights. Run RPI-Netboot-Manager.exe and approve the UAC prompt."
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

function Normalize-StorageRoot {
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = "D:\"
    }
    $full = [System.IO.Path]::GetFullPath($Path.Trim())
    $trimmed = $full.TrimEnd([char[]]@("\", "/"))
    if ($trimmed -match '^[A-Za-z]:$') {
        return ($trimmed + "\")
    }
    return $trimmed
}

function Get-StorageLayout {
    param([object] $ConfigObject = $null)

    $root = $StorageRoot
    $overrideStorage = -not [string]::IsNullOrWhiteSpace($root)
    if ([string]::IsNullOrWhiteSpace($root) -and $ConfigObject -and $ConfigObject.project_root) {
        $root = [string]$ConfigObject.project_root
    }
    $root = Normalize-StorageRoot $root

    $tftp = if (-not $overrideStorage -and $ConfigObject -and $ConfigObject.tftp_root) { [string]$ConfigObject.tftp_root } else { Join-Path $root "tftp" }
    $rootfs = if (-not $overrideStorage -and $ConfigObject -and $ConfigObject.nfs_root) { [string]$ConfigObject.nfs_root } else { Join-Path $root "rootfs" }
    $iscsi = if (-not $overrideStorage -and $ConfigObject -and $ConfigObject.iscsi_root) { [string]$ConfigObject.iscsi_root } else { Join-Path $root "iscsi" }

    [pscustomobject]@{
        ProjectRoot = $root
        TftpRoot = $tftp
        RootfsRoot = $rootfs
        IscsiRoot = $iscsi
        Downloads = Join-Path $root "downloads"
        Logs = Join-Path $root "logs"
        Tools = Join-Path $root "tools"
        NetbootTools = Join-Path (Join-Path $root "tools") "rpi-netboot"
    }
}

function Get-ProjectDownloadCache {
    return (Join-Path $ProjectRoot "cache\downloads")
}

function Update-ConfigStorage {
    param([object] $ConfigObject, [object] $Layout)
    $ConfigObject.project_root = $Layout.ProjectRoot
    $ConfigObject.tftp_root = $Layout.TftpRoot
    $ConfigObject.nfs_root = $Layout.RootfsRoot
    $ConfigObject.iscsi_root = $Layout.IscsiRoot
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
    $storage = Get-StorageLayout $cfg
    $routerAddress = if ($cfg -and $cfg.router_ip) { [string]$cfg.router_ip } else { "10.73.0.1" }
    $serverAddressExpected = if ($cfg -and $cfg.server_ip) { [string]$cfg.server_ip } else { "10.73.0.10" }

    Write-Output "상태 확인은 Raspberry Pi 4 네트워크 부팅 전에 필요한 7가지를 봅니다."
    Write-Output "정책: 네트워크 부팅 대상은 RPi4만입니다. Zero 2 W는 SD boot + USB gadget으로 준비합니다."
    Write-Output "1. 저장소와 S: SD카드"
    Write-Output "2. 서버 PC 이더넷 IP와 공유기 연결"
    Write-Output "3. lab 설정 파일과 TFTP/rootfs 폴더"
    Write-Output "4. DHCP/TFTP/NFS 서비스 포트"
    Write-Output "5. 부팅 서비스 실행 상태"
    Write-Output "6. 저장소 정리 후보"
    Write-Output "7. 지금 다음에 눌러야 할 버튼"

    Invoke-Step "1. 저장소 / SD카드" {
        $root = [string]$storage.ProjectRoot
        $rootDrive = Split-Path -Qualifier $root
        $volume = $null
        if ($rootDrive -match '^[A-Za-z]:$') {
            $volume = Get-Volume -DriveLetter $rootDrive.TrimEnd(":") -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $root -PathType Container) {
            $detail = if ($volume) {
                "$root, $($volume.FileSystemLabel) $($volume.FileSystem) $($volume.DriveType), 남은 공간 $(Format-Size ([UInt64]$volume.SizeRemaining))"
            } else {
                $root
            }
            Write-Check "정상" "저장소" $detail
        } else {
            Write-Check "필요" "저장소" "$root 폴더가 없습니다. '서버 PC 준비'를 누르세요."
        }

        $sd = Get-Volume -DriveLetter $SdDriveLetter -ErrorAction SilentlyContinue
        if ($sd -and $sd.DriveType -eq "Removable") {
            Write-Check "정상" "$SdDriveLetter`: SD카드 후보" "$($sd.FileSystem) 이동식 드라이브, 크기 $(Format-Size ([UInt64]$sd.Size))"
        } elseif ($sd) {
            Write-Check "주의" "$SdDriveLetter`: 드라이브" "이동식 드라이브가 아닙니다. OS SD 쓰기 전에 대상이 맞는지 확인하세요."
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
                Write-Check "정상" "SD카드 후보" "작은 FAT32 이동식 파티션 $(Format-Size ([UInt64]$eepromVolume.Size)) ($letter). 물리 디스크 선택 화면에서 최종 대상을 확인하세요."
            } else {
                Write-Check "주의" "$SdDriveLetter`: SD카드" "현재 보이지 않습니다. OS SD를 쓸 때 다시 꽂고 상태 확인을 다시 누르세요."
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
            Write-Check "오류" "서버 IP" "유선 이더넷에 $serverAddressExpected/24가 필요합니다. '서버 PC 준비'를 누르세요."
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
            Write-Check "오류" "lab 설정" "$Config 파일이 없습니다. '서버 PC 준비'가 필요합니다."
            return
        }

        Write-Check "정상" "lab 설정" "등록된 RPi4 $(@($cfg.clients).Count)대, 서버 IP $($cfg.server_ip), 공유기 $($cfg.router_ip), 방식 $($cfg.method)"

        foreach ($folder in @($storage.TftpRoot, $storage.RootfsRoot, $storage.Downloads, $storage.Logs, $storage.Tools)) {
            if (Test-Folder $folder) {
                Write-Check "정상" $folder "폴더 있음"
            } else {
                Write-Check "필요" $folder "폴더 없음. '서버 PC 준비'를 누르세요."
            }
        }

        $tftpDirs = Get-FolderCount $storage.TftpRoot
        $rootfsDirs = Get-FolderCount $storage.RootfsRoot
        Write-Check "정상" "TFTP 클라이언트 폴더" "${tftpDirs}개. 각 Pi serial별 폴더입니다."
        Write-Check "정상" "rootfs 클라이언트 폴더" "${rootfsDirs}개. 실제 등록된 RPi4와 맞는지 아래 정리 후보를 확인합니다."

        $bootFiles = 0
        if (Test-Folder $storage.TftpRoot) {
            $bootFileMatches = @(Get-ChildItem -LiteralPath $storage.TftpRoot -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "^(start4\.elf|fixup4\.dat|kernel.*\.img|.*\.dtb)$" })
            $bootFiles = $bootFileMatches.Count
        }
        if ($bootFiles -gt 0) {
            Write-Check "정상" "TFTP 실제 부팅 파일" "$($bootFiles)개 발견"
        } else {
            Write-Check "필요" "TFTP 실제 부팅 파일" "현재 cmdline/config 중심입니다. 첫 Pi의 boot partition 파일을 $($storage.TftpRoot)\<serial>에 채워야 합니다."
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
        $provisionListeners = @(Get-TcpListeners 8088)
        if ($provisionListeners.Count -gt 0) {
            $addresses = @($provisionListeners | ForEach-Object { $_.LocalAddress }) -join ", "
            Write-Check "정상" "Provision TCP 8088" "OS SD 첫 부팅 리포트 수신 대기 중입니다. 주소: $addresses"
        } else {
            Write-Check "필요" "Provision TCP 8088" "새 RPi 시리얼/MAC 자동 수집 리스너가 대기 중이 아닙니다. '부팅 서비스 시작'을 누르세요."
        }
        $nfsListeners = @(Get-TcpListeners 2049)
        if ($nfsListeners.Count -gt 0) {
            $addresses = @($nfsListeners | ForEach-Object { $_.LocalAddress }) -join ", "
            Write-Check "정상" "NFS TCP 2049" "서비스가 대기 중입니다. 주소: $addresses"
        } else {
            Write-Check "필요" "NFS TCP 2049" "아직 대기 중인 서비스가 없습니다. rootfs 부팅에는 NFS 설정이 필요합니다."
        }
    }

    Invoke-Step "5. 부팅 서비스 상태" {
        $litePidPath = Join-Path $storage.NetbootTools "run\rpi-boot-lite.pid"
        $nfsPidPath = Join-Path $storage.NetbootTools "run\winnfsd.pid"
        $liteExe = Join-Path $storage.NetbootTools "bin\RpiBootServiceLite.exe"
        $nfsExe = Join-Path $storage.NetbootTools "winnfsd\WinNFSd.exe"

        if (Test-Path -LiteralPath $liteExe) {
            Write-Check "정상" "내장 DHCP/TFTP 파일" $liteExe
        } else {
            Write-Check "필요" "내장 DHCP/TFTP 파일" "아직 준비되지 않았습니다. '부팅 서비스 시작'을 누르면 자동 빌드됩니다."
        }

        if (Test-Path -LiteralPath $nfsExe) {
            Write-Check "정상" "rootfs 서비스 파일" "준비됨"
        } else {
            Write-Check "필요" "rootfs 서비스 파일" "아직 준비되지 않았습니다. '부팅 서비스 시작'을 누르면 준비합니다."
        }

        foreach ($entry in @(
            @{ Name = "내장 DHCP/TFTP"; Path = $litePidPath },
            @{ Name = "rootfs 서비스"; Path = $nfsPidPath }
        )) {
            if (Test-Path -LiteralPath $entry.Path) {
                $pidText = (Get-Content -LiteralPath $entry.Path -Raw -ErrorAction SilentlyContinue).Trim()
                $proc = if ($pidText) { Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue } else { $null }
                if ($proc) {
                    Write-Check "정상" $entry.Name "실행 중 PID $pidText"
                } else {
                    Write-Check "주의" $entry.Name "PID 파일은 있지만 프로세스가 없습니다. '부팅 서비스 시작'을 다시 누르세요."
                }
            } else {
                Write-Check "필요" $entry.Name "실행 중이 아닙니다. '부팅 서비스 시작'을 누르세요."
            }
        }
    }

    Invoke-Step "6. 저장소 정리 후보" {
        if (-not $cfg) {
            Write-Check "주의" "정리 후보" "lab 설정이 없어 저장소 정리 후보를 판단하지 않았습니다."
        } else {
            $registered = @{}
            foreach ($client in @($cfg.clients)) {
                if ($client.serial) { $registered[[string]$client.serial] = $true }
            }
            foreach ($root in @([string]$storage.TftpRoot, [string]$storage.RootfsRoot)) {
                if (Test-Folder $root) {
                    $stale = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                        Where-Object { -not $registered.ContainsKey($_.Name) })
                    if ($stale.Count -gt 0) {
                        $sample = @($stale | Select-Object -First 5 -ExpandProperty Name) -join ", "
                        Write-Check "주의" "$root 정리 후보" "$($stale.Count)개가 현재 등록 목록에 없습니다. 예: $sample"
                    } else {
                        Write-Check "정상" "$root 정리 후보" "등록되지 않은 클라이언트 폴더 없음"
                    }
                }
            }

            foreach ($folder in @((Join-Path $storage.ProjectRoot "backups"), $storage.IscsiRoot, (Join-Path $storage.ProjectRoot "templates\golden"))) {
                if (Test-Folder $folder -and (Get-FileCount $folder) -eq 0 -and (Get-FolderCount $folder) -eq 0) {
                    Write-Check "주의" $folder "현재 비어 있습니다. 운영에 필요해질 때 다시 만들 수 있습니다."
                }
            }
        }
    }

    Invoke-Step "7. 다음에 할 일" {
        if (-not (Test-Admin)) {
            Write-Check "주의" "관리자 권한" "설치/SD 쓰기/방화벽 작업을 누르면 관리자 모드로 다시 열어야 합니다."
        }
        Write-Output "작업 흐름:"
        Write-Output "1. 상태 확인으로 저장소와 네트워크를 확인"
        Write-Output "2. 서버 PC 준비로 이더넷과 기본 폴더를 맞춤"
        Write-Output "3. 부팅 서비스 시작"
        Write-Output "4. RPi4 OS SD 작성 후 새 Pi를 SD로 부팅해 시리얼/MAC 자동 수집"
        Write-Output "5. 새 RPi4 등록/복제에서 감지된 값 확인 후 등록"
        Write-Output "6. SD를 제거하고 새 RPi4 전원을 다시 넣어 네트워크 부팅 확인"
    }
}

function Invoke-ServerSetup {
    Assert-Admin
    $cfg = if (Test-Path -LiteralPath $Config) { Read-ConfigObject } else { $null }
    $storage = Get-StorageLayout $cfg
    Invoke-Step "Set Ethernet to 10.73.0.10" {
        Invoke-Tool "tools\set-ethernet-10.73.ps1"
    }
    Invoke-Step "Create storage folders" {
        foreach ($path in @($storage.ProjectRoot, $storage.TftpRoot, $storage.RootfsRoot, $storage.Downloads, $storage.Logs, $storage.Tools)) {
            New-Item -ItemType Directory -Force -Path $path | Out-Null
        }
        Get-ChildItem -Force $storage.ProjectRoot | Select-Object Name,Mode,LastWriteTime | Format-Table -AutoSize
    }
    Invoke-Step "Validate lab config and plan" {
        if (-not (Test-Path -LiteralPath $Config)) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\rpi-win-netboot.ps1" init `
                -Config $Config `
                -Method windows-lite-nfs `
                -ServerIp 10.73.0.10 `
                -RouterIp 10.73.0.1 `
                -ProjectRoot $storage.ProjectRoot `
                -TftpRoot $storage.TftpRoot `
                -RootfsRoot $storage.RootfsRoot `
                -IscsiRoot $storage.IscsiRoot
            if ($LASTEXITCODE -ne 0) { throw "init failed" }
        } elseif ($StorageRoot) {
            Update-ConfigStorage $cfg $storage
            $cfg | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Config -Encoding UTF8
        }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\rpi-win-netboot.ps1" generate -Config $Config -Out $Generated
        if ($LASTEXITCODE -ne 0) { throw "generate failed" }
    }
    Invoke-Firewall
    Invoke-Verify
}

function Invoke-LiteProviderStart {
    Invoke-Step "부팅 서비스 준비/시작" {
        Invoke-Tool "tools\lite-provider.ps1" @("start", "-Config", $Config)
    }
}

function Invoke-PrepareRpi4EepromSd {
    Assert-Admin
    $cfg = if (Test-Path -LiteralPath $Config) { Read-ConfigObject } else { $null }
    $cache = Get-ProjectDownloadCache
    $targetText = if ($SdDiskNumber -ge 0) { "PhysicalDrive$SdDiskNumber" } else { "drive $SdDriveLetter`:" }
    Invoke-Step "List disks before writing SD" {
        Invoke-Tool "tools\rpi-sd-card.ps1" @("list", "-CacheDir", $cache)
    }
    if (-not (Confirm-Destructive "This will erase the selected SD target $targetText and write the Raspberry Pi 4 network-boot EEPROM image. Zero 2 W is not a netboot target.")) {
        Write-Host "Cancelled."
        return
    }
    Invoke-Step "Write Raspberry Pi 4 EEPROM network boot image to SD" {
        $args = @("prepare-eeprom-network", "-Model", "pi4", "-CacheDir", $cache, "-IUnderstand")
        if ($SdDiskNumber -ge 0) {
            $args += @("-DiskNumber", ([string]$SdDiskNumber))
        } else {
            $args += @("-DriveLetter", $SdDriveLetter)
        }
        Invoke-Tool "tools\rpi-sd-card.ps1" $args
    }
}

function Invoke-PrepareRpi4OsSd {
    Assert-Admin
    $cache = Get-ProjectDownloadCache
    $targetText = if ($SdDiskNumber -ge 0) { "PhysicalDrive$SdDiskNumber" } else { "drive $SdDriveLetter`:" }
    Invoke-Step "List disks before writing SD" {
        Invoke-Tool "tools\rpi-sd-card.ps1" @("list", "-CacheDir", $cache)
    }
    if (-not (Confirm-Destructive "This will erase the selected SD target $targetText and write Raspberry Pi OS Lite 64-bit Trixie 2026-04-21 with the first-boot provisioning reporter. Use this OS SD to boot the Pi so the manager can collect serial/MAC/EEPROM boot order automatically.")) {
        Write-Host "Cancelled."
        return
    }
    Invoke-Step "Write Raspberry Pi OS Lite 64-bit Trixie image to SD" {
        $args = @("prepare-rpios-lite-trixie", "-CacheDir", $cache, "-IUnderstand")
        if ($SdDiskNumber -ge 0) {
            $args += @("-DiskNumber", ([string]$SdDiskNumber))
        } else {
            $args += @("-DriveLetter", $SdDriveLetter)
        }
        Invoke-Tool "tools\rpi-sd-card.ps1" $args
    }
}

function Invoke-PrepareSd {
    Invoke-PrepareRpi4OsSd
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
        Write-Host "3. Start boot services"
        Write-Host "4. Prepare Raspberry Pi OS Lite Trixie SD card"
        Write-Host "5. Prepare Zero 2 W SD boot + USB gadget SD"
        Write-Host "6. Verify lab / services / generated files"
        Write-Host "7. Show docs"
        Write-Host "0. Exit"
        Write-Host ""
        $choice = Read-Host "Select"
        try {
            switch ($choice) {
                "1" { Show-Status }
                "2" { Invoke-ServerSetup }
                "3" { Invoke-LiteProviderStart }
                "4" { Invoke-PrepareRpi4OsSd }
                "5" { Invoke-PrepareZero2WGadgetSd }
                "6" { Invoke-Verify }
                "7" { Open-Docs }
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
    "prepare-rpi4-os-sd" { Invoke-PrepareRpi4OsSd }
    "prepare-rpi4-eeprom-sd" { Invoke-PrepareRpi4EepromSd }
    "prepare-sd" { Invoke-PrepareSd }
    "prepare-zero2w-gadget-sd" { Invoke-PrepareZero2WGadgetSd }
    "verify" { Invoke-Verify }
    "docs" { Open-Docs }
}







