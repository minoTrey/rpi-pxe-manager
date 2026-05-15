param(
    [Parameter(Position = 0)]
    [ValidateSet("status", "apply")]
    [string] $Command = "status",

    [string] $DriveLetter = "S",
    [string] $Hostname = "rpizero2w-gadget",
    [switch] $Yes
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Write-Check {
    param(
        [ValidateSet("OK", "WARN", "NEED", "ERROR")]
        [string] $Status,
        [string] $Item,
        [string] $Detail
    )
    Write-Output ("[{0}] {1} - {2}" -f $Status, $Item, $Detail)
}

function Resolve-BootDrive {
    $letter = $DriveLetter.Trim().TrimEnd(":").ToUpperInvariant()
    if ($letter.Length -ne 1) {
        throw "DriveLetter must look like S or S:."
    }
    $root = $letter + ':\'
    if (-not (Test-Path -LiteralPath $root)) {
        throw "Drive not found: $root"
    }
    return $root
}

function Get-BootFiles {
    $root = Resolve-BootDrive
    [pscustomobject]@{
        Root = $root
        Config = Join-Path $root "config.txt"
        Cmdline = Join-Path $root "cmdline.txt"
        UserData = Join-Path $root "user-data"
    }
}

function Ensure-Pi02Config {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "config.txt not found: $Path"
    }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($text -match "(?m)^\[pi02\]\s*$" -and $text -match "(?m)^dtoverlay=dwc2,dr_mode=peripheral\s*$") {
        return
    }

    $insert = @(
        "",
        "# RPI Netboot Manager: Raspberry Pi Zero 2 W SD boot + USB Ethernet gadget",
        "[pi02]",
        "dtoverlay=dwc2,dr_mode=peripheral",
        "",
        "[all]"
    )
    Add-Content -LiteralPath $Path -Value $insert -Encoding UTF8
}

function Ensure-CmdlineGadget {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "cmdline.txt not found: $Path"
    }
    $cmdline = (Get-Content -LiteralPath $Path -Raw -Encoding UTF8).Trim()
    if ([string]::IsNullOrWhiteSpace($cmdline)) {
        throw "cmdline.txt is empty: $Path"
    }
    if ($cmdline -notmatch "(^|\s)modules-load=dwc2,g_ether(\s|$)") {
        if ($cmdline -match "(^|\s)rootwait(\s|$)") {
            $cmdline = [regex]::Replace($cmdline, "(^|\s)rootwait(\s|$)", '$1rootwait modules-load=dwc2,g_ether$2', 1)
        } else {
            $cmdline = "$cmdline modules-load=dwc2,g_ether"
        }
    }
    Set-Content -LiteralPath $Path -Value $cmdline -Encoding ASCII
}

function Ensure-CloudInitGadget {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($text -match "(?m)^\s*enable_usb_gadget:\s*true\s*$") {
        return $true
    }
    $block = @(
        "",
        "# RPI Netboot Manager: enable USB Ethernet gadget on Raspberry Pi OS Trixie.",
        "rpi:",
        "  enable_usb_gadget: true",
        "enable_ssh: true",
        "hostname: $Hostname"
    ) -join [Environment]::NewLine
    Add-Content -LiteralPath $Path -Value $block -Encoding UTF8
    return $true
}

function Show-GadgetStatus {
    $files = Get-BootFiles
    Write-Output "== Raspberry Pi Zero 2 W SD boot + USB gadget status =="
    Write-Output "Policy: Raspberry Pi 4 is the only network boot target. Zero 2 W keeps SD boot and exposes USB Ethernet gadget."
    Write-Check "OK" "boot drive" $files.Root

    foreach ($entry in @(
        @{ Name = "config.txt"; Path = $files.Config },
        @{ Name = "cmdline.txt"; Path = $files.Cmdline }
    )) {
        if (Test-Path -LiteralPath $entry.Path) {
            Write-Check "OK" $entry.Name $entry.Path
        } else {
            Write-Check "ERROR" $entry.Name "$($entry.Path) not found. Check that this is a Raspberry Pi OS boot partition."
        }
    }

    if (Test-Path -LiteralPath $files.Config) {
        $configText = Get-Content -LiteralPath $files.Config -Raw -Encoding UTF8
        if ($configText -match "(?m)^\[pi02\]\s*$" -and $configText -match "(?m)^dtoverlay=dwc2,dr_mode=peripheral\s*$") {
            Write-Check "OK" "Zero 2 W OTG config" "[pi02] dtoverlay=dwc2,dr_mode=peripheral"
        } else {
            Write-Check "NEED" "Zero 2 W OTG config" "config.txt needs the [pi02] gadget overlay."
        }
    }

    if (Test-Path -LiteralPath $files.Cmdline) {
        $cmdline = Get-Content -LiteralPath $files.Cmdline -Raw -Encoding UTF8
        if ($cmdline -match "(^|\s)modules-load=dwc2,g_ether(\s|$)") {
            Write-Check "OK" "g_ether module" "cmdline.txt contains modules-load=dwc2,g_ether."
        } else {
            Write-Check "NEED" "g_ether module" "cmdline.txt needs modules-load=dwc2,g_ether on its single line."
        }
    }

    if (Test-Path -LiteralPath $files.UserData) {
        $userData = Get-Content -LiteralPath $files.UserData -Raw -Encoding UTF8
        if ($userData -match "(?m)^\s*enable_usb_gadget:\s*true\s*$") {
            Write-Check "OK" "Trixie cloud-init" "user-data contains enable_usb_gadget true."
        } else {
            Write-Check "WARN" "Trixie cloud-init" "user-data exists but does not contain enable_usb_gadget. apply will add helper settings."
        }
    } else {
        Write-Check "WARN" "Trixie cloud-init" "user-data not found. This can be normal for Bookworm/manual g_ether images."
    }
}

function Apply-GadgetSettings {
    $files = Get-BootFiles
    if (-not $Yes) {
        Write-Check "WARN" "confirmation required" "Run apply with -Yes after confirming the target SD boot drive."
        Show-GadgetStatus
        return
    }

    Ensure-Pi02Config $files.Config
    Ensure-CmdlineGadget $files.Cmdline
    $cloudInitChanged = Ensure-CloudInitGadget $files.UserData

    $sshMarker = Join-Path $files.Root "ssh"
    if (-not (Test-Path -LiteralPath $sshMarker)) {
        New-Item -ItemType File -Path $sshMarker -Force | Out-Null
    }

    $note = Join-Path $files.Root "RPI-Zero2W-gadget-readme.txt"
    $noteText = @(
        "Raspberry Pi Zero 2 W SD boot + USB gadget",
        "==========================================",
        "",
        "This SD card was prepared by RPI Netboot Manager for Zero 2 W USB Ethernet gadget use.",
        "",
        "Policy:",
        "- Raspberry Pi 4 is the only network boot target.",
        "- Zero 2 W boots from this SD card and connects to the PC through the USB data port.",
        "- Use the Zero 2 W USB data port, not the PWR IN port.",
        "",
        "Applied settings:",
        "- config.txt: [pi02] dtoverlay=dwc2,dr_mode=peripheral",
        "- cmdline.txt: modules-load=dwc2,g_ether",
        "- user-data when present: rpi.enable_usb_gadget=true, enable_ssh=true",
        "- ssh marker file created",
        "",
        "After boot, Windows should show a USB Ethernet/RNDIS adapter."
    ) -join [Environment]::NewLine
    Set-Content -LiteralPath $note -Value $noteText -Encoding UTF8

    Write-Check "OK" "Zero 2 W SD boot + USB gadget" "boot partition patched."
    if ($cloudInitChanged) {
        Write-Check "OK" "Trixie cloud-init" "user-data gadget settings confirmed or added."
    }
    Write-Check "OK" "SSH marker" $sshMarker
    Write-Check "OK" "guide file" $note
    Show-GadgetStatus
}

switch ($Command) {
    "status" { Show-GadgetStatus }
    "apply" { Apply-GadgetSettings }
}
