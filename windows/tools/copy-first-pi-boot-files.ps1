param(
    [string] $Config = ".\lab-10.73.json",
    [string] $GeneratedTftp = ".\generated\lab-10.73\tftp",
    [string] $Serial = "",
    [string] $Mac = "",
    [string] $SourceDriveLetter = ""
)

$ErrorActionPreference = "Stop"

function Write-Check {
    param(
        [ValidateSet("정상", "주의", "필요", "오류")]
        [string] $Status,
        [string] $Item,
        [string] $Detail
    )
    Write-Output ("[{0}] {1} - {2}" -f $Status, $Item, $Detail)
}

function Normalize-Mac {
    param([string] $Value)
    return ($Value -replace "-", ":" -replace "\s", "").ToLowerInvariant()
}

function Find-RecentDhcpMac {
    $paths = @(
        "C:\Program Files\dhcp\dynamic",
        "C:\Program Files\dhcp\ethers"
    )
    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $line = Get-Content -LiteralPath $path -ErrorAction SilentlyContinue |
            Where-Object { $_ -match "^[0-9a-fA-F]{2}([:-][0-9a-fA-F]{2}){5}\s+" } |
            Select-Object -First 1
        if ($line) {
            return ($line -split "\s+")[0]
        }
    }
    return ""
}

function Resolve-Serial {
    param($ConfigObject)
    if ($Serial) { return $Serial }

    $lookupMac = $Mac
    if (-not $lookupMac) {
        $lookupMac = Find-RecentDhcpMac
    }
    if ($lookupMac) {
        $normalized = Normalize-Mac $lookupMac
        $client = @($ConfigObject.clients) |
            Where-Object { (Normalize-Mac ([string]$_.mac)) -eq $normalized } |
            Select-Object -First 1
        if ($client) {
            Write-Check "정상" "대상 Pi 자동 선택" "$($client.serial) / $($client.mac) / $($client.ip)"
            return [string]$client.serial
        }
    }

    throw "대상 Pi serial을 정하지 못했습니다. Pi가 한 번 DHCP 요청을 보낸 뒤 다시 실행하거나 -Serial 값을 지정하세요."
}

function Find-BootSource {
    if ($SourceDriveLetter) {
        $root = "$($SourceDriveLetter.TrimEnd(':')):\"
        if ((Test-Path -LiteralPath (Join-Path $root "start4.elf")) -and
            (Test-Path -LiteralPath (Join-Path $root "fixup4.dat"))) {
            return $root
        }
        throw "$root 에 start4.elf/fixup4.dat가 없습니다. EEPROM SD가 아니라 Raspberry Pi OS boot 파티션이 필요합니다."
    }

    $candidates = foreach ($volume in Get-Volume -ErrorAction SilentlyContinue) {
        if (-not $volume.DriveLetter) { continue }
        if ($volume.FileSystem -ne "FAT32") { continue }
        $root = "$($volume.DriveLetter):\"
        $start = Join-Path $root "start4.elf"
        $fixup = Join-Path $root "fixup4.dat"
        if ((Test-Path -LiteralPath $start) -and (Test-Path -LiteralPath $fixup)) {
            [pscustomobject]@{
                Root = $root
                Label = $volume.FileSystemLabel
                Size = $volume.Size
            }
        }
    }

    $items = @($candidates)
    if ($items.Count -eq 1) {
        return $items[0].Root
    }
    if ($items.Count -gt 1) {
        $list = ($items | ForEach-Object { "$($_.Root) ($($_.Label))" }) -join ", "
        throw "boot 파티션 후보가 여러 개입니다: $list. SourceDriveLetter를 지정하세요."
    }

    throw "Raspberry Pi OS boot 파티션을 찾지 못했습니다. start4.elf/fixup4.dat가 있는 SD카드나 이미지 파티션을 꽂아야 합니다. EEPROM 업데이트 SD만으로는 부족합니다."
}

try {
    $cfg = Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json
    $targetSerial = Resolve-Serial $cfg
    $sourceRoot = Find-BootSource
    $targetRoot = Join-Path ([string]$cfg.tftp_root) $targetSerial
    $generatedRoot = Join-Path $GeneratedTftp $targetSerial
    $generatedCmdline = Join-Path $generatedRoot "cmdline.txt"

    if (-not (Test-Path -LiteralPath $generatedCmdline)) {
        throw "generated cmdline.txt를 찾지 못했습니다: $generatedCmdline"
    }

    New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null

    $backupRoot = Join-Path $targetRoot ("_backup-before-boot-copy-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
    foreach ($name in @("cmdline.txt", "config.txt")) {
        $path = Join-Path $targetRoot $name
        if (Test-Path -LiteralPath $path) {
            Copy-Item -LiteralPath $path -Destination (Join-Path $backupRoot $name) -Force
        }
    }

    Copy-Item -Path (Join-Path $sourceRoot "*") -Destination $targetRoot -Recurse -Force
    Copy-Item -LiteralPath $generatedCmdline -Destination (Join-Path $targetRoot "cmdline.txt") -Force

    $configPath = Join-Path $targetRoot "config.txt"
    if (Test-Path -LiteralPath $configPath) {
        $configText = Get-Content -LiteralPath $configPath -Raw -ErrorAction SilentlyContinue
        if ($configText -notmatch "(?m)^\s*enable_uart=1\s*$") {
            Add-Content -LiteralPath $configPath -Value "`r`nenable_uart=1"
        }
    } else {
        Set-Content -LiteralPath $configPath -Value "enable_uart=1" -Encoding ASCII
    }

    $required = @("start4.elf", "fixup4.dat", "bcm2711-rpi-4-b.dtb", "cmdline.txt", "config.txt")
    $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $targetRoot $_)) })

    Write-Check "정상" "boot 파티션 원본" $sourceRoot
    Write-Check "정상" "대상 TFTP 폴더" $targetRoot
    Write-Check "정상" "cmdline.txt" "네트워크 rootfs용 generated 파일로 복원했습니다."
    if ($missing.Count -eq 0) {
        Write-Check "정상" "Pi 4 필수 boot 파일" "필수 파일이 모두 있습니다."
    } else {
        Write-Check "주의" "Pi 4 필수 boot 파일" "누락: $($missing -join ', ')"
    }
} catch {
    Write-Check "필요" "첫 Pi 부팅파일 복사" $_.Exception.Message
}


