param(
    [Parameter(Position = 0)]
    [ValidateSet("status", "make-script")]
    [string] $Command = "make-script",

    [string] $Config = ".\lab-10.73.json",
    [string] $Serial = "d80c0b88",
    [string] $Mac = "88:a2:9e:4f:a9:b1",
    [string] $OutputDir = "D:\downloads"
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

function Get-TargetClient {
    $cfg = Read-ConfigObject
    $client = @($cfg.clients) |
        Where-Object { $_.serial -eq $Serial -or $_.mac -eq $Mac } |
        Select-Object -First 1
    if (-not $client) {
        throw "Target client not found. Serial=$Serial Mac=$Mac"
    }
    [pscustomobject]@{
        Config = $cfg
        Client = $client
        RootfsPath = Join-Path ([string]$cfg.nfs_root) ([string]$client.serial)
        ScriptPath = Join-Path $OutputDir ("rpi4-rootfs-import-{0}.sh" -f $client.serial)
        GuidePath = Join-Path $OutputDir ("rpi4-rootfs-import-{0}.txt" -f $client.serial)
    }
}

function Show-RootfsStatus {
    $target = Get-TargetClient
    $cfg = $target.Config
    $client = $target.Client
    $root = $target.RootfsPath

    Write-Output "== RPi4 netboot rootfs status =="
    Write-Output "Policy: Raspberry Pi 4 is the only network boot target. Raspberry Pi Zero 2 W uses SD boot + USB gadget."
    Write-Check "정상" "대상 Pi 4" "$($client.serial) / $($client.mac) / $($client.ip)"
    Write-Check "정상" "NFS export" "$($cfg.server_ip):$($cfg.nfs_alias) -> $($cfg.nfs_root)"

    if (-not (Test-Path -LiteralPath $root)) {
        Write-Check "필요" "RPi4 rootfs 폴더" "$root 없음"
        return
    }

    $topCount = @(Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | Select-Object -First 5).Count
    $hasInit = (Test-Path -LiteralPath (Join-Path $root "sbin\init")) -or
        (Test-Path -LiteralPath (Join-Path $root "lib\systemd\systemd")) -or
        (Test-Path -LiteralPath (Join-Path $root "usr\lib\systemd\systemd"))
    $hasShell = Test-Path -LiteralPath (Join-Path $root "bin\sh")
    $hasEtc = Test-Path -LiteralPath (Join-Path $root "etc")
    $hasUsr = Test-Path -LiteralPath (Join-Path $root "usr")

    if ($hasInit -and $hasShell -and $hasEtc -and $hasUsr) {
        Write-Check "정상" "RPi4 rootfs 내용" "$root 안에 init/bin/sh/etc/usr 확인"
    } elseif ($topCount -eq 0) {
        Write-Check "필요" "RPi4 rootfs 내용" "$root 비어 있음. 현재 상태로는 커널 이후 부팅 불가"
    } else {
        Write-Check "오류" "RPi4 rootfs 내용" "$root 안에 일부 파일은 있지만 init/bin/sh/etc/usr 중 빠진 항목이 있음"
    }
}

function New-RootfsImportScript {
    $target = Get-TargetClient
    $cfg = $target.Config
    $client = $target.Client
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

    $script = @"
#!/usr/bin/env bash
set -euo pipefail

SERVER_IP="`${SERVER_IP:-$($cfg.server_ip)}"
NFS_ALIAS="`${NFS_ALIAS:-$($cfg.nfs_alias)}"
CLIENT_SERIAL="`${CLIENT_SERIAL:-$($client.serial)}"
CLIENT_HOSTNAME="`${CLIENT_HOSTNAME:-$($client.hostname)}"
WORK="`${WORK:-/mnt/rpi-netboot-windows}"
SOURCE_ROOT="`${1:-/}"

LOG="/boot/rpi4-netboot-rootfs-import-$($client.serial).log"
if [ -d /boot/firmware ]; then
  LOG="/boot/firmware/rpi4-netboot-rootfs-import-$($client.serial).log"
fi
exec > >(tee -a "`$LOG") 2>&1

echo "== Raspberry Pi 4 netboot rootfs import =="
echo "policy: RPi4 is netboot target; Zero 2 W uses SD boot + USB gadget"
echo "server: `$SERVER_IP`$NFS_ALIAS"
echo "client: `$CLIENT_SERIAL / `$CLIENT_HOSTNAME"
echo "source: `$SOURCE_ROOT"

if ! command -v rsync >/dev/null 2>&1 || { ! command -v mount.nfs >/dev/null 2>&1 && ! [ -x /sbin/mount.nfs ] && ! [ -x /usr/sbin/mount.nfs ]; }; then
  echo "Installing rsync and nfs-common..."
  sudo apt-get update
  sudo apt-get install -y rsync nfs-common
fi

sudo mkdir -p "`$WORK/nfs"
if ! mountpoint -q "`$WORK/nfs"; then
  sudo mount -t nfs -o vers=3,tcp,nolock "`$SERVER_IP:`$NFS_ALIAS" "`$WORK/nfs"
fi

sudo mkdir -p "`$WORK/nfs/`$CLIENT_SERIAL"

if [ "`$SOURCE_ROOT" = "/" ]; then
  sudo rsync -aHx --inplace --whole-file --omit-dir-times --numeric-ids \
    --exclude=/dev/* --exclude=/proc/* --exclude=/sys/* --exclude=/run/* \
    --exclude=/tmp/* --exclude=/mnt/* --exclude=/media/* --exclude=/lost+found \
    --exclude=/usr/include/* --exclude=/usr/share/doc/* --exclude=/usr/share/man/* \
    --exclude=/usr/share/info/* --exclude=/var/cache/apt/archives/* \
    --exclude=/var/lib/apt/lists/* \
    / "`$WORK/nfs/`$CLIENT_SERIAL"/
else
  sudo rsync -aH --inplace --whole-file --omit-dir-times --numeric-ids "`$SOURCE_ROOT"/ "`$WORK/nfs/`$CLIENT_SERIAL"/
fi

if [ -d "`$WORK/nfs/`$CLIENT_SERIAL/etc" ]; then
  echo "`$CLIENT_HOSTNAME" | sudo tee "`$WORK/nfs/`$CLIENT_SERIAL/etc/hostname" >/dev/null
  sudo tee "`$WORK/nfs/`$CLIENT_SERIAL/etc/fstab" >/dev/null <<'FSTAB'
proc            /proc           proc    defaults          0       0
tmpfs           /tmp            tmpfs   defaults,nosuid   0       0
devpts          /dev/pts        devpts  gid=5,mode=620    0       0
FSTAB
fi

sudo sync
echo "Done: rootfs copied to `$SERVER_IP:`$NFS_ALIAS/`$CLIENT_SERIAL"
echo "Power off the Pi, remove the OS SD card, then retry Raspberry Pi 4 network boot."
"@

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($target.ScriptPath, $script, $utf8NoBom)

    $guide = @"
RPi4 network boot rootfs helper
===============================

Policy:
- Raspberry Pi 4 is the only network boot target.
- Raspberry Pi Zero 2 W is not a netboot target; it uses SD boot + USB gadget.

Current blocker:
- TFTP and NFS can be ready on Windows.
- The RPi4 rootfs still has to be copied into $($target.RootfsPath).

Target Pi 4:
- Serial: $($client.serial)
- MAC: $($client.mac)
- IP: $($client.ip)

Generated Pi/Linux script:
$($target.ScriptPath)

Usage:
1. Boot the source Raspberry Pi OS SD card on a Pi, or mount the source rootfs on Linux.
2. Copy this .sh file to that Pi/Linux helper.
3. Run:

   sudo bash rpi4-rootfs-import-$($client.serial).sh /

4. After the copy finishes, power off the Pi and remove the SD card.
5. Retry Raspberry Pi 4 network boot.

Expected Windows-side folders after success:
$($target.RootfsPath)\bin
$($target.RootfsPath)\etc
$($target.RootfsPath)\usr
$($target.RootfsPath)\sbin

Notes:
- Do not copy a Linux root filesystem with Windows Explorer; ownership, permissions, and symlinks can be damaged.
- This helper uses rsync -aHAX from Linux into the NFS export.
"@

    Set-Content -LiteralPath $target.GuidePath -Value $guide -Encoding UTF8

    Write-Check "정상" "RPi4 rootfs import script" $target.ScriptPath
    Write-Check "정상" "RPi4 rootfs guide" $target.GuidePath
    Write-Check "필요" "다음 단계" "Run the generated .sh from Raspberry Pi OS or another Linux helper with sudo bash."
    Show-RootfsStatus
}

switch ($Command) {
    "status" { Show-RootfsStatus }
    "make-script" { New-RootfsImportScript }
}
