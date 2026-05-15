param(
    [string] $InterfaceAlias = "",
    [string] $ServerIp = "10.73.0.10",
    [string] $RouterIp = "10.73.0.1",
    [string] $ProjectRoot = "D:\"
)

$ErrorActionPreference = "Continue"

function Resolve-LabInterfaceAlias {
    param([string] $RequestedAlias)

    if (-not [string]::IsNullOrWhiteSpace($RequestedAlias)) {
        return (Get-NetAdapter -Name $RequestedAlias -ErrorAction Stop).Name
    }

    $candidate = Get-NetAdapter |
        Where-Object {
            $_.Status -eq "Up" -and
            $_.InterfaceDescription -notmatch "Wireless|Wi-Fi|802\.11|Bluetooth|Virtual"
        } |
        Sort-Object ifIndex |
        Select-Object -First 1

    if (-not $candidate) {
        throw "Could not auto-detect a wired Ethernet adapter. Pass -InterfaceAlias explicitly."
    }
    return $candidate.Name
}

$InterfaceAlias = Resolve-LabInterfaceAlias $InterfaceAlias

Write-Host "== Volumes =="
Get-Volume | Sort-Object DriveLetter |
    Select-Object DriveLetter,FileSystemLabel,FileSystem,DriveType,HealthStatus,SizeRemaining,Size |
    Format-Table -AutoSize

Write-Host "== RPI storage expectation =="
$rpiVolume = Get-Volume -DriveLetter D -ErrorAction SilentlyContinue
[pscustomobject]@{
    Expected = "D: fixed NTFS volume labeled rpi"
    Actual = if ($rpiVolume) { "D: $($rpiVolume.FileSystemLabel) $($rpiVolume.FileSystem) $($rpiVolume.DriveType)" } else { "D: not mounted" }
    OK = ($rpiVolume -and $rpiVolume.FileSystemLabel -eq "rpi" -and $rpiVolume.FileSystem -eq "NTFS" -and $rpiVolume.DriveType -eq "Fixed")
} | Format-List

Write-Host "== Adapter =="
Get-NetIPConfiguration -InterfaceAlias $InterfaceAlias | Format-List InterfaceAlias,IPv4Address,IPv4DefaultGateway,DNSServer

Write-Host "== Router reachability =="
Test-NetConnection -ComputerName $RouterIp -InformationLevel Detailed |
    Select-Object ComputerName,RemoteAddress,InterfaceAlias,SourceAddress,PingSucceeded |
    Format-List

Write-Host "== Expected lab folders =="
$folders = @(
    $ProjectRoot,
    (Join-Path $ProjectRoot "tftp"),
    (Join-Path $ProjectRoot "rootfs"),
    (Join-Path $ProjectRoot "iscsi")
)
foreach ($folder in $folders) {
    [pscustomobject]@{ Path = $folder; Exists = (Test-Path -LiteralPath $folder) }
}

Write-Host "== Local boot-service listeners =="
Write-Host "UDP 67/69 should appear after DHCP/TFTP tools are running."
Get-NetUDPEndpoint -LocalPort 67,69 -ErrorAction SilentlyContinue |
    Select-Object LocalAddress,LocalPort,OwningProcess,@{Name='ProcessName';Expression={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName}} |
    Format-Table -AutoSize

Write-Host "TCP 2049 appears after NFS is running; TCP 3260 appears after iSCSI target is running."
Get-NetTCPConnection -LocalPort 2049,3260 -ErrorAction SilentlyContinue |
    Select-Object LocalAddress,LocalPort,State,OwningProcess,@{Name='ProcessName';Expression={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName}} |
    Format-Table -AutoSize

Write-Host "== Generated plan =="
$plan = Join-Path (Split-Path -Parent $PSScriptRoot) "generated\lab-10.73"
[pscustomobject]@{
    PlanPath = $plan
    Exists = (Test-Path -LiteralPath $plan)
    TftpClientDirs = if (Test-Path -LiteralPath "$plan\tftp") { @(Get-ChildItem -LiteralPath "$plan\tftp" -Directory).Count } else { 0 }
} | Format-List
