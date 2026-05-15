[CmdletBinding()]
param(
    [ValidateSet("status", "install-busybox", "restore")]
    [string] $Command = "status",

    [string] $Config = ".\lab-10.73.json",
    [string] $Serial = "d80c0b88",
    [string] $SevenZip = "C:\Program Files\7-Zip\7z.exe",
    [string] $DownloadDir = "D:\downloads",
    [string] $ToolsRoot = "D:\tools\rpi-netboot"
)

$ErrorActionPreference = "Stop"

$BusyBoxUrl = "https://deb.debian.org/debian/pool/main/b/busybox/busybox-static_1.37.0-6+b7_arm64.deb"
$BusyBoxSha256 = "DBDDAF497C4BB5AC03C74DFCBD38ED2C81A69C139786DDC8C104E3B8EAAA3644"

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

function Resolve-Inside {
    param([string] $Path, [string] $Root)
    $resolvedPath = [IO.Path]::GetFullPath($Path)
    $resolvedRoot = [IO.Path]::GetFullPath($Root)
    if (-not $resolvedRoot.EndsWith("\")) { $resolvedRoot += "\" }
    if (-not $resolvedPath.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to touch path outside expected root. Path=$resolvedPath Root=$resolvedRoot"
    }
    $resolvedPath
}

function Get-Paths {
    $cfg = Read-LabConfig
    $rootfsRoot = if ($cfg.rootfs_root) { [string]$cfg.rootfs_root } else { "D:\rootfs" }
    $tftpRoot = if ($cfg.tftp_root) { [string]$cfg.tftp_root } else { "D:\tftp" }
    $rootfs = Join-Path $rootfsRoot $Serial
    $tftp = Join-Path $tftpRoot $Serial

    [pscustomobject]@{
        Rootfs = Resolve-Inside $rootfs $rootfsRoot
        Tftp = Resolve-Inside $tftp $tftpRoot
        Init = Resolve-Inside (Join-Path $rootfs "usr\sbin\init") $rootfsRoot
        InitBackup = Resolve-Inside (Join-Path $rootfs "usr\sbin\init.systemd-before-busybox") $rootfsRoot
        Cmdline = Resolve-Inside (Join-Path $tftp "cmdline.txt") $tftpRoot
        Marker = Resolve-Inside (Join-Path $rootfs "BOOT-NFS-BUSYBOX-DIAGNOSTIC.txt") $rootfsRoot
    }
}

function Get-BusyBox {
    if (-not (Test-Path -LiteralPath $SevenZip)) {
        throw "7-Zip not found: $SevenZip"
    }
    New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
    $pkg = Join-Path $DownloadDir "busybox-static_1.37.0-6+b7_arm64.deb"
    if (-not (Test-Path -LiteralPath $pkg)) {
        Write-Check "진행" "busybox-static 다운로드" $BusyBoxUrl
        Invoke-WebRequest -Uri $BusyBoxUrl -OutFile $pkg
    }

    $hash = (Get-FileHash -LiteralPath $pkg -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($hash -ne $BusyBoxSha256) {
        throw "busybox-static hash mismatch. Expected=$BusyBoxSha256 Actual=$hash"
    }
    Write-Check "정상" "busybox-static SHA256" $hash

    $extractRoot = Join-Path $ToolsRoot "diagnostics\busybox-static-arm64"
    $stage1 = Join-Path $extractRoot "deb"
    $stage2 = Join-Path $extractRoot "root"
    New-Item -ItemType Directory -Force -Path $stage1, $stage2 | Out-Null

    & $SevenZip x -y $pkg "-o$stage1" | Out-Null
    $dataTarXz = Join-Path $stage1 "data.tar.xz"
    if (Test-Path -LiteralPath $dataTarXz) {
        & $SevenZip x -y $dataTarXz "-o$stage1" | Out-Null
    }
    & $SevenZip x -y (Join-Path $stage1 "data.tar") "-o$stage2" | Out-Null

    $busybox = Join-Path $stage2 "bin\busybox"
    if (-not (Test-Path -LiteralPath $busybox)) {
        $busybox = Join-Path $stage2 "usr\bin\busybox"
    }
    if (-not (Test-Path -LiteralPath $busybox)) {
        throw "Extracted busybox not found: $busybox"
    }
    $busybox
}

function Set-CmdlineInit {
    param([string] $Cmdline)
    if (-not (Test-Path -LiteralPath $Cmdline)) {
        Write-Check "주의" "cmdline.txt" "찾을 수 없음: $Cmdline"
        return
    }
    $line = (Get-Content -LiteralPath $Cmdline -Raw -Encoding ASCII).Trim()
    if ($line -match "\sinit=\S+") {
        $line = [regex]::Replace($line, "\sinit=\S+", " init=/usr/sbin/init")
    } else {
        $line = "$line init=/usr/sbin/init"
    }
    Set-Content -LiteralPath $Cmdline -Value $line -Encoding ASCII -NoNewline
    Write-Check "정상" "cmdline init" "init=/usr/sbin/init"
}

function Show-Status {
    $paths = Get-Paths
    Write-Check "정보" "rootfs" $paths.Rootfs
    Write-Check "정보" "tftp" $paths.Tftp
    foreach ($path in @($paths.Init, $paths.InitBackup, $paths.Cmdline, $paths.Marker)) {
        if (Test-Path -LiteralPath $path) {
            $item = Get-Item -LiteralPath $path -Force
            $hash = if (-not $item.PSIsContainer) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash } else { "" }
            Write-Check "정상" $path "size=$($item.Length) sha256=$hash"
        } else {
            Write-Check "없음" $path "not found"
        }
    }
}

function Install-BusyBoxInit {
    $paths = Get-Paths
    if (-not (Test-Path -LiteralPath $paths.Init)) {
        throw "init not found: $($paths.Init)"
    }

    if (-not (Test-Path -LiteralPath $paths.InitBackup)) {
        Copy-Item -LiteralPath $paths.Init -Destination $paths.InitBackup
        Write-Check "정상" "systemd init 백업" $paths.InitBackup
    } else {
        Write-Check "정상" "systemd init 백업" "이미 있음: $($paths.InitBackup)"
    }

    $busybox = Get-BusyBox
    Copy-Item -LiteralPath $busybox -Destination $paths.Init -Force
    Set-CmdlineInit $paths.Cmdline

    $note = @(
        "Temporary diagnostic mode.",
        "usr/sbin/init was replaced with Debian arm64 busybox-static.",
        "Restore with: powershell -NoProfile -ExecutionPolicy Bypass -File windows\tools\init-diagnostic.ps1 -Command restore",
        "Expected result: if static busybox also fails with error -14, the NFS provider/file representation is strongly suspect."
    )
    Set-Content -LiteralPath $paths.Marker -Value $note -Encoding UTF8
    Write-Check "정상" "busybox static init" "설치됨. 이제 RPi4 전원을 다시 넣어 진단 부팅합니다."
}

function Restore-Init {
    $paths = Get-Paths
    if (-not (Test-Path -LiteralPath $paths.InitBackup)) {
        throw "backup not found: $($paths.InitBackup)"
    }
    Copy-Item -LiteralPath $paths.InitBackup -Destination $paths.Init -Force
    Set-CmdlineInit $paths.Cmdline
    Write-Check "정상" "systemd init 복원" $paths.Init
}

switch ($Command) {
    "status" { Show-Status }
    "install-busybox" { Install-BusyBoxInit; Show-Status }
    "restore" { Restore-Init; Show-Status }
}
