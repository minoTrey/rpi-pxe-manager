param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet("init", "add-client", "import-legacy", "generate", "doctor", "sources", "sd-list", "sd-download-eeprom-network", "sd-prepare-eeprom-network", "sd-write-image")]
    [string] $Command,

    [string] $Config = "rpi-netboot.json",
    [ValidateSet("hanewin-nfs", "windows-server-nfs", "windows-server-iscsi")]
    [string] $Method = "hanewin-nfs",
    [string] $ServerIp = "192.168.1.10",
    [string] $RouterIp = "192.168.1.1",
    [string] $DnsServer = "",
    [string] $SubnetMask = "255.255.255.0",
    [string] $DhcpStart = "",
    [string] $DhcpEnd = "",
    [string] $ProjectRoot = "D:\",
    [string] $TftpRoot = "",
    [string] $RootfsRoot = "",
    [string] $IscsiRoot = "",

    [string] $Serial,
    [string] $Mac,
    [string] $Ip,
    [string] $Hostname,
    [ValidateSet("nfs", "iscsi")]
    [string] $BootMode = "nfs",
    [string] $Backup,
    [string] $Out = "generated",

    [ValidateSet("pi4", "pi5")]
    [string] $PiModel = "pi4",
    [int] $DiskNumber = -1,
    [string] $DriveLetter = "",
    [string] $Image = "",
    [string] $CacheDir = "D:\downloads",
    [int] $MaxDiskSizeGB = 64,
    [switch] $IUnderstand,
    [switch] $NoVerify,
    [switch] $AllowNonUsb,
    [switch] $AllowLargeDisk
)

$ErrorActionPreference = "Stop"

$Option43Bytes = @(
    0x06, 0x01, 0x03, 0x0A, 0x04, 0x00, 0x50, 0x58,
    0x45, 0x09, 0x14, 0x00, 0x00, 0x11, 0x52, 0x61,
    0x73, 0x70, 0x62, 0x65, 0x72, 0x72, 0x79, 0x20,
    0x50, 0x69, 0x20, 0x42, 0x6F, 0x6F, 0x74, 0xFF
)

function Normalize-Mac {
    param([Parameter(Mandatory = $true)][string] $Value)
    $clean = ($Value -replace '[^0-9a-fA-F]', '').ToLowerInvariant()
    if ($clean.Length -ne 12) {
        throw "MAC address must contain 12 hex digits: $Value"
    }
    $pairs = for ($i = 0; $i -lt 12; $i += 2) { $clean.Substring($i, 2) }
    return ($pairs -join ":")
}

function Get-DhcpClientId {
    param([string] $Value)
    return (Normalize-Mac $Value).Replace(":", "-")
}

function Safe-Name {
    param([string] $Value, [string] $Fallback = "rpi")
    $clean = (($Value | ForEach-Object { "$_" }).Trim() -replace '[^A-Za-z0-9_.-]+', '-').Trim("-")
    if ([string]::IsNullOrWhiteSpace($clean)) { return $Fallback }
    return $clean
}

function ConvertTo-IpUInt32 {
    param([string] $Address)
    $bytes = [System.Net.IPAddress]::Parse($Address).GetAddressBytes()
    [Array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

function ConvertFrom-IpUInt32 {
    param([uint32] $Value)
    $bytes = [BitConverter]::GetBytes($Value)
    [Array]::Reverse($bytes)
    return ([System.Net.IPAddress]::new($bytes)).ToString()
}

function Get-ScopeId {
    param([string] $Address, [string] $Mask)
    $network = (ConvertTo-IpUInt32 $Address) -band (ConvertTo-IpUInt32 $Mask)
    return ConvertFrom-IpUInt32 $network
}

function Get-CidrPrefix {
    param([string] $Mask)
    $value = ConvertTo-IpUInt32 $Mask
    $bits = [Convert]::ToString($value, 2).PadLeft(32, "0")
    return ($bits.ToCharArray() | Where-Object { $_ -eq "1" }).Count
}

function Normalize-WindowsPath {
    param([string] $Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Path value must not be empty."
    }
    $full = [System.IO.Path]::GetFullPath($Value.Trim())
    $trimmed = $full.TrimEnd([char[]]@("\", "/"))
    if ($trimmed -match '^[A-Za-z]:$') {
        return ($trimmed + "\")
    }
    return $trimmed
}

function New-Client {
    param(
        [string] $Serial,
        [string] $Mac,
        [string] $Ip,
        [string] $Hostname,
        [string] $BootMode = "nfs"
    )
    $safeSerial = (Safe-Name $Serial).ToLowerInvariant()
    $safeHost = Safe-Name $Hostname "rpi-$($safeSerial.Substring([Math]::Max(0, $safeSerial.Length - 6)))"
    return [ordered]@{
        serial = $safeSerial
        mac = Normalize-Mac $Mac
        ip = $Ip
        hostname = $safeHost
        model = "pi4"
        boot_mode = $BootMode
        tftp_prefix = $safeSerial
        iscsi_target_name = "rpi-$safeHost"
        iscsi_initiator_iqn = "iqn.1993-08.org.debian:01:$safeHost"
        root_uuid = ""
    }
}

function Move-IpToServerSubnet {
    param([string] $ClientIp, [string] $ServerIp)
    $clientParts = $ClientIp.Split(".")
    $serverParts = $ServerIp.Split(".")
    if ($clientParts.Count -ne 4 -or $serverParts.Count -ne 4) {
        return $ClientIp
    }
    return "$($serverParts[0]).$($serverParts[1]).$($serverParts[2]).$($clientParts[3])"
}

function New-HostConfig {
    param(
        [string] $Method,
        [string] $ServerIp,
        [string] $RouterIp,
        [string] $DnsServer,
        [string] $SubnetMask,
        [string] $DhcpStart,
        [string] $DhcpEnd,
        [string] $ProjectRoot,
        [string] $TftpRoot = "",
        [string] $RootfsRoot = "",
        [string] $IscsiRoot = "",
        [object[]] $Clients = @()
    )
    $root = Normalize-WindowsPath $ProjectRoot
    if ([string]::IsNullOrWhiteSpace($TftpRoot)) {
        $TftpRoot = Join-Path $root "tftp"
    } else {
        $TftpRoot = Normalize-WindowsPath $TftpRoot
    }
    if ([string]::IsNullOrWhiteSpace($RootfsRoot)) {
        $RootfsRoot = Join-Path $root "rootfs"
    } else {
        $RootfsRoot = Normalize-WindowsPath $RootfsRoot
    }
    if ([string]::IsNullOrWhiteSpace($IscsiRoot)) {
        $IscsiRoot = Join-Path $root "iscsi"
    } else {
        $IscsiRoot = Normalize-WindowsPath $IscsiRoot
    }
    if ([string]::IsNullOrWhiteSpace($DnsServer)) {
        $DnsServer = $RouterIp
    }
    $octets = $ServerIp.Split(".")
    if ($octets.Count -eq 4) {
        $base = "$($octets[0]).$($octets[1]).$($octets[2])"
        if ([string]::IsNullOrWhiteSpace($DhcpStart)) { $DhcpStart = "$base.100" }
        if ([string]::IsNullOrWhiteSpace($DhcpEnd)) { $DhcpEnd = "$base.199" }
    }
    return [ordered]@{
        name = "rpi-netboot-windows"
        method = $Method
        server_ip = $ServerIp
        router_ip = $RouterIp
        dns_server = $DnsServer
        subnet_mask = $SubnetMask
        dhcp_start = $DhcpStart
        dhcp_end = $DhcpEnd
        project_root = $root
        tftp_root = $TftpRoot
        nfs_root = $RootfsRoot
        nfs_alias = "/rpi"
        iscsi_root = $IscsiRoot
        vhdx_size_gb = 32
        clients = @($Clients)
    }
}

function Read-Json {
    param([string] $Path)
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Save-Json {
    param([object] $Value, [string] $Path)
    $targetParent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($targetParent)) {
        New-Item -ItemType Directory -Force -Path $targetParent | Out-Null
    }
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-SdCardTool {
    param([string] $SdCommand)

    $sdScriptPath = Join-Path $PSScriptRoot "tools\rpi-sd-card.ps1"
    $sdArgs = @(
        $SdCommand,
        "-Model", $PiModel,
        "-CacheDir", $CacheDir,
        "-MaxDiskSizeGB", $MaxDiskSizeGB
    )
    if ($DiskNumber -ge 0) { $sdArgs += @("-DiskNumber", $DiskNumber) }
    if (-not [string]::IsNullOrWhiteSpace($DriveLetter)) { $sdArgs += @("-DriveLetter", $DriveLetter) }
    if (-not [string]::IsNullOrWhiteSpace($Image)) { $sdArgs += @("-Image", $Image) }
    if ($IUnderstand) { $sdArgs += "-IUnderstand" }
    if ($NoVerify) { $sdArgs += "-NoVerify" }
    if ($AllowNonUsb) { $sdArgs += "-AllowNonUsb" }
    if ($AllowLargeDisk) { $sdArgs += "-AllowLargeDisk" }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sdScriptPath @sdArgs
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

function Write-Text {
    param([string] $Path, [string] $Text)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    ($Text.TrimEnd() + [Environment]::NewLine) | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-Option43DecimalText {
    return ($Option43Bytes | ForEach-Object { [int] $_ }) -join " "
}

function Get-Option43PsText {
    return "[byte[]](" + (($Option43Bytes | ForEach-Object { "0x{0:X2}" -f $_ }) -join ",") + ")"
}

function Get-NfsCmdline {
    param([object] $ConfigObject, [object] $Client)
    return "console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=$($ConfigObject.server_ip):$($ConfigObject.nfs_alias)/$($Client.serial),vers=3,tcp rw ip=dhcp rootwait elevator=deadline"
}

function Get-IscsiCmdline {
    param([object] $ConfigObject, [object] $Client)
    $uuid = if ($Client.root_uuid) { $Client.root_uuid } else { "REPLACE_WITH_ROOT_FILESYSTEM_UUID" }
    return "console=serial0,115200 console=tty1 ip=dhcp rootwait rw ISCSI_INITIATOR=$($Client.iscsi_initiator_iqn) ISCSI_TARGET_NAME=iqn.1991-05.com.microsoft:$($Client.iscsi_target_name) ISCSI_TARGET_IP=$($ConfigObject.server_ip) root=UUID=$uuid"
}

function Get-ResearchText {
@"
# Research Notes

Windows support is feasible because Raspberry Pi netboot requires standard network services, not Linux specifically. The hard part is matching the services and Linux filesystem semantics.

Primary sources:

- Raspberry Pi network boot: https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#network-booting
- Raspberry Pi bootloader/TFTP prefix settings: https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#raspberry-pi-bootloader-configuration
- Windows Server NFS: https://learn.microsoft.com/en-us/windows-server/storage/nfs/deploy-nfs
- Windows Server iSCSI Target: https://learn.microsoft.com/en-us/windows-server/storage/iscsi/iscsi-target-server
- Windows Server DHCP PowerShell: https://learn.microsoft.com/en-us/powershell/module/dhcpserver/set-dhcpserverv4optionvalue
- Tftpd64: https://github.com/PJO2/tftpd64
- WinNFSd: https://github.com/winnfsd/winnfsd
- haneWIN Raspberry Pi from Windows: https://hanewin.net/rpi/remote-rpi-boot.htm
- haneWIN Raspberry Pi OS from Windows: https://hanewin.net/rpi/remote-rpi-boot2.htm
"@
}

function Invoke-Generate {
    param([object] $ConfigObject, [string] $OutputRoot)
    $scope = Get-ScopeId $ConfigObject.server_ip $ConfigObject.subnet_mask
    $cidr = Get-CidrPrefix $ConfigObject.subnet_mask
    $option43Decimal = Get-Option43DecimalText
    $option43Ps = Get-Option43PsText
    $clientCount = @($ConfigObject.clients).Count

    Write-Text "$OutputRoot\README_NEXT_STEPS.md" @"
# Generated Raspberry Pi Windows Netboot Plan

Method: ``$($ConfigObject.method)``

This directory is a plan, not an automatic network mutation. Review the files, run PowerShell as Administrator where required, and test on an isolated wired lab network before touching a production LAN.

## Apply Order

1. Create Windows folders: ``$($ConfigObject.project_root)``, ``$($ConfigObject.tftp_root)``, ``$($ConfigObject.nfs_root)``, ``$($ConfigObject.iscsi_root)``.
2. Copy Raspberry Pi boot partition files into each ``tftp/<prefix>`` folder. Keep or merge the generated ``cmdline.txt`` and ``config.txt``.
3. Configure DHCP/TFTP with ``windows/02-dhcp-windows-server.ps1`` or ``windows/hanewin-dhcp-profile.md``.
4. Configure NFS or iSCSI with the generated Windows files.
5. Open firewall ports with ``windows/01-firewall.ps1``.
6. Materialize the Linux root filesystem from a Pi/Linux helper using ``pi/materialize-rootfs.sh``.

## Network Values

- Server IP: ``$($ConfigObject.server_ip)``
- DHCP scope: ``$scope/$cidr``
- Router: ``$($ConfigObject.router_ip)``
- DNS: ``$($ConfigObject.dns_server)``
- Subnet mask: ``$($ConfigObject.subnet_mask)``
- Clients: ``$clientCount``

## Important Constraints

- Raspberry Pi netboot uses the built-in wired Ethernet adapter.
- Early boot needs DHCP and TFTP before Linux starts.
- Linux root should be NFSv3 or an initramfs-supported root such as iSCSI.
- Ordinary Windows extraction of an ext4 root partition does not preserve enough Linux metadata.
"@

    Write-Text "$OutputRoot\RESEARCH_NOTES.md" (Get-ResearchText)

    Write-Text "$OutputRoot\windows\01-firewall.ps1" @"
# Run in an elevated PowerShell session.
New-NetFirewallRule -DisplayName "RPI Netboot DHCP" -Direction Inbound -Protocol UDP -LocalPort 67,68 -Action Allow -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "RPI Netboot TFTP" -Direction Inbound -Protocol UDP -LocalPort 69 -Action Allow -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "RPI Netboot NFS RPC" -Direction Inbound -Protocol TCP -LocalPort 111,2049 -Action Allow -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "RPI Netboot NFS RPC UDP" -Direction Inbound -Protocol UDP -LocalPort 111,2049 -Action Allow -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "RPI Netboot iSCSI" -Direction Inbound -Protocol TCP -LocalPort 3260 -Action Allow -ErrorAction SilentlyContinue
Write-Host "Firewall rules added for $($ConfigObject.name) on $($ConfigObject.server_ip)."
Write-Host "If your TFTP/NFS tool uses dynamic high ports, allow the program executable too."
"@

    $reservationLines = @()
    foreach ($client in @($ConfigObject.clients)) {
        $clientId = Get-DhcpClientId $client.mac
        $reservationLines += "Add-DhcpServerv4Reservation -ScopeId '$scope' -IPAddress '$($client.ip)' -ClientId '$clientId' -Name '$($client.hostname)' -Description 'Raspberry Pi $($client.hostname)' -ErrorAction SilentlyContinue"
    }
    if ($reservationLines.Count -eq 0) { $reservationLines = @("# Add clients first, then regenerate.") }
    Write-Text "$OutputRoot\windows\02-dhcp-windows-server.ps1" @"
# Run in an elevated PowerShell session on Windows Server.
# Review before running. Existing DHCP scopes/options may conflict.

`$ScopeId = '$scope'
`$StartRange = '$($ConfigObject.dhcp_start)'
`$EndRange = '$($ConfigObject.dhcp_end)'
`$SubnetMask = '$($ConfigObject.subnet_mask)'
`$Router = '$($ConfigObject.router_ip)'
`$DnsServer = '$($ConfigObject.dns_server)'
`$TftpServer = '$($ConfigObject.server_ip)'
`$Option43 = $option43Ps

Install-WindowsFeature -Name DHCP -IncludeManagementTools

if (-not (Get-DhcpServerv4Scope -ScopeId `$ScopeId -ErrorAction SilentlyContinue)) {
    Add-DhcpServerv4Scope -Name '$($ConfigObject.name)' -StartRange `$StartRange -EndRange `$EndRange -SubnetMask `$SubnetMask
}

Set-DhcpServerv4OptionValue -ScopeId `$ScopeId -Router `$Router -DnsServer `$DnsServer
Set-DhcpServerv4OptionValue -ScopeId `$ScopeId -OptionId 66 -Value `$TftpServer
Set-DhcpServerv4OptionValue -ScopeId `$ScopeId -OptionId 67 -Value "bootcode.bin"

# Raspberry Pi legacy netboot vendor-specific option 43.
# If this errors on your DHCP Server version, create option 43 manually with:
# $option43Decimal
Set-DhcpServerv4OptionValue -ScopeId `$ScopeId -OptionId 43 -Value `$Option43

$($reservationLines -join [Environment]::NewLine)

Write-Host "DHCP plan applied. Verify no other DHCP server is answering on this VLAN."
"@

    $staticClients = @()
    foreach ($client in @($ConfigObject.clients)) {
        $staticClients += "- ``$($client.mac)`` -> ``$($client.ip)`` ($($client.hostname)), profile ``$($ConfigObject.name)``"
    }
    if ($staticClients.Count -eq 0) { $staticClients = @("- Add clients first, then regenerate.") }
    Write-Text "$OutputRoot\windows\hanewin-dhcp-profile.md" @"
# haneWIN DHCP/TFTP Profile Notes

- Profile name: ``$($ConfigObject.name)``
- Gateway/router: ``$($ConfigObject.router_ip)``
- DNS server: ``$($ConfigObject.dns_server)``
- TFTP next server: ``$($ConfigObject.server_ip)``
- TFTP root directory: ``$($ConfigObject.tftp_root)``
- Vendor-specific option 43 bytes:

``````text
$option43Decimal
``````

## Static Clients

$($staticClients -join [Environment]::NewLine)
"@

    Write-Text "$OutputRoot\windows\hanewin-nfs-exports.txt" @"
# haneWIN NFS export lines
# Enable "Save attributes/uid/gid on NTFS volumes" in haneWIN NFS Server.

$($ConfigObject.nfs_root) -name:$($ConfigObject.nfs_alias.TrimStart("/")) -alldirs -i32 -maproot:0:0
"@

    Write-Text "$OutputRoot\windows\server-nfs.ps1" @"
# Run in an elevated PowerShell session on Windows Server.
Install-WindowsFeature -Name FS-NFS-Service -IncludeManagementTools
New-Item -ItemType Directory -Force -Path '$($ConfigObject.nfs_root)' | Out-Null
New-NfsShare -Name '$($ConfigObject.nfs_alias.TrimStart("/"))' -Path '$($ConfigObject.nfs_root)' -Permission ReadWrite -AllowRootAccess `$true -Authentication sys
Grant-NfsSharePermission -Name '$($ConfigObject.nfs_alias.TrimStart("/"))' -ClientName "*" -ClientType Host -Permission ReadWrite -AllowRootAccess `$true
"@

    $iscsiBlocks = @()
    foreach ($client in @($ConfigObject.clients)) {
        $vhdx = "$($ConfigObject.iscsi_root)\$($client.hostname).vhdx"
        $iscsiBlocks += @"
New-IscsiVirtualDisk -Path '$vhdx' -SizeBytes $($ConfigObject.vhdx_size_gb)GB
New-IscsiServerTarget -TargetName '$($client.iscsi_target_name)' -InitiatorIds 'IQN:$($client.iscsi_initiator_iqn)'
Add-IscsiVirtualDiskTargetMapping -TargetName '$($client.iscsi_target_name)' -Path '$vhdx'
# Pi cmdline target: iqn.1991-05.com.microsoft:$($client.iscsi_target_name)
"@
    }
    if ($iscsiBlocks.Count -eq 0) { $iscsiBlocks = @("# Add clients first, then regenerate.") }
    Write-Text "$OutputRoot\windows\03-iscsi-windows-server.ps1" @"
# Run in an elevated PowerShell session on Windows Server.
Install-WindowsFeature -Name FS-iSCSITarget-Server -IncludeManagementTools
New-Item -ItemType Directory -Force -Path '$($ConfigObject.iscsi_root)' | Out-Null

$($iscsiBlocks -join [Environment]::NewLine)
"@

    $firstClient = if (@($ConfigObject.clients).Count -gt 0) { @($ConfigObject.clients)[0].serial } else { "CLIENT_SERIAL" }
    $materialize = @'
#!/usr/bin/env bash
set -euo pipefail

# Run this from a temporary Raspberry Pi OS boot or a Linux helper machine.
# It copies a mounted/ext4 Raspberry Pi root filesystem into the Windows NFS
# export through NFS, preserving Linux metadata through the NFS server.

SERVER_IP="${SERVER_IP:-__SERVER_IP__}"
NFS_ALIAS="${NFS_ALIAS:-__NFS_ALIAS__}"
CLIENT_SERIAL="${CLIENT_SERIAL:-__CLIENT_SERIAL__}"
SOURCE_ROOT="${1:-}"
WORK="${WORK:-/mnt/rpi-netboot-windows}"

if [ -z "$SOURCE_ROOT" ]; then
  echo "Usage: CLIENT_SERIAL=<serial> $0 /path/to/mounted/rootfs"
  exit 2
fi

sudo apt-get update
sudo apt-get install -y nfs-common rsync

sudo mkdir -p "$WORK/nfs"
sudo mountpoint -q "$WORK/nfs" || sudo mount -t nfs -o vers=3,tcp "$SERVER_IP:$NFS_ALIAS" "$WORK/nfs"
sudo mkdir -p "$WORK/nfs/$CLIENT_SERIAL"

sudo rsync -aHAX --numeric-ids --delete "$SOURCE_ROOT"/ "$WORK/nfs/$CLIENT_SERIAL"/

if [ -f "$WORK/nfs/$CLIENT_SERIAL/etc/fstab" ]; then
  sudo sed -i.bak -E 's#^(PARTUUID=[^[:space:]]+[[:space:]]+/[[:space:]].*)$#\#\1#' "$WORK/nfs/$CLIENT_SERIAL/etc/fstab"
  sudo sed -i -E 's#^(PARTUUID=[^[:space:]]+[[:space:]]+/boot[^[:space:]]*[[:space:]].*)$#\#\1#' "$WORK/nfs/$CLIENT_SERIAL/etc/fstab"
fi

echo "Root filesystem copied to $SERVER_IP:$NFS_ALIAS/$CLIENT_SERIAL"
'@
    $materialize = $materialize.Replace("__SERVER_IP__", $ConfigObject.server_ip).Replace("__NFS_ALIAS__", $ConfigObject.nfs_alias).Replace("__CLIENT_SERIAL__", $firstClient)
    Write-Text "$OutputRoot\pi\materialize-rootfs.sh" $materialize

    foreach ($client in @($ConfigObject.clients)) {
        $tftpDir = "$OutputRoot\tftp\$($client.tftp_prefix)"
        Write-Text "$tftpDir\config.txt" "enable_uart=1"
        if ($ConfigObject.method -eq "windows-server-iscsi" -or $client.boot_mode -eq "iscsi") {
            Write-Text "$tftpDir\cmdline.txt" (Get-IscsiCmdline $ConfigObject $client)
        } else {
            Write-Text "$tftpDir\cmdline.txt" (Get-NfsCmdline $ConfigObject $client)
        }
        Write-Text "$tftpDir\README_COPY_BOOT_FILES.txt" @"
Copy the Raspberry Pi boot partition files for $($client.hostname) into this folder.
Keep the generated cmdline.txt and config.txt, or merge their contents carefully.

Expected TFTP prefix: $($client.tftp_prefix)
Client IP reservation: $($client.ip)
"@
    }
}

switch ($Command) {
    "init" {
        $cfg = New-HostConfig -Method $Method -ServerIp $ServerIp -RouterIp $RouterIp -DnsServer $DnsServer -SubnetMask $SubnetMask -DhcpStart $DhcpStart -DhcpEnd $DhcpEnd -ProjectRoot $ProjectRoot -TftpRoot $TftpRoot -RootfsRoot $RootfsRoot -IscsiRoot $IscsiRoot
        Save-Json $cfg $Config
        Write-Host "Created $((Resolve-Path -LiteralPath $Config).Path)"
    }
    "add-client" {
        if (-not $Serial -or -not $Mac -or -not $Ip) { throw "add-client requires -Serial, -Mac, and -Ip" }
        $cfg = Read-Json $Config
        $clients = @($cfg.clients)
        $clients += New-Client $Serial $Mac $Ip $Hostname $BootMode
        $cfg.clients = @($clients)
        Save-Json $cfg $Config
        Write-Host "Added client to $((Resolve-Path -LiteralPath $Config).Path)"
    }
    "import-legacy" {
        if (-not $Backup) { throw "import-legacy requires -Backup" }
        $legacy = Read-Json $Backup
        $clients = @()
        foreach ($item in @($legacy.clients)) {
            $mappedIp = Move-IpToServerSubnet $item.ip $ServerIp
            $clients += New-Client $item.serial $item.mac $mappedIp $item.hostname $item.boot_mode
        }
        $cfg = New-HostConfig -Method $Method -ServerIp $ServerIp -RouterIp $RouterIp -DnsServer $DnsServer -SubnetMask $SubnetMask -DhcpStart $DhcpStart -DhcpEnd $DhcpEnd -ProjectRoot $ProjectRoot -TftpRoot $TftpRoot -RootfsRoot $RootfsRoot -IscsiRoot $IscsiRoot -Clients $clients
        Save-Json $cfg $Config
        Write-Host "Imported $($clients.Count) clients into $((Resolve-Path -LiteralPath $Config).Path)"
    }
    "generate" {
        $cfg = Read-Json $Config
        Invoke-Generate $cfg $Out
        Write-Host "Generated plan in $((Resolve-Path -LiteralPath $Out).Path)"
    }
    "doctor" {
        Write-Host "OS: $([System.Environment]::OSVersion.VersionString)"
        Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
        if (Test-Path -LiteralPath $Config) {
            $cfg = Read-Json $Config
            $scope = Get-ScopeId $cfg.server_ip $cfg.subnet_mask
            $cidr = Get-CidrPrefix $cfg.subnet_mask
            Write-Host "Config: $((Resolve-Path -LiteralPath $Config).Path)"
            Write-Host "Method: $($cfg.method)"
            Write-Host "Server IP: $($cfg.server_ip)"
            Write-Host "DHCP scope: $scope/$cidr"
            Write-Host "Clients: $(@($cfg.clients).Count)"
        } else {
            Write-Host "Config not found: $((Resolve-Path -LiteralPath .).Path)\$Config"
        }
    }
    "sources" {
        Write-Output (Get-ResearchText)
    }
    "sd-list" {
        Invoke-SdCardTool "list"
    }
    "sd-download-eeprom-network" {
        Invoke-SdCardTool "download-eeprom-network"
    }
    "sd-prepare-eeprom-network" {
        Invoke-SdCardTool "prepare-eeprom-network"
    }
    "sd-write-image" {
        Invoke-SdCardTool "write-image"
    }
}
