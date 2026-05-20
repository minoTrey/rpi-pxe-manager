#Requires -RunAsAdministrator
param(
    [string] $InterfaceAlias = "",
    [string] $IpAddress = "10.73.0.10",
    [int] $PrefixLength = 24,
    [string] $Gateway = "",
    [string] $DnsServer = "10.73.0.1"
)

$ErrorActionPreference = "Stop"

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
$adapter = Get-NetAdapter -Name $InterfaceAlias -ErrorAction Stop
if ($adapter.Status -ne "Up") {
    throw "Adapter '$InterfaceAlias' is not Up. Current status: $($adapter.Status)"
}

Write-Host "Configuring adapter '$InterfaceAlias' as $IpAddress/$PrefixLength"
Write-Host "Existing IPv4 addresses/routes on this adapter will be replaced."

Set-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -Dhcp Disabled

Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

Get-NetRoute -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
    Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

if ([string]::IsNullOrWhiteSpace($Gateway)) {
    New-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $IpAddress -PrefixLength $PrefixLength | Out-Null
    Write-Host "No default gateway was set on this adapter. Wi-Fi can keep normal internet routing."
} else {
    New-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $IpAddress -PrefixLength $PrefixLength -DefaultGateway $Gateway | Out-Null
}

if ([string]::IsNullOrWhiteSpace($DnsServer)) {
    Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ResetServerAddresses
} else {
    Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $DnsServer
}

Get-NetIPConfiguration -InterfaceAlias $InterfaceAlias | Format-List InterfaceAlias,IPv4Address,IPv4DefaultGateway,DNSServer
