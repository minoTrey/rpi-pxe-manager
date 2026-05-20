param(
    [string] $Config = ".\lab-10.73.json",
    [string] $Serial = "",
    [string] $Branch = "master",
    [switch] $Force
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

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

function Resolve-Client {
    param($Cfg)
    if (-not [string]::IsNullOrWhiteSpace($Serial)) {
        $client = @($Cfg.clients) | Where-Object { $_.serial -eq $Serial -or $_.tftp_prefix -eq $Serial } | Select-Object -First 1
        if (-not $client) { throw "Client serial not found in config: $Serial" }
        return $client
    }

    $current = @($Cfg.clients) | Where-Object { $_.mac -eq "88:a2:9e:4f:a9:b1" -or $_.serial -eq "d80c0b88" } | Select-Object -First 1
    if ($current) { return $current }

    return @($Cfg.clients) | Select-Object -First 1
}

function Invoke-DownloadFile {
    param([string] $Url, [string] $OutFile)
    if ((Test-Path -LiteralPath $OutFile) -and -not $Force) {
        return
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutFile) | Out-Null
    Invoke-WebRequest -Uri $Url -OutFile $OutFile
}

function Get-GitHubContents {
    param([string] $Path)
    $encoded = ($Path -split "/" | ForEach-Object { [uri]::EscapeDataString($_) }) -join "/"
    $url = "https://api.github.com/repos/raspberrypi/firmware/contents/$encoded`?ref=$Branch"
    $response = Invoke-RestMethod -Uri $url -Headers @{ "User-Agent" = "rpi-netboot-windows" }
    foreach ($entry in @($response)) {
        Write-Output $entry
    }
}

function Download-Directory {
    param([string] $RepoPath, [string] $Destination)
    $items = @(Get-GitHubContents $RepoPath)
    foreach ($item in $items) {
        if ($item.type -eq "file") {
            $target = Join-Path $Destination $item.name
            Invoke-DownloadFile $item.download_url $target
            Write-Check "정상" "download" "$RepoPath/$($item.name)"
        } elseif ($item.type -eq "dir" -and $item.name -eq "overlays") {
            Download-Directory "$RepoPath/$($item.name)" (Join-Path $Destination $item.name)
        }
    }
}

function Add-ConfigLine {
    param([string[]] $Lines, [string] $Line)
    $key = ($Line -split "=", 2)[0]
    if ($Lines | Where-Object { $_ -match "^\s*$([regex]::Escape($key))\s*=" -or $_.Trim() -eq $Line }) {
        return $Lines
    }
    return @($Lines + $Line)
}

$cfg = Read-ConfigObject
$client = Resolve-Client $cfg
if (-not $client) { throw "No client in config." }

$serialValue = [string]$client.tftp_prefix
if ([string]::IsNullOrWhiteSpace($serialValue)) { $serialValue = [string]$client.serial }
$target = Join-Path ([string]$cfg.tftp_root) $serialValue
New-Item -ItemType Directory -Force -Path $target | Out-Null

$cmdlinePath = Join-Path $target "cmdline.txt"
$configPath = Join-Path $target "config.txt"
$existingCmdline = if (Test-Path -LiteralPath $cmdlinePath) { Get-Content -LiteralPath $cmdlinePath -Raw -Encoding UTF8 } else { "" }
$existingConfig = if (Test-Path -LiteralPath $configPath) { Get-Content -LiteralPath $configPath -Encoding UTF8 } else { @() }

Write-Output "== Raspberry Pi 공식 firmware boot 파일 다운로드 =="
Write-Check "정상" "대상 Pi" "$serialValue / $($client.mac) / $($client.ip)"
Write-Check "정상" "TFTP 폴더" $target

Download-Directory "boot" $target

if (-not [string]::IsNullOrWhiteSpace($existingCmdline)) {
    Set-Content -LiteralPath $cmdlinePath -Value (($existingCmdline -replace "\r?\n", " ").Trim()) -Encoding ASCII
    Write-Check "정상" "cmdline 유지" $cmdlinePath
}

$configLines = @($existingConfig)
if ($configLines.Count -eq 0) { $configLines = @("enable_uart=1") }
$configLines = Add-ConfigLine $configLines "enable_uart=1"
$configLines = Add-ConfigLine $configLines "arm_64bit=1"
$configLines = Add-ConfigLine $configLines "kernel=kernel8.img"
Set-Content -LiteralPath $configPath -Value $configLines -Encoding ASCII
Write-Check "정상" "config 정리" "enable_uart=1, arm_64bit=1, kernel=kernel8.img"

$required = @("start4.elf", "fixup4.dat", "bcm2711-rpi-4-b.dtb", "kernel8.img", "overlays")
$missing = @()
foreach ($name in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $target $name))) {
        $missing += $name
    }
}

if ($missing.Count -gt 0) {
    Write-Check "오류" "필수 boot 파일" ("누락: " + ($missing -join ", "))
    exit 2
}

Write-Check "정상" "필수 boot 파일" "start4.elf, fixup4.dat, bcm2711-rpi-4-b.dtb, kernel8.img, overlays 준비됨"
Write-Check "주의" "다음 단계" "이제 TFTP firmware 단계는 넘어갈 수 있지만, D:\rootfs\$serialValue Linux rootfs가 비어 있으면 NFS root 단계에서 멈춥니다."


