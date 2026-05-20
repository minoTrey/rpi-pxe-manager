param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet("list", "download-eeprom-network", "prepare-eeprom-network", "download-rpios-lite-trixie", "prepare-rpios-lite-trixie", "write-image", "verify-image")]
    [string] $Command,

    [ValidateSet("pi4", "pi5")]
    [string] $Model = "pi4",

    [int] $DiskNumber = -1,
    [string] $DriveLetter = "",
    [string] $Image = "",
    [string] $CacheDir = "",
    [string] $OsListUrl = "https://downloads.raspberrypi.com/os_list_imagingutility_v4.json",
    [int] $MaxDiskSizeGB = 64,
    [string] $ProvisionServer = "10.73.0.10",
    [int] $ProvisionPort = 8088,

    [switch] $IUnderstand,
    [switch] $NoVerify,
    [switch] $NoProvision,
    [switch] $AllowNonUsb,
    [switch] $AllowLargeDisk
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($CacheDir)) {
    $CacheDir = Join-Path (Split-Path -Parent $PSScriptRoot) "cache\downloads"
}

$script:LastWrittenDiskNumber = $null
$script:LastWrittenImagePath = ""

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this command from an elevated PowerShell session."
    }
}

function Format-Bytes {
    param([UInt64] $Value)
    if ($Value -ge 1TB) { return "{0:n2} TB" -f ($Value / 1TB) }
    if ($Value -ge 1GB) { return "{0:n2} GB" -f ($Value / 1GB) }
    if ($Value -ge 1MB) { return "{0:n2} MB" -f ($Value / 1MB) }
    return "$Value B"
}

function Ensure-BufferComparer {
    if ("RpiSdCard.BufferComparer" -as [type]) {
        return
    }

    Add-Type -TypeDefinition @"
namespace RpiSdCard {
    public static class BufferComparer {
        public static bool Equals(byte[] left, byte[] right, int count) {
            if (left == null || right == null) return false;
            if (count < 0 || count > left.Length || count > right.Length) return false;
            for (int i = 0; i < count; i++) {
                if (left[i] != right[i]) return false;
            }
            return true;
        }
    }
}
"@
}

function Get-RpiSdDiskRows {
    $volumesByDisk = @{}
    foreach ($partition in Get-Partition -ErrorAction SilentlyContinue) {
        if ($partition.DriveLetter) {
            $key = [string]$partition.DiskNumber
            if (-not $volumesByDisk.ContainsKey($key)) {
                $volumesByDisk[$key] = @()
            }
            $volume = Get-Volume -DriveLetter $partition.DriveLetter -ErrorAction SilentlyContinue
            $label = if ($volume) { $volume.FileSystemLabel } else { "" }
            $fs = if ($volume) { $volume.FileSystem } else { "" }
            $volumesByDisk[$key] += "$($partition.DriveLetter):${label}:${fs}"
        }
    }

    Get-Disk | Sort-Object Number | ForEach-Object {
        $key = [string]$_.Number
        [pscustomobject]@{
            DiskNumber = $_.Number
            FriendlyName = $_.FriendlyName
            BusType = $_.BusType
            MediaType = $_.MediaType
            PartitionStyle = $_.PartitionStyle
            Size = Format-Bytes ([UInt64]$_.Size)
            IsBoot = $_.IsBoot
            IsSystem = $_.IsSystem
            Volumes = if ($volumesByDisk.ContainsKey($key)) { $volumesByDisk[$key] -join ", " } else { "" }
        }
    }
}

function Resolve-TargetDisk {
    if ($DiskNumber -ge 0) {
        return Get-Disk -Number $DiskNumber -ErrorAction Stop
    }

    if (-not [string]::IsNullOrWhiteSpace($DriveLetter)) {
        $letter = $DriveLetter.Trim().TrimEnd(":").ToUpperInvariant()
        if ($letter.Length -ne 1) {
            throw "DriveLetter must look like S or S:."
        }
        $partition = Get-Partition -DriveLetter $letter -ErrorAction Stop
        return Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
    }

    throw "Specify -DiskNumber or -DriveLetter for destructive write commands."
}

function Assert-TargetDiskSafe {
    param(
        [Parameter(Mandatory = $true)] $Disk,
        [UInt64] $ImageSize
    )

    if (-not $IUnderstand) {
        throw "Refusing to write without -IUnderstand. This will erase the target disk."
    }
    if ($Disk.IsBoot -or $Disk.IsSystem) {
        throw "Refusing to write to boot/system disk $($Disk.Number)."
    }
    if ($Disk.OperationalStatus -contains "No Media" -or $Disk.Size -eq 0) {
        throw "Disk $($Disk.Number) has no media."
    }
    if ($ImageSize -gt [UInt64]$Disk.Size) {
        throw "Image size $(Format-Bytes $ImageSize) is larger than disk size $(Format-Bytes ([UInt64]$Disk.Size))."
    }
    if (-not $AllowNonUsb -and [string]$Disk.BusType -ne "USB") {
        throw "Disk $($Disk.Number) is BusType '$($Disk.BusType)'. Use -AllowNonUsb only if you are certain."
    }
    $maxBytes = [UInt64]$MaxDiskSizeGB * 1GB
    if (-not $AllowLargeDisk -and [UInt64]$Disk.Size -gt $maxBytes) {
        throw "Disk $($Disk.Number) is larger than $MaxDiskSizeGB GB. Use -AllowLargeDisk only if you are certain."
    }
}

function Expand-ImageIfNeeded {
    param([Parameter(Mandatory = $true)][string] $Path)

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $extension = [IO.Path]::GetExtension($resolved).ToLowerInvariant()
    if ($extension -eq ".img") {
        return $resolved
    }

    if ($extension -eq ".zip") {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $extractRoot = Join-Path (Split-Path -Parent $resolved) ([IO.Path]::GetFileNameWithoutExtension($resolved))
        New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
        $zip = [IO.Compression.ZipFile]::OpenRead($resolved)
        try {
            $entry = $zip.Entries |
                Where-Object { $_.FullName.ToLowerInvariant().EndsWith(".img") } |
                Sort-Object Length -Descending |
                Select-Object -First 1
            if (-not $entry) {
                throw "Zip does not contain an .img file: $resolved"
            }
            $target = Join-Path $extractRoot ([IO.Path]::GetFileName($entry.FullName))
            if (-not (Test-Path -LiteralPath $target) -or (Get-Item -LiteralPath $target).Length -ne $entry.Length) {
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
            }
            return $target
        } finally {
            $zip.Dispose()
        }
    }

    if ($resolved.ToLowerInvariant().EndsWith(".img.xz")) {
        $target = Join-Path (Split-Path -Parent $resolved) ([IO.Path]::GetFileNameWithoutExtension($resolved))
        $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
        if (-not $tar) {
            throw "Cannot expand .img.xz without tar.exe. Provide an extracted .img file instead."
        }
        if (-not (Test-Path -LiteralPath $target)) {
            & $tar.Source -xf $resolved -C (Split-Path -Parent $resolved)
            if ($LASTEXITCODE -ne 0) {
                throw "tar.exe failed while extracting $resolved"
            }
        }
        return $target
    }

    throw "Unsupported image type: $resolved. Use .img, .zip containing .img, or .img.xz."
}

function Get-PinnedRpiOsLiteTrixieImageName {
    return "2026-04-21-raspios-trixie-arm64-lite.img"
}

function Get-CachedRpiOsLiteTrixieImage {
    New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
    $imageName = Get-PinnedRpiOsLiteTrixieImageName
    $imagePath = Join-Path $CacheDir $imageName
    if (Test-Path -LiteralPath $imagePath) {
        return (Resolve-Path -LiteralPath $imagePath).Path
    }

    $archivePath = "$imagePath.xz"
    if (Test-Path -LiteralPath $archivePath) {
        return (Expand-ImageIfNeeded $archivePath)
    }

    return ""
}

function Get-OfficialRpiOsLiteTrixieEntry {
    New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
    $osListPath = Join-Path $CacheDir "os_list_imagingutility_v4.json"
    Invoke-WebRequest -Uri $OsListUrl -OutFile $osListPath
    $json = Get-Content -LiteralPath $osListPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $targetFile = "$(Get-PinnedRpiOsLiteTrixieImageName).xz"

    function Walk-Items {
        param($Items, [string] $Path)
        foreach ($item in @($Items)) {
            $newPath = if ($Path) { "$Path > $($item.name)" } else { [string]$item.name }
            if ($item.url) {
                [pscustomobject]@{
                    Path = $newPath
                    Name = $item.name
                    Url = $item.url
                    Description = $item.description
                    ReleaseDate = $item.release_date
                    ExtractSize = $item.extract_size
                }
            }
            if ($item.subitems) {
                Walk-Items $item.subitems $newPath
            }
        }
    }

    $entry = Walk-Items $json.os_list "" |
        Where-Object {
            $fileName = [IO.Path]::GetFileName(([Uri]$_.Url).AbsolutePath)
            $fileName -eq $targetFile
        } |
        Select-Object -First 1

    if (-not $entry) {
        throw "Could not find pinned Raspberry Pi OS image in official OS list: $targetFile"
    }
    return $entry
}

function Save-RpiOsLiteTrixieImage {
    $cached = Get-CachedRpiOsLiteTrixieImage
    if (-not [string]::IsNullOrWhiteSpace($cached)) {
        [pscustomobject]@{
            Name = "Raspberry Pi OS Lite 64-bit Trixie"
            Version = "2026-04-21"
            Source = "cache"
            Image = $cached
            ImageSize = Format-Bytes ([UInt64](Get-Item -LiteralPath $cached).Length)
        }
        return
    }

    $entry = Get-OfficialRpiOsLiteTrixieEntry
    $fileName = [IO.Path]::GetFileName(([Uri]$entry.Url).AbsolutePath)
    $archivePath = Join-Path $CacheDir $fileName
    if (-not (Test-Path -LiteralPath $archivePath)) {
        Write-Host "Downloading Raspberry Pi OS Lite 64-bit Trixie 2026-04-21"
        Write-Host $entry.Url
        Invoke-WebRequest -Uri $entry.Url -OutFile $archivePath
    }
    $imagePath = Expand-ImageIfNeeded $archivePath
    [pscustomobject]@{
        Name = "Raspberry Pi OS Lite 64-bit Trixie"
        Version = "2026-04-21"
        Source = $entry.Path
        ReleaseDate = $entry.ReleaseDate
        Archive = $archivePath
        Image = $imagePath
        ImageSize = Format-Bytes ([UInt64](Get-Item -LiteralPath $imagePath).Length)
    }
}

function Get-OfficialBootloaderEntry {
    param([string] $RequestedModel)

    New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
    $osListPath = Join-Path $CacheDir "os_list_imagingutility_v4.json"
    Invoke-WebRequest -Uri $OsListUrl -OutFile $osListPath
    $json = Get-Content -LiteralPath $osListPath -Raw -Encoding UTF8 | ConvertFrom-Json

    $targetPath = if ($RequestedModel -eq "pi5") {
        "Misc utility images > Bootloader (Pi 5 family) > Network Boot"
    } else {
        "Misc utility images > Bootloader (Pi 4 family) > Network Boot"
    }

    function Walk-Items {
        param($Items, [string] $Path)
        foreach ($item in @($Items)) {
            $newPath = if ($Path) { "$Path > $($item.name)" } else { [string]$item.name }
            if ($item.url) {
                [pscustomobject]@{
                    Path = $newPath
                    Name = $item.name
                    Url = $item.url
                    Description = $item.description
                    ReleaseDate = $item.release_date
                    ExtractSize = $item.extract_size
                }
            }
            if ($item.subitems) {
                Walk-Items $item.subitems $newPath
            }
        }
    }

    $entry = Walk-Items $json.os_list "" |
        Where-Object { $_.Path -eq $targetPath } |
        Select-Object -First 1

    if (-not $entry) {
        throw "Could not find official entry: $targetPath"
    }
    return $entry
}

function Save-OfficialBootloaderImage {
    param([string] $RequestedModel)

    $entry = Get-OfficialBootloaderEntry $RequestedModel
    $fileName = [IO.Path]::GetFileName(([Uri]$entry.Url).AbsolutePath)
    $zipPath = Join-Path $CacheDir $fileName
    if (-not (Test-Path -LiteralPath $zipPath)) {
        Write-Host "Downloading $($entry.Path)"
        Write-Host $entry.Url
        Invoke-WebRequest -Uri $entry.Url -OutFile $zipPath
    }
    $imagePath = Expand-ImageIfNeeded $zipPath
    [pscustomobject]@{
        Model = $RequestedModel
        Path = $entry.Path
        Description = $entry.Description
        ReleaseDate = $entry.ReleaseDate
        Zip = $zipPath
        Image = $imagePath
        ImageSize = Format-Bytes ([UInt64](Get-Item -LiteralPath $imagePath).Length)
    }
}

function Clear-TargetDiskForImage {
    param([Parameter(Mandatory = $true)] $Disk)

    Set-Disk -Number $Disk.Number -IsOffline $false -ErrorAction SilentlyContinue
    Set-Disk -Number $Disk.Number -IsReadOnly $false -ErrorAction SilentlyContinue
    Clear-Disk -Number $Disk.Number -RemoveData -Confirm:$false
    Start-Sleep -Seconds 1
}

function Write-RawImage {
    param(
        [Parameter(Mandatory = $true)][string] $ImagePath,
        [Parameter(Mandatory = $true)] $Disk
    )

    $source = [IO.File]::Open($ImagePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $targetPath = "\\.\PhysicalDrive$($Disk.Number)"
    $target = [IO.File]::Open($targetPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
    try {
        $buffer = New-Object byte[] (4MB)
        $total = [UInt64]$source.Length
        $written = [UInt64]0
        while (($read = $source.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $target.Write($buffer, 0, $read)
            $written += [UInt64]$read
            $percent = if ($total -gt 0) { [int](($written * 100) / $total) } else { 0 }
            Write-Progress -Activity "Writing image to PhysicalDrive$($Disk.Number)" -Status "$(Format-Bytes $written) / $(Format-Bytes $total)" -PercentComplete $percent
        }
        $target.Flush($true)
        Write-Progress -Activity "Writing image to PhysicalDrive$($Disk.Number)" -Completed
    } finally {
        $target.Dispose()
        $source.Dispose()
    }
}

function Verify-RawImage {
    param(
        [Parameter(Mandatory = $true)][string] $ImagePath,
        [Parameter(Mandatory = $true)] $Disk
    )

    Ensure-BufferComparer
    $source = [IO.File]::Open($ImagePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $targetPath = "\\.\PhysicalDrive$($Disk.Number)"
    $target = [IO.File]::Open($targetPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $left = New-Object byte[] (4MB)
        $right = New-Object byte[] (4MB)
        $total = [UInt64]$source.Length
        $checked = [UInt64]0
        while (($read = $source.Read($left, 0, $left.Length)) -gt 0) {
            $targetRead = $target.Read($right, 0, $read)
            if ($targetRead -ne $read) {
                throw "Verification failed: target ended early at $(Format-Bytes $checked)."
            }
            if (-not [RpiSdCard.BufferComparer]::Equals($left, $right, $read)) {
                throw "Verification failed in block starting at byte offset $checked."
            }
            $checked += [UInt64]$read
            $percent = if ($total -gt 0) { [int](($checked * 100) / $total) } else { 0 }
            Write-Progress -Activity "Verifying PhysicalDrive$($Disk.Number)" -Status "$(Format-Bytes $checked) / $(Format-Bytes $total)" -PercentComplete $percent
        }
        Write-Progress -Activity "Verifying PhysicalDrive$($Disk.Number)" -Completed
    } finally {
        $target.Dispose()
        $source.Dispose()
    }
}

function Get-FreeDriveLetter {
    $used = @{}
    foreach ($volume in @(Get-Volume -ErrorAction SilentlyContinue)) {
        if ($volume.DriveLetter) {
            $used[[string]$volume.DriveLetter] = $true
        }
    }
    foreach ($letter in @("R", "S", "T", "U", "V", "W", "X", "Y", "Z")) {
        if (-not $used.ContainsKey($letter)) {
            return $letter
        }
    }
    throw "No free temporary drive letter is available for the Raspberry Pi OS boot partition."
}

function Resolve-RpiOsBootPartition {
    param([Parameter(Mandatory = $true)][int] $DiskNumber)

    for ($attempt = 0; $attempt -lt 12; $attempt++) {
        $partitions = @(Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue | Sort-Object PartitionNumber)
        foreach ($partition in $partitions) {
            $volume = $partition | Get-Volume -ErrorAction SilentlyContinue
            if ($volume -and $volume.FileSystem -eq "FAT32" -and $volume.FileSystemLabel -eq "bootfs") {
                return $partition
            }
        }
        foreach ($partition in $partitions) {
            if ($partition.PartitionNumber -eq 1 -and [UInt64]$partition.Size -le 1GB) {
                return $partition
            }
        }
        Start-Sleep -Milliseconds 750
    }

    throw "Could not find the Raspberry Pi OS bootfs partition on PhysicalDrive$DiskNumber."
}

function Get-RpiProvisionUserData {
    param(
        [Parameter(Mandatory = $true)][string] $Server,
        [Parameter(Mandatory = $true)][int] $Port
    )

    $template = @'
#cloud-config
hostname: rpi-provision
manage_etc_hosts: true
ssh_pwauth: false
write_files:
  - path: /usr/local/sbin/rpi-netboot-report.py
    owner: root:root
    permissions: '0755'
    content: |
      #!/usr/bin/env python3
      import json
      import os
      import socket
      import subprocess
      import time
      import urllib.request

      SERVER = "__SERVER__"
      PORT = __PORT__

      def read_text(path):
          try:
              with open(path, "rb") as handle:
                  return handle.read().decode("utf-8", "ignore").strip("\x00 \t\r\n")
          except Exception:
              return ""

      def run(args):
          try:
              return subprocess.check_output(args, stderr=subprocess.DEVNULL, text=True, timeout=8).strip()
          except Exception:
              return ""

      def run_shell(command):
          try:
              return subprocess.check_output(command, shell=True, stderr=subprocess.DEVNULL, text=True, timeout=8).strip()
          except Exception:
              return ""

      def cpu_serial():
          try:
              with open("/proc/cpuinfo", "r", encoding="utf-8", errors="ignore") as handle:
                  for line in handle:
                      if line.lower().startswith("serial"):
                          value = line.split(":", 1)[1].strip().lower()
                          return value[-8:] if len(value) > 8 else value
          except Exception:
              pass
          return ""

      def primary_ip():
          text = run(["hostname", "-I"]).split()
          if text:
              return text[0]
          try:
              sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
              sock.connect((SERVER, PORT))
              ip = sock.getsockname()[0]
              sock.close()
              return ip
          except Exception:
              return ""

      def boot_order(config):
          for line in config.splitlines():
              if line.startswith("BOOT_ORDER="):
                  return line.split("=", 1)[1].strip()
          return ""

      eeprom_config = run(["vcgencmd", "bootloader_config"])
      payload = {
          "source": "rpios-provision-sd",
          "serial": cpu_serial(),
          "mac": read_text("/sys/class/net/eth0/address").lower(),
          "ip": primary_ip(),
          "hostname": socket.gethostname(),
          "model": read_text("/proc/device-tree/model"),
          "boot_order": boot_order(eeprom_config),
          "eeprom_update": run_shell("rpi-eeprom-update 2>/dev/null | head -n 20"),
      }

      url = "http://{}:{}/provision/report".format(SERVER, PORT)
      for attempt in range(1, 61):
          payload["attempt"] = attempt
          payload["uptime_seconds"] = int(float(read_text("/proc/uptime").split()[0])) if read_text("/proc/uptime") else 0
          data = json.dumps(payload, sort_keys=True).encode("utf-8")
          request = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")
          try:
              with urllib.request.urlopen(request, timeout=5) as response:
                  if 200 <= response.status < 300:
                      raise SystemExit(0)
          except Exception:
              time.sleep(5)
      raise SystemExit(1)
runcmd:
  - [ sh, -xc, "systemctl enable ssh 2>/dev/null || true" ]
  - [ sh, -xc, "systemctl start ssh 2>/dev/null || true" ]
  - [ sh, -xc, "python3 /usr/local/sbin/rpi-netboot-report.py || true" ]
'@

    return $template.Replace("__SERVER__", $Server).Replace("__PORT__", [string]$Port)
}

function Patch-RpiOsProvisioning {
    param(
        [Parameter(Mandatory = $true)][int] $DiskNumber,
        [Parameter(Mandatory = $true)][string] $Server,
        [Parameter(Mandatory = $true)][int] $Port
    )

    $storageRefresh = Get-Command Update-HostStorageCache -ErrorAction SilentlyContinue
    if ($storageRefresh) {
        Update-HostStorageCache
    }

    $partition = Resolve-RpiOsBootPartition -DiskNumber $DiskNumber
    $assignedLetter = $false
    $accessPath = $null
    $letter = [string]$partition.DriveLetter
    if ([string]::IsNullOrWhiteSpace($letter)) {
        $letter = Get-FreeDriveLetter
        $accessPath = "$letter`:\"
        Add-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber $partition.PartitionNumber -AccessPath $accessPath
        $assignedLetter = $true
        Start-Sleep -Milliseconds 750
    } else {
        $accessPath = "$letter`:\"
    }

    try {
        if (-not (Test-Path -LiteralPath $accessPath)) {
            throw "Bootfs access path is not mounted: $accessPath"
        }
        $userData = Get-RpiProvisionUserData -Server $Server -Port $Port
        $metaData = @(
            "instance_id: rpi-netboot-provision-$([DateTime]::UtcNow.ToString("yyyyMMddHHmmss"))",
            "local-hostname: rpi-provision",
            "dsmode: local"
        ) -join "`n"
        $networkConfig = @(
            "network:",
            "  version: 2",
            "  ethernets:",
            "    eth0:",
            "      dhcp4: true",
            "      optional: true"
        ) -join "`n"

        Set-Content -LiteralPath (Join-Path $accessPath "user-data") -Value $userData -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $accessPath "meta-data") -Value $metaData -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $accessPath "network-config") -Value $networkConfig -Encoding ASCII
        Write-Host "Provisioning patch applied to bootfs on PhysicalDrive$DiskNumber."
        Write-Host "Provision report target: http://$Server`:$Port/provision/report"
    } finally {
        if ($assignedLetter -and $accessPath) {
            Remove-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber $partition.PartitionNumber -AccessPath $accessPath -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-WriteImageCommand {
    param([string] $RequestedImage)

    if (-not $IUnderstand) {
        throw "Refusing to write without -IUnderstand. This will erase the target disk."
    }
    Assert-Admin
    if ([string]::IsNullOrWhiteSpace($RequestedImage)) {
        throw "write-image requires -Image."
    }
    $imagePath = Expand-ImageIfNeeded $RequestedImage
    $imageSize = [UInt64](Get-Item -LiteralPath $imagePath).Length
    $disk = Resolve-TargetDisk
    Assert-TargetDiskSafe -Disk $disk -ImageSize $imageSize

    Write-Host "Target: PhysicalDrive$($disk.Number) $($disk.FriendlyName) $(Format-Bytes ([UInt64]$disk.Size))"
    Write-Host "Image:  $imagePath $(Format-Bytes $imageSize)"
    Clear-TargetDiskForImage $disk
    Write-RawImage -ImagePath $imagePath -Disk $disk
    if (-not $NoVerify) {
        Verify-RawImage -ImagePath $imagePath -Disk $disk
    }
    $storageRefresh = Get-Command Update-HostStorageCache -ErrorAction SilentlyContinue
    if ($storageRefresh) {
        Update-HostStorageCache
    }
    $script:LastWrittenDiskNumber = $disk.Number
    $script:LastWrittenImagePath = $imagePath
    Write-Host "Image write completed."
}

function Invoke-VerifyImageCommand {
    param([string] $RequestedImage)

    Assert-Admin
    if ([string]::IsNullOrWhiteSpace($RequestedImage)) {
        throw "verify-image requires -Image."
    }
    $imagePath = Expand-ImageIfNeeded $RequestedImage
    $imageSize = [UInt64](Get-Item -LiteralPath $imagePath).Length
    $disk = Resolve-TargetDisk
    if ($imageSize -gt [UInt64]$disk.Size) {
        throw "Image size $(Format-Bytes $imageSize) is larger than disk size $(Format-Bytes ([UInt64]$disk.Size))."
    }

    Write-Host "Target: PhysicalDrive$($disk.Number) $($disk.FriendlyName) $(Format-Bytes ([UInt64]$disk.Size))"
    Write-Host "Image:  $imagePath $(Format-Bytes $imageSize)"
    Verify-RawImage -ImagePath $imagePath -Disk $disk
    Write-Host "Image verification completed."
}

switch ($Command) {
    "list" {
        Get-RpiSdDiskRows | Format-Table -AutoSize
    }
    "download-eeprom-network" {
        Save-OfficialBootloaderImage $Model | Format-List
    }
    "prepare-eeprom-network" {
        $download = Save-OfficialBootloaderImage $Model
        Invoke-WriteImageCommand $download.Image
    }
    "download-rpios-lite-trixie" {
        Save-RpiOsLiteTrixieImage | Format-List
    }
    "prepare-rpios-lite-trixie" {
        $download = Save-RpiOsLiteTrixieImage
        Invoke-WriteImageCommand $download.Image
        if (-not $NoProvision) {
            Patch-RpiOsProvisioning -DiskNumber $script:LastWrittenDiskNumber -Server $ProvisionServer -Port $ProvisionPort
        }
    }
    "write-image" {
        Invoke-WriteImageCommand $Image
    }
    "verify-image" {
        Invoke-VerifyImageCommand $Image
    }
}
