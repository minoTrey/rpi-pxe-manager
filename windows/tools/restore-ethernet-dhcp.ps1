#Requires -RunAsAdministrator
param(
    [string] $InterfaceAlias = ""
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

Write-Host "Restoring DHCP on adapter '$InterfaceAlias'"

Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

Get-NetRoute -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
    Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

Set-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -Dhcp Enabled
Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ResetServerAddresses

ipconfig /renew $InterfaceAlias
Get-NetIPConfiguration -InterfaceAlias $InterfaceAlias | Format-List InterfaceAlias,IPv4Address,IPv4DefaultGateway,DNSServer
