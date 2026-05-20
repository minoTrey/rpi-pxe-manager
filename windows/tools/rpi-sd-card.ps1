param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet("list", "download-eeprom-network", "prepare-eeprom-network", "download-rpios-lite-trixie", "prepare-rpios-lite-trixie", "write-image")]
    [string] $Command,

    [ValidateSet("pi4", "pi5")]
    [string] $Model = "pi4",

    [int] $DiskNumber = -1,
    [string] $DriveLetter = "",
    [string] $Image = "",
    [string] $CacheDir = "",
    [string] $OsListUrl = "https://downloads.raspberrypi.com/os_list_imagingutility_v4.json",
    [int] $MaxDiskSizeGB = 64,

    [switch] $IUnderstand,
    [switch] $NoVerify,
    [switch] $AllowNonUsb,
    [switch] $AllowLargeDisk
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($CacheDir)) {
    $CacheDir = Join-Path (Split-Path -Parent $PSScriptRoot) "cache\downloads"
}

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
            for ($i = 0; $i -lt $read; $i++) {
                if ($left[$i] -ne $right[$i]) {
                    throw "Verification failed at byte offset $($checked + [UInt64]$i)."
                }
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
    Write-Host "Image write completed."
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
    }
    "write-image" {
        Invoke-WriteImageCommand $Image
    }
}
