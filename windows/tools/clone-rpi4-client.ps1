param(
    [Parameter(Position = 0)]
    [ValidateSet("plan", "register", "clone", "verify", "promote-golden")]
    [string] $Command = "plan",

    [string] $Config = ".\windows\lab-10.73.json",
    [string] $GoldenSerial = "d80c0b88",
    [string] $Serial = "",
    [string] $Mac = "",
    [string] $Ip = "",
    [string] $Hostname = "",

    [ValidateSet("WinNFSdMinimal", "LinuxNFS")]
    [string] $ProviderProfile = "WinNFSdMinimal",

    [switch] $Force
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$OriginalLocation = (Get-Location).Path
if (-not [IO.Path]::IsPathRooted($Config)) {
    $Config = [IO.Path]::GetFullPath((Join-Path $OriginalLocation $Config))
}

$WindowsRoot = Split-Path -Parent $PSScriptRoot
$RepoRoot = Split-Path -Parent $WindowsRoot
Set-Location $RepoRoot

function Write-Check {
    param(
        [ValidateSet("정상", "주의", "필요", "오류")]
        [string] $Status,
        [string] $Item,
        [string] $Detail
    )
    Write-Output ("[{0}] {1} - {2}" -f $Status, $Item, $Detail)
}

function Read-ConfigObject {
    if (-not (Test-Path -LiteralPath $Config)) {
        throw "Config not found: $Config"
    }
    return Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Save-ConfigObject {
    param([object] $ConfigObject)
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $json = $ConfigObject | ConvertTo-Json -Depth 32
    [System.IO.File]::WriteAllText($Config, $json + [Environment]::NewLine, $utf8NoBom)
}

function Normalize-Serial {
    param([string] $Value)
    $clean = ($Value.Trim() -replace "^0x", "").ToLowerInvariant()
    if ($clean -notmatch "^[0-9a-f]{8}$") {
        throw "RPi4 serial은 8자리 hex여야 합니다. 입력값: $Value"
    }
    return $clean
}

function Normalize-Mac {
    param([string] $Value)
    $clean = ($Value.Trim().ToLowerInvariant() -replace "[:-]", "")
    if ($clean -notmatch "^[0-9a-f]{12}$") {
        throw "MAC 주소 형식이 아닙니다. 입력값: $Value"
    }
    return (($clean.ToCharArray() -join "") -replace "(.{2})(?!$)", '$1:')
}

function Convert-IPv4ToUInt32 {
    param([string] $Address)
    $bytes = [System.Net.IPAddress]::Parse($Address).GetAddressBytes()
    [Array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

function Convert-UInt32ToIPv4 {
    param([uint32] $Value)
    $bytes = [BitConverter]::GetBytes($Value)
    [Array]::Reverse($bytes)
    return ([System.Net.IPAddress]::new($bytes)).ToString()
}

function Resolve-ConfigChildPath {
    param([string] $Root, [string] $Child)
    $rootFull = [IO.Path]::GetFullPath($Root.TrimEnd("\") + "\")
    $childFull = [IO.Path]::GetFullPath((Join-Path $rootFull $Child))
    if (-not $childFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe path outside root. Root=$rootFull Child=$Child"
    }
    return $childFull
}

function Test-DirectoryHasItems {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return @((Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | Select-Object -First 1)).Count -gt 0
}

function Get-NextClientIp {
    param([object] $ConfigObject)
    $start = Convert-IPv4ToUInt32 ([string]$ConfigObject.dhcp_start)
    $end = Convert-IPv4ToUInt32 ([string]$ConfigObject.dhcp_end)
    $used = @{}
    foreach ($client in @($ConfigObject.clients)) {
        if ($client.ip) {
            $used[[string]$client.ip] = $true
        }
    }
    for ($candidate = $start; $candidate -le $end; $candidate++) {
        $address = Convert-UInt32ToIPv4 $candidate
        if (-not $used.ContainsKey($address)) {
            return $address
        }
    }
    throw "DHCP 예약 범위 안에 남은 IP가 없습니다: $($ConfigObject.dhcp_start)-$($ConfigObject.dhcp_end)"
}

function Get-ClientBySerial {
    param([object] $ConfigObject, [string] $ClientSerial)
    return @($ConfigObject.clients) | Where-Object { $_.serial -eq $ClientSerial } | Select-Object -First 1
}

function Get-ClientSourcePaths {
    param([object] $ConfigObject, [string] $SourceSerial)
    $templateRoot = Join-Path ([string]$ConfigObject.project_root) "templates\golden\rpi4"
    $templateBoot = Join-Path $templateRoot "bootfs"
    $templateRootfs = Join-Path $templateRoot "rootfs"

    if ((Test-DirectoryHasItems $templateBoot) -and (Test-DirectoryHasItems $templateRootfs)) {
        return [pscustomobject]@{
            Kind = "template"
            Boot = $templateBoot
            Rootfs = $templateRootfs
        }
    }

    return [pscustomobject]@{
        Kind = "live-client"
        Boot = Resolve-ConfigChildPath ([string]$ConfigObject.tftp_root) $SourceSerial
        Rootfs = Resolve-ConfigChildPath ([string]$ConfigObject.nfs_root) $SourceSerial
    }
}

function Invoke-RobocopyMirror {
    param([string] $Source, [string] $Target, [string] $Label)
    if (-not (Test-DirectoryHasItems $Source)) {
        throw "$Label source is empty or missing: $Source"
    }
    if ((Test-DirectoryHasItems $Target) -and -not $Force) {
        throw "$Label target already has files. Use -Force only when you intentionally want to mirror over it: $Target"
    }
    New-Item -ItemType Directory -Force -Path $Target | Out-Null
    $args = @($Source, $Target, "/MIR", "/SL", "/COPY:DAT", "/DCOPY:DAT", "/R:2", "/W:1", "/NP")
    & robocopy @args | Out-Host
    $code = $LASTEXITCODE
    if ($code -gt 7) {
        throw "robocopy failed for $Label with exit code $code"
    }
    Write-Check "정상" "$Label 복제" "$Source -> $Target (robocopy $code)"
}

function Get-CmdlineText {
    param([object] $ConfigObject, [string] $ClientSerial)
    $serverIp = [string]$ConfigObject.server_ip
    $alias = [string]$ConfigObject.nfs_alias
    if ([string]::IsNullOrWhiteSpace($alias)) { $alias = "/rpi" }

    switch ($ProviderProfile) {
        "LinuxNFS" {
            $linuxIp = [string]$ConfigObject.linux_nfs_server_ip
            if ([string]::IsNullOrWhiteSpace($linuxIp)) { $linuxIp = $serverIp }
            $linuxAlias = [string]$ConfigObject.linux_nfs_alias
            if ([string]::IsNullOrWhiteSpace($linuxAlias)) { $linuxAlias = "/srv/rpi-root" }
            return "console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=${linuxIp}:$linuxAlias/$ClientSerial,vers=3,tcp,nolock rw ip=dhcp rootwait elevator=deadline init=/usr/sbin/init"
        }
        default {
            return "console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=${serverIp}:$alias/$ClientSerial,vers=3 rw ip=dhcp rootwait elevator=deadline init=/usr/sbin/init"
        }
    }
}

function Set-BootIdentity {
    param([object] $ConfigObject, [string] $ClientSerial)
    $bootDir = Resolve-ConfigChildPath ([string]$ConfigObject.tftp_root) $ClientSerial
    $cmdlinePath = Join-Path $bootDir "cmdline.txt"
    if (-not (Test-Path -LiteralPath $cmdlinePath)) {
        throw "cmdline.txt not found in cloned bootfs: $cmdlinePath"
    }
    Set-Content -LiteralPath $cmdlinePath -Value (Get-CmdlineText $ConfigObject $ClientSerial) -Encoding ASCII
    Write-Check "정상" "cmdline.txt" "$cmdlinePath ($ProviderProfile)"
}

function Set-RootfsIdentity {
    param([object] $ConfigObject, [object] $Client)
    $root = Resolve-ConfigChildPath ([string]$ConfigObject.nfs_root) ([string]$Client.serial)
    $etc = Join-Path $root "etc"
    if (-not (Test-Path -LiteralPath $etc)) {
        throw "cloned rootfs has no etc directory: $root"
    }

    Set-Content -LiteralPath (Join-Path $etc "hostname") -Value ([string]$Client.hostname) -Encoding ASCII
    $hosts = @(
        "127.0.0.1 localhost",
        "127.0.1.1 $($Client.hostname)",
        "::1 localhost ip6-localhost ip6-loopback"
    )
    Set-Content -LiteralPath (Join-Path $etc "hosts") -Value $hosts -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $etc "machine-id") -Value "" -Encoding ASCII

    $dbusMachineId = Join-Path $root "var\lib\dbus\machine-id"
    if (Test-Path -LiteralPath $dbusMachineId) {
        Set-Content -LiteralPath $dbusMachineId -Value "" -Encoding ASCII
    }

    $sshDir = Join-Path $etc "ssh"
    if (Test-Path -LiteralPath $sshDir) {
        Get-ChildItem -LiteralPath $sshDir -Filter "ssh_host_*" -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    Write-Check "정상" "rootfs identity" "$root hostname/machine-id/SSH host keys reset"
}

function New-ClientRecord {
    param([object] $ConfigObject)
    if ([string]::IsNullOrWhiteSpace($Serial)) { throw "-Serial is required for $Command" }
    if ([string]::IsNullOrWhiteSpace($Mac)) { throw "-Mac is required for $Command" }

    $newSerial = Normalize-Serial $Serial
    $newMac = Normalize-Mac $Mac
    $newIp = if ([string]::IsNullOrWhiteSpace($Ip)) { Get-NextClientIp $ConfigObject } else { [string]$Ip }
    $newHostname = if ([string]::IsNullOrWhiteSpace($Hostname)) { $newSerial } else { $Hostname.Trim() }

    $sameSerial = Get-ClientBySerial $ConfigObject $newSerial
    $sameMac = @($ConfigObject.clients) | Where-Object { $_.mac -eq $newMac -and $_.serial -ne $newSerial } | Select-Object -First 1
    $sameIp = @($ConfigObject.clients) | Where-Object { $_.ip -eq $newIp -and $_.serial -ne $newSerial } | Select-Object -First 1

    if ($sameMac) { throw "MAC already belongs to $($sameMac.serial): $newMac" }
    if ($sameIp) { throw "IP already belongs to $($sameIp.serial): $newIp" }
    if ($sameSerial -and -not $Force) {
        throw "Client serial already exists. Use -Force to update it: $newSerial"
    }

    return [pscustomobject][ordered]@{
        serial = $newSerial
        mac = $newMac
        ip = $newIp
        hostname = $newHostname
        model = "pi4"
        boot_mode = "nfs"
        tftp_prefix = $newSerial
        iscsi_target_name = "rpi-$newSerial"
        iscsi_initiator_iqn = "iqn.1993-08.org.debian:01:$newSerial"
        root_uuid = ""
    }
}

function Upsert-ClientRecord {
    param([object] $ConfigObject, [object] $Client)
    $clients = @($ConfigObject.clients) | Where-Object { $_.serial -ne $Client.serial }
    $clients += $Client
    $ConfigObject.clients = @($clients | Sort-Object ip)
    Save-ConfigObject $ConfigObject
    Write-Check "정상" "client 등록" "$($Client.serial) / $($Client.mac) / $($Client.ip)"
}

function Show-Plan {
    $cfg = Read-ConfigObject
    $source = Get-ClientSourcePaths $cfg (Normalize-Serial $GoldenSerial)

    Write-Output "== RPi4 fast clone plan =="
    Write-Output "haneWIN: proof-only, production forbidden"
    Write-Output "Provider profile: $ProviderProfile"
    Write-Output "Golden source: $($source.Kind)"
    Write-Output "  bootfs: $($source.Boot)"
    Write-Output "  rootfs: $($source.Rootfs)"
    Write-Output ""
    Write-Output "New RPi4 flow:"
    Write-Output "1. EEPROM network boot setting only"
    Write-Output "2. Run clone-rpi4-client.ps1 clone -Serial <8hex> -Mac <mac>"
    Write-Output "3. Restart Lite DHCP/TFTP provider so the new reservation is active"
    Write-Output "4. Power-cycle the new RPi4"
    Write-Output ""
    Write-Output "Next free IP: $(Get-NextClientIp $cfg)"
}

function Register-Client {
    $cfg = Read-ConfigObject
    $client = New-ClientRecord $cfg
    Upsert-ClientRecord $cfg $client
}

function Clone-Client {
    $cfg = Read-ConfigObject
    $golden = Normalize-Serial $GoldenSerial
    if (-not (Get-ClientBySerial $cfg $golden)) {
        Write-Check "주의" "golden client" "$golden is not in config; using folders only"
    }

    $client = New-ClientRecord $cfg
    $source = Get-ClientSourcePaths $cfg $golden
    $targetBoot = Resolve-ConfigChildPath ([string]$cfg.tftp_root) ([string]$client.serial)
    $targetRootfs = Resolve-ConfigChildPath ([string]$cfg.nfs_root) ([string]$client.serial)

    Write-Output "== Clone RPi4 client =="
    Write-Check "정상" "source" "$($source.Kind): $golden"
    Write-Check "정상" "target" "$($client.serial) / $($client.mac) / $($client.ip)"

    Invoke-RobocopyMirror $source.Boot $targetBoot "bootfs"
    Invoke-RobocopyMirror $source.Rootfs $targetRootfs "rootfs"
    Set-BootIdentity $cfg ([string]$client.serial)
    Set-RootfsIdentity $cfg $client
    Upsert-ClientRecord $cfg $client

    Write-Check "필요" "provider reload" "관리자 GUI 또는 lite-provider.ps1 start로 DHCP 예약을 다시 반영하세요."
    Verify-Client -ConfigObject (Read-ConfigObject) -ClientSerial ([string]$client.serial)
}

function Promote-Golden {
    $cfg = Read-ConfigObject
    $golden = Normalize-Serial $GoldenSerial
    $sourceBoot = Resolve-ConfigChildPath ([string]$cfg.tftp_root) $golden
    $sourceRootfs = Resolve-ConfigChildPath ([string]$cfg.nfs_root) $golden
    $targetRoot = Join-Path ([string]$cfg.project_root) "templates\golden\rpi4"
    $targetBoot = Join-Path $targetRoot "bootfs"
    $targetRootfs = Join-Path $targetRoot "rootfs"

    Write-Output "== Promote golden RPi4 =="
    Write-Check "주의" "live rootfs" "Pi가 이 rootfs로 부팅 중이면 먼저 정상 종료한 뒤 promote하는 것이 가장 안전합니다."
    Invoke-RobocopyMirror $sourceBoot $targetBoot "golden bootfs"
    Invoke-RobocopyMirror $sourceRootfs $targetRootfs "golden rootfs"
    Write-Check "정상" "golden template" $targetRoot
}

function Verify-Client {
    param([object] $ConfigObject, [string] $ClientSerial)
    if (-not $ConfigObject) { $ConfigObject = Read-ConfigObject }
    $serialToCheck = if ([string]::IsNullOrWhiteSpace($ClientSerial)) { Normalize-Serial $Serial } else { Normalize-Serial $ClientSerial }
    $client = Get-ClientBySerial $ConfigObject $serialToCheck
    if (-not $client) { throw "client not registered: $serialToCheck" }

    $bootDir = Resolve-ConfigChildPath ([string]$ConfigObject.tftp_root) $serialToCheck
    $root = Resolve-ConfigChildPath ([string]$ConfigObject.nfs_root) $serialToCheck
    $cmdline = Join-Path $bootDir "cmdline.txt"
    $hasKernel = Test-Path -LiteralPath (Join-Path $bootDir "kernel8.img")
    $hasDtb = Test-Path -LiteralPath (Join-Path $bootDir "bcm2711-rpi-4-b.dtb")
    $hasCmdline = Test-Path -LiteralPath $cmdline
    $cmdlineOk = $false
    if ($hasCmdline) {
        $cmdlineOk = (Get-Content -LiteralPath $cmdline -Raw -Encoding ASCII) -match [regex]::Escape($serialToCheck)
    }
    $hasInit = (Test-Path -LiteralPath (Join-Path $root "usr\sbin\init")) -or
        (Test-Path -LiteralPath (Join-Path $root "sbin\init")) -or
        (Test-Path -LiteralPath (Join-Path $root "lib\systemd\systemd"))
    $hasShell = Test-Path -LiteralPath (Join-Path $root "bin\sh")

    Write-Output "== Verify RPi4 client =="
    Write-Check $(if ($client) { "정상" } else { "오류" }) "config" "$($client.serial) / $($client.mac) / $($client.ip)"
    Write-Check $(if ($hasKernel) { "정상" } else { "오류" }) "kernel8.img" (Join-Path $bootDir "kernel8.img")
    Write-Check $(if ($hasDtb) { "정상" } else { "오류" }) "RPi4 dtb" (Join-Path $bootDir "bcm2711-rpi-4-b.dtb")
    Write-Check $(if ($cmdlineOk) { "정상" } else { "오류" }) "cmdline serial" $cmdline
    Write-Check $(if ($hasInit) { "정상" } else { "오류" }) "rootfs init" $root
    Write-Check $(if ($hasShell) { "정상" } else { "오류" }) "rootfs shell" $root

    if (-not ($client -and $hasKernel -and $hasDtb -and $cmdlineOk -and $hasInit -and $hasShell)) {
        throw "verify failed for $serialToCheck"
    }
}

switch ($Command) {
    "plan" { Show-Plan }
    "register" { Register-Client }
    "clone" { Clone-Client }
    "verify" { Verify-Client -ConfigObject (Read-ConfigObject) -ClientSerial $Serial }
    "promote-golden" { Promote-Golden }
}
