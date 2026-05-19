[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("prepare", "apply-cmdline", "restore-winnfsd-cmdline", "start-attempt", "finish-attempt", "status")]
    [string] $Command = "prepare",

    [string] $Config = ".\windows\lab-10.73.json",
    [string] $Serial = "d80c0b88",
    [string] $Mac = "88:a2:9e:4f:a9:b1",
    [string] $PiIp = "10.73.0.155",
    [string] $LinuxServerIp = "10.73.0.20",
    [string] $LinuxExportRoot = "/srv/rpi-root",
    [string] $ToolsRoot = "D:\tools\rpi-netboot",
    [string] $OutRoot = "D:\logs\netboot-harness",
    [string] $ConsoleText = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

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

function Save-Json {
    param([object] $Data, [string] $Path, [int] $Depth = 8)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $Data | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-Paths {
    $cfg = Read-LabConfig
    $tftpRoot = if ($cfg.tftp_root) { [string]$cfg.tftp_root } else { "D:\tftp" }
    $serverIp = if ($cfg.server_ip) { [string]$cfg.server_ip } else { "10.73.0.10" }
    $nfsAlias = if ($cfg.nfs_alias) { [string]$cfg.nfs_alias } else { "/rpi" }
    [pscustomobject]@{
        TftpRoot = $tftpRoot
        Tftp = Join-Path $tftpRoot $Serial
        Cmdline = Join-Path (Join-Path $tftpRoot $Serial) "cmdline.txt"
        ServerIp = $serverIp
        NfsAlias = $nfsAlias
        BundleRoot = Join-Path $ToolsRoot "linux-nfs-provider"
        StatePath = Join-Path $ToolsRoot "config\nfs-provider-state.json"
    }
}

function Backup-Cmdline {
    param([string] $Cmdline)
    if (-not (Test-Path -LiteralPath $Cmdline)) {
        throw "cmdline.txt not found: $Cmdline"
    }
    $backup = "{0}.backup-{1}" -f $Cmdline, (Get-Date -Format "yyyyMMdd-HHmmss")
    Copy-Item -LiteralPath $Cmdline -Destination $backup
    $backup
}

function Set-Cmdline {
    param([string] $TargetProvider)
    $paths = Get-Paths
    $backup = Backup-Cmdline $paths.Cmdline
    if ($TargetProvider -eq "LinuxNFS") {
        $nfsPath = "{0}/{1}" -f $LinuxExportRoot.TrimEnd("/"), $Serial
        $line = "console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=$($LinuxServerIp):$nfsPath,vers=3,proto=tcp,rw ip=dhcp rootwait elevator=deadline init=/usr/sbin/init"
    } else {
        $alias = $paths.NfsAlias.TrimEnd("/")
        $line = "console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=$($paths.ServerIp):$alias/$Serial,vers=3,tcp rw ip=dhcp rootwait elevator=deadline init=/usr/sbin/init"
    }
    Set-Content -LiteralPath $paths.Cmdline -Value $line -Encoding ASCII -NoNewline
    Save-Json ([pscustomobject]@{
        provider = $TargetProvider
        serial = $Serial
        mac = $Mac
        piIp = $PiIp
        linuxServerIp = $LinuxServerIp
        linuxExportRoot = $LinuxExportRoot
        cmdline = $line
        backup = $backup
        updatedAt = (Get-Date).ToString("o")
    }) $paths.StatePath
    Write-Check "정상" "cmdline provider" "$TargetProvider -> $line"
    Write-Check "정상" "cmdline backup" $backup
}

function Write-LinuxScripts {
    $paths = Get-Paths
    New-Item -ItemType Directory -Force -Path $paths.BundleRoot | Out-Null
    $setup = Join-Path $paths.BundleRoot "setup-linux-nfs-provider.sh"
    $verify = Join-Path $paths.BundleRoot "verify-linux-nfs-provider.sh"
    $readme = Join-Path $paths.BundleRoot "README.md"
    $exports = Join-Path $paths.BundleRoot "rpi-netboot.exports.example"

    $setupText = @'
#!/usr/bin/env bash
set -euo pipefail

SERIAL="${SERIAL:-d80c0b88}"
EXPORT_ROOT="${EXPORT_ROOT:-/srv/rpi-root}"
SUBNET="${SUBNET:-10.73.0.0/24}"
SOURCE_SSH="${SOURCE_SSH:-}"
SOURCE_DIR="${SOURCE_DIR:-}"
TARGET="${EXPORT_ROOT%/}/${SERIAL}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo: sudo SERIAL=$SERIAL EXPORT_ROOT=$EXPORT_ROOT bash $0"
  exit 1
fi

apt-get update
apt-get install -y nfs-kernel-server rsync

mkdir -p "$TARGET"

if [ -n "$SOURCE_SSH" ]; then
  echo "Pulling rootfs from SSH source: $SOURCE_SSH:/"
  rsync -aHAXx --numeric-ids --delete \
    --exclude=/dev/* --exclude=/proc/* --exclude=/sys/* --exclude=/run/* \
    --exclude=/tmp/* --exclude=/mnt/* --exclude=/media/* --exclude=/lost+found \
    --exclude=/boot/firmware/* \
    "$SOURCE_SSH:/" "$TARGET/"
elif [ -n "$SOURCE_DIR" ]; then
  echo "Copying rootfs from mounted source: $SOURCE_DIR"
  rsync -aHAXx --numeric-ids --delete \
    --exclude=/dev/* --exclude=/proc/* --exclude=/sys/* --exclude=/run/* \
    --exclude=/tmp/* --exclude=/mnt/* --exclude=/media/* --exclude=/lost+found \
    "$SOURCE_DIR/" "$TARGET/"
else
  echo "No SOURCE_SSH or SOURCE_DIR was provided."
  echo "Created empty target: $TARGET"
  echo "Re-run with one of:"
  echo "  sudo SOURCE_SSH=pi@10.73.0.155 SERIAL=$SERIAL bash $0"
  echo "  sudo SOURCE_DIR=/mnt/rpi-root SERIAL=$SERIAL bash $0"
fi

mkdir -p "$TARGET/proc" "$TARGET/sys" "$TARGET/dev" "$TARGET/run" "$TARGET/tmp"
chmod 1777 "$TARGET/tmp" || true

if [ -d "$TARGET/etc" ]; then
  cp -a "$TARGET/etc/fstab" "$TARGET/etc/fstab.before-netboot" 2>/dev/null || true
  cat > "$TARGET/etc/fstab" <<'FSTAB'
proc            /proc           proc    defaults          0       0
tmpfs           /tmp            tmpfs   defaults,nosuid   0       0
devpts          /dev/pts        devpts  gid=5,mode=620    0       0
FSTAB
fi

cat > "/etc/exports.d/rpi-netboot-${SERIAL}.exports" <<EXPORTS
$TARGET $SUBNET(rw,sync,no_subtree_check,no_root_squash,insecure)
EXPORTS

exportfs -ra
systemctl restart nfs-kernel-server

echo "== exportfs =="
exportfs -v
echo "== showmount =="
showmount -e localhost || true
echo "Linux NFS provider ready: $TARGET"
'@

    $verifyText = @'
#!/usr/bin/env bash
set -euo pipefail

SERIAL="${SERIAL:-d80c0b88}"
EXPORT_ROOT="${EXPORT_ROOT:-/srv/rpi-root}"
TARGET="${EXPORT_ROOT%/}/${SERIAL}"

echo "== service =="
systemctl --no-pager --full status nfs-kernel-server || true
echo "== exports =="
exportfs -v || true
echo "== critical files =="
for p in \
  "$TARGET/usr/sbin/init" \
  "$TARGET/usr/lib/systemd/systemd" \
  "$TARGET/usr/bin/sh" \
  "$TARGET/usr/bin/dash" \
  "$TARGET/usr/lib/ld-linux-aarch64.so.1" \
  "$TARGET/usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1" \
  "$TARGET/etc/fstab"; do
  if [ -e "$p" ]; then
    stat -c '%F %a %u:%g %s %n' "$p"
    sha256sum "$p" 2>/dev/null || true
    file "$p" 2>/dev/null || true
  else
    echo "MISSING $p"
  fi
done
'@

    $readmeText = @'
# Linux NFS Provider Bundle

Purpose: prove whether WinNFSd/NTFS is the failing layer by serving the same RPi4 NFS root from a real Linux NFS server.

Expected network:

- Windows DHCP/TFTP server: `10.73.0.10`
- Linux NFS server: `{{LINUX_SERVER_IP}}`
- Test RPi4: `{{PI_IP}}`
- Serial: `{{SERIAL}}`
- Export path: `{{LINUX_EXPORT_ROOT}}/{{SERIAL}}`

On the Linux VM or Linux helper:

```bash
cd /path/to/this/bundle
sudo SOURCE_SSH=pi@10.73.0.155 SERIAL={{SERIAL}} EXPORT_ROOT={{LINUX_EXPORT_ROOT}} bash setup-linux-nfs-provider.sh
sudo SERIAL={{SERIAL}} EXPORT_ROOT={{LINUX_EXPORT_ROOT}} bash verify-linux-nfs-provider.sh
```

If the source Pi cannot be reached over SSH, mount the SD root partition in the Linux VM and run:

```bash
sudo SOURCE_DIR=/mnt/rpi-root SERIAL={{SERIAL}} EXPORT_ROOT={{LINUX_EXPORT_ROOT}} bash setup-linux-nfs-provider.sh
```

On Windows, switch the Pi cmdline to Linux NFS:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\tools\linux-nfs-provider.ps1 apply-cmdline -Config .\windows\lab-10.73.json -Serial {{SERIAL}} -LinuxServerIp {{LINUX_SERVER_IP}}
```

Then start a harness attempt:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\tools\linux-nfs-provider.ps1 start-attempt -Config .\windows\lab-10.73.json -Serial {{SERIAL}} -LinuxServerIp {{LINUX_SERVER_IP}}
```
'@
    $readmeText = $readmeText.Replace("{{SERIAL}}", $Serial).Replace("{{LINUX_SERVER_IP}}", $LinuxServerIp).Replace("{{PI_IP}}", $PiIp).Replace("{{LINUX_EXPORT_ROOT}}", $LinuxExportRoot)

    $exportsText = "$LinuxExportRoot/$Serial 10.73.0.0/24(rw,sync,no_subtree_check,no_root_squash,insecure)"

    Set-Content -LiteralPath $setup -Value $setupText -Encoding UTF8
    Set-Content -LiteralPath $verify -Value $verifyText -Encoding UTF8
    Set-Content -LiteralPath $readme -Value $readmeText -Encoding UTF8
    Set-Content -LiteralPath $exports -Value $exportsText -Encoding ASCII

    Write-Check "정상" "Linux NFS provider bundle" $paths.BundleRoot
    Write-Check "다음" "Linux VM" "bundle 폴더를 Linux VM에 복사하고 README.md 순서대로 실행"
}

function Show-Status {
    $paths = Get-Paths
    Write-Check "정보" "bundle" $paths.BundleRoot
    Write-Check "정보" "cmdline" $paths.Cmdline
    if (Test-Path -LiteralPath $paths.Cmdline) {
        Write-Output ((Get-Content -LiteralPath $paths.Cmdline -Raw -Encoding ASCII).Trim())
    }
    if (Test-Path -LiteralPath $paths.StatePath) {
        Write-Check "정보" "provider state" $paths.StatePath
        Get-Content -LiteralPath $paths.StatePath -Raw -Encoding UTF8
    }
    if (Test-Path -LiteralPath (Join-Path $OutRoot "latest-verdict.json")) {
        Write-Check "정보" "latest verdict" (Join-Path $OutRoot "latest-verdict.json")
        Get-Content -LiteralPath (Join-Path $OutRoot "latest-verdict.json") -Raw -Encoding UTF8
    }
}

function Invoke-Harness {
    param([string] $HarnessCommand)
    $script = Join-Path $PSScriptRoot "netboot-harness.ps1"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script $HarnessCommand `
        -Config $Config `
        -Serial $Serial `
        -Mac $Mac `
        -PiIp $PiIp `
        -Provider LinuxNFS `
        -InitVariant busybox-static `
        -OutRoot $OutRoot `
        -ConsoleText $ConsoleText
}

switch ($Command) {
    "prepare" {
        Write-LinuxScripts
        Show-Status
    }
    "apply-cmdline" {
        Write-LinuxScripts
        Set-Cmdline "LinuxNFS"
    }
    "restore-winnfsd-cmdline" {
        Set-Cmdline "WinNFSd"
    }
    "start-attempt" {
        Write-LinuxScripts
        Set-Cmdline "LinuxNFS"
        Invoke-Harness "start-attempt"
    }
    "finish-attempt" {
        Invoke-Harness "finish-attempt"
    }
    "status" {
        Show-Status
    }
}
