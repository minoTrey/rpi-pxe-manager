[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("preflight", "inspect-rootfs", "start-attempt", "finish-attempt", "collect-latest", "classify-latest")]
    [string] $Command = "collect-latest",

    [string] $Config = ".\windows\lab-10.73.json",
    [string] $Serial = "d80c0b88",
    [string] $Mac = "88:a2:9e:4f:a9:b1",
    [string] $PiIp = "10.73.0.155",
    [ValidateSet("WinNFSd", "haneWIN", "LinuxNFS", "Unknown")]
    [string] $Provider = "WinNFSd",
    [ValidateSet("systemd-default", "systemd-explicit", "busybox-static", "bin-sh", "unknown")]
    [string] $InitVariant = "busybox-static",
    [string] $OutRoot = "D:\logs\netboot-harness",
    [string] $AttemptId = "",
    [string] $ConsoleText = "",
    [int] $WindowSeconds = 90
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$BootLog = "D:\logs\rpi-boot-lite.log"
$NfsStdoutLog = if ($Provider -eq "haneWIN") {
    $portableLog = "D:\logs\hanewin-portable.stdout.log"
    if (Test-Path -LiteralPath $portableLog) {
        $portableLog
    } else {
        $latestHaneWinLog = Get-ChildItem "C:\Program Files\nfsd" -Filter "nfsd*.log" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latestHaneWinLog) { $latestHaneWinLog.FullName } else { "C:\Program Files\nfsd\nfsd2605.log" }
    }
} else {
    "D:\logs\winnfsd.stdout.log"
}
$NfsStderrLog = "D:\logs\winnfsd.stderr.log"

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

function Get-FileSnapshot {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            path = $Path
            exists = $false
        }
    }
    $item = Get-Item -LiteralPath $Path -Force
    $hash = $null
    if (-not $item.PSIsContainer) {
        $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
    [pscustomobject]@{
        path = $Path
        exists = $true
        type = if ($item.PSIsContainer) { "directory" } else { "file" }
        length = if ($item.PSIsContainer) { $null } else { $item.Length }
        attributes = [string]$item.Attributes
        linkType = $item.LinkType
        target = @($item.Target)
        lastWriteTime = $item.LastWriteTime.ToString("o")
        sha256 = $hash
    }
}

function Get-LogState {
    $logs = @($BootLog, $NfsStdoutLog, $NfsStderrLog)
    $states = @()
    foreach ($path in $logs) {
        if (Test-Path -LiteralPath $path) {
            $item = Get-Item -LiteralPath $path
            $states += [pscustomobject]@{
                path = $path
                exists = $true
                length = $item.Length
                lastWriteTime = $item.LastWriteTime.ToString("o")
            }
        } else {
            $states += [pscustomobject]@{
                path = $path
                exists = $false
                length = 0
                lastWriteTime = $null
            }
        }
    }
    $states
}

function Read-NewText {
    param([string] $Path, [int64] $Offset)
    if (-not (Test-Path -LiteralPath $Path)) { return "" }
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        if ($Offset -gt $fs.Length) { $Offset = 0 }
        $fs.Seek($Offset, [IO.SeekOrigin]::Begin) | Out-Null
        $reader = [IO.StreamReader]::new($fs, [Text.Encoding]::UTF8, $true)
        return $reader.ReadToEnd()
    } finally {
        if ($reader) { $reader.Dispose() }
        $fs.Dispose()
    }
}

function Get-TextWindow {
    param([string] $Path, [int] $TailLines = 220)
    if (-not (Test-Path -LiteralPath $Path)) { return "" }
    (Get-Content -LiteralPath $Path -Tail $TailLines -ErrorAction SilentlyContinue) -join [Environment]::NewLine
}

function Get-Paths {
    $cfg = Read-LabConfig
    $tftpRoot = if ($cfg.tftp_root) { [string]$cfg.tftp_root } else { "D:\tftp" }
    $rootfsRoot = if ($cfg.nfs_root) { [string]$cfg.nfs_root } else { "D:\rootfs" }
    [pscustomobject]@{
        Config = (Resolve-Path -LiteralPath $Config).Path
        TftpRoot = $tftpRoot
        RootfsRoot = $rootfsRoot
        Tftp = Join-Path $tftpRoot $Serial
        Rootfs = Join-Path $rootfsRoot $Serial
        Cmdline = Join-Path (Join-Path $tftpRoot $Serial) "cmdline.txt"
        ConfigTxt = Join-Path (Join-Path $tftpRoot $Serial) "config.txt"
    }
}

function Get-PortSnapshot {
    $rows = @()
    foreach ($port in @(67, 69, 111, 2049, 3260)) {
        foreach ($endpoint in @(Get-NetUDPEndpoint -LocalPort $port -ErrorAction SilentlyContinue)) {
            $proc = Get-Process -Id $endpoint.OwningProcess -ErrorAction SilentlyContinue
            $rows += [pscustomobject]@{
                protocol = "UDP"
                localAddress = $endpoint.LocalAddress
                localPort = $port
                processId = $endpoint.OwningProcess
                processName = if ($proc) { $proc.ProcessName } else { $null }
            }
        }
        foreach ($endpoint in @(Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue)) {
            $proc = Get-Process -Id $endpoint.OwningProcess -ErrorAction SilentlyContinue
            $rows += [pscustomobject]@{
                protocol = "TCP"
                localAddress = $endpoint.LocalAddress
                localPort = $port
                state = $endpoint.State
                processId = $endpoint.OwningProcess
                processName = if ($proc) { $proc.ProcessName } else { $null }
            }
        }
    }
    $rows
}

function Get-TftpManifest {
    $paths = Get-Paths
    $important = @(
        "start4.elf",
        "fixup4.dat",
        "config.txt",
        "cmdline.txt",
        "kernel8.img",
        "initramfs8",
        "bcm2711-rpi-4-b.dtb",
        "overlays\overlay_map.dtb",
        "overlays\vc4-kms-v3d-pi4.dtbo"
    )
    $items = @()
    foreach ($name in $important) {
        $items += Get-FileSnapshot (Join-Path $paths.Tftp $name)
    }
    [pscustomobject]@{
        serial = $Serial
        tftp = $paths.Tftp
        files = $items
        cmdline = if (Test-Path -LiteralPath $paths.Cmdline) { (Get-Content -LiteralPath $paths.Cmdline -Raw -Encoding ASCII).Trim() } else { $null }
        configContainsAutoInitramfs = if (Test-Path -LiteralPath $paths.ConfigTxt) { ((Get-Content -LiteralPath $paths.ConfigTxt -Raw -Encoding UTF8) -match "(?m)^auto_initramfs=1\s*$") } else { $false }
    }
}

function Inspect-RootfsExec {
    $paths = Get-Paths
    $root = $paths.Rootfs
    $critical = @(
        "sbin\init",
        "usr\sbin\init",
        "usr\sbin\init.systemd-before-busybox",
        "usr\lib\systemd\systemd",
        "bin\sh",
        "usr\bin\sh",
        "usr\bin\dash",
        "lib\ld-linux-aarch64.so.1",
        "usr\lib\ld-linux-aarch64.so.1",
        "usr\lib\aarch64-linux-gnu\ld-linux-aarch64.so.1",
        "BOOT-NFS-BUSYBOX-DIAGNOSTIC.txt",
        "etc\fstab",
        "dev\console"
    )
    $files = @()
    foreach ($name in $critical) {
        $files += Get-FileSnapshot (Join-Path $root $name)
    }
    $busyboxMarker = Test-Path -LiteralPath (Join-Path $root "BOOT-NFS-BUSYBOX-DIAGNOSTIC.txt")
    $init = Get-FileSnapshot (Join-Path $root "usr\sbin\init")
    $backup = Get-FileSnapshot (Join-Path $root "usr\sbin\init.systemd-before-busybox")
    [pscustomobject]@{
        serial = $Serial
        rootfs = $root
        busyboxDiagnosticActive = [bool]$busyboxMarker
        currentInitLength = $init.length
        currentInitSha256 = $init.sha256
        systemdBackupExists = [bool]$backup.exists
        files = $files
    }
}

function Get-Preflight {
    $cfg = Read-LabConfig
    $paths = Get-Paths
    $volumes = @(Get-Volume -ErrorAction SilentlyContinue | Sort-Object DriveLetter | Select-Object DriveLetter, FileSystemLabel, FileSystem, DriveType, HealthStatus, SizeRemaining, Size)
    $ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Sort-Object InterfaceAlias,IPAddress | Select-Object InterfaceAlias, IPAddress, PrefixLength, AddressState)
    $router = Test-NetConnection -ComputerName ([string]$cfg.router_ip) -InformationLevel Quiet
    [pscustomobject]@{
        timestamp = (Get-Date).ToString("o")
        config = $paths.Config
        serverIp = [string]$cfg.server_ip
        routerIp = [string]$cfg.router_ip
        serial = $Serial
        mac = $Mac
        piIp = $PiIp
        paths = $paths
        routerPing = [bool]$router
        ports = @(Get-PortSnapshot)
        volumes = $volumes
        ipv4 = $ips
        logs = @(Get-LogState)
    }
}

function New-AttemptId {
    "{0}-{1}-{2}-{3}" -f (Get-Date -Format "yyyyMMdd-HHmmss"), $Serial, $Provider.ToLowerInvariant(), $InitVariant.ToLowerInvariant()
}

function Get-AttemptDir {
    param([string] $Id)
    Join-Path $OutRoot $Id
}

function Start-Attempt {
    $id = if ([string]::IsNullOrWhiteSpace($AttemptId)) { New-AttemptId } else { $AttemptId }
    $dir = Get-AttemptDir $id
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    $state = [pscustomobject]@{
        attemptId = $id
        startedAt = (Get-Date).ToString("o")
        serial = $Serial
        mac = $Mac
        piIp = $PiIp
        provider = $Provider
        initVariant = $InitVariant
        logState = @(Get-LogState)
    }
    Save-Json $state (Join-Path $dir "attempt-start.json")
    Save-Json (Get-Preflight) (Join-Path $dir "preflight.json")
    Save-Json (Get-TftpManifest) (Join-Path $dir "tftp-manifest.json")
    Save-Json (Inspect-RootfsExec) (Join-Path $dir "rootfs-exec-inspection.json")
    Set-Content -LiteralPath (Join-Path $OutRoot "latest-attempt.txt") -Value $id -Encoding ASCII

    $timeline = @(
        "# Netboot Attempt $id",
        "",
        "- Started: $($state.startedAt)",
        "- Serial: $Serial",
        "- MAC: $Mac",
        "- Pi IP: $PiIp",
        "- Provider: $Provider",
        "- Init variant: $InitVariant",
        "",
        "Power-cycle the SD-less Pi now, then run `finish-attempt`."
    )
    Set-Content -LiteralPath (Join-Path $dir "timeline.md") -Value $timeline -Encoding UTF8
    Write-Check "OK" "attempt started" $id
    Write-Check "NEXT" "power cycle" "Power-cycle the SD-less RPi4, then run finish-attempt."
}

function Get-StartState {
    param([string] $Id)
    if ([string]::IsNullOrWhiteSpace($Id)) {
        $latest = Join-Path $OutRoot "latest-attempt.txt"
        if (-not (Test-Path -LiteralPath $latest)) {
            throw "AttemptId was not provided and latest-attempt.txt was not found."
        }
        $Id = (Get-Content -LiteralPath $latest -Raw -Encoding ASCII).Trim()
    }
    $dir = Get-AttemptDir $Id
    $statePath = Join-Path $dir "attempt-start.json"
    if (-not (Test-Path -LiteralPath $statePath)) {
        throw "Attempt start state not found: $statePath"
    }
    [pscustomobject]@{
        id = $Id
        dir = $dir
        state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
}

function Select-LogOffset {
    param([object] $State, [string] $Path)
    foreach ($entry in @($State.logState)) {
        if ([string]::Equals([string]$entry.path, $Path, [StringComparison]::OrdinalIgnoreCase)) {
            return [int64]$entry.length
        }
    }
    0
}

function Classify-Evidence {
    param(
        [string] $BootText,
        [string] $NfsText,
        [string] $ConsoleText,
        [object] $RootfsInspection,
        [object] $TftpManifest
    )

    $escapedMac = [regex]::Escape($Mac)
    $escapedPiIp = [regex]::Escape($PiIp)
    $escapedSerial = [regex]::Escape($Serial)
    $dhcpPass = $BootText -match "(?im)^.*DHCP\s+ACK\s+$escapedMac\s*->\s*$escapedPiIp\b"
    $tftpStarted = $BootText -match "(?im)TFTP\s+GET\s+$escapedPiIp`:\d+\s+$escapedSerial/"
    $kernelPass = $BootText -match "(?im)TFTP\s+DONE\s+$escapedPiIp`:\d+\s+$escapedSerial/kernel8\.img\b"
    $cmdlinePass = $BootText -match "(?im)TFTP\s+DONE\s+$escapedPiIp`:\d+\s+$escapedSerial/cmdline\.txt\b"
    $dtbPass = $BootText -match "(?im)TFTP\s+DONE\s+$escapedPiIp`:\d+\s+$escapedSerial/bcm2711-rpi-4-b\.dtb\b"
    $initramfsPass = $BootText -match "(?im)TFTP\s+GET\s+$escapedPiIp`:\d+\s+$escapedSerial/initramfs8\b" -and $BootText -match "(?im)TFTP\s+DONE\s+$escapedPiIp`:\d+\s+$escapedSerial/initramfs8\b"
    $nfsMountPass =
        $NfsText -match "(?im)\bMOUNT\b.*\b(MNT|from|$escapedPiIp)\b" -or
        $NfsText -match "(?im)\bmount3\b.*\b$escapedPiIp\b" -or
        $NfsText -match "(?im)mountd:\s+name\s+rpi/$escapedSerial\s+-->" -or
        $NfsText -match "(?im)\b$escapedPiIp\b.*\b(mount|mnt|nfs)\b" -or
        $NfsText -match "(?im)\bFinal local requested path\b.*$escapedSerial"
    $nfsMountInvalidArgument = $ConsoleText -match "(?i)(nfs\s+mount.*invalid argument|mount:\s+invalid argument)"
    $nfsRootReadPass =
        $NfsText -match "\\usr\\sbin\\init" -or
        $NfsText -match "/usr/sbin/init" -or
        $NfsText -match "\\sbin\\init" -or
        $NfsText -match "/sbin/init" -or
        $NfsText -match "\\etc\\fstab" -or
        $NfsText -match "/etc/fstab"
    $initRead = $NfsText -match "\\usr\\sbin\\init" -or $NfsText -match "/usr/sbin/init" -or $NfsText -match "\\bin\\busybox" -or $NfsText -match "/bin/busybox"
    $error14 = $ConsoleText -match "(?i)(error\s*[-=]?\s*14|EFAULT|Requested init .*failed)"
    $noInit = $ConsoleText -match "No working init found"
    $busyboxActive = [bool]$RootfsInspection.busyboxDiagnosticActive
    $repeatDhcpAfterNfs = $nfsMountPass -and (($BootText | Select-String -Pattern "DHCP ACK" -AllMatches).Matches.Count -ge 2)

    $passed = @()
    if ($dhcpPass) { $passed += "DHCP" }
    if ($tftpStarted) { $passed += "TFTP_STARTED" }
    if ($kernelPass) { $passed += "TFTP_KERNEL" }
    if ($cmdlinePass) { $passed += "TFTP_CMDLINE" }
    if ($dtbPass) { $passed += "TFTP_DTB" }
    if ($initramfsPass) { $passed += "INITRAMFS_TRANSFER" }
    if ($nfsMountPass) { $passed += "NFS_MOUNT" }
    if ($nfsRootReadPass) { $passed += "NFS_ROOT_READ" }
    if ($initRead) { $passed += "INIT_READ" }

    $category = "UNKNOWN"
    $likelyArea = "needs more evidence"
    $confidence = "low"
    $missing = @()

    if (-not $dhcpPass) {
        $category = "DHCP_FAIL"
        $likelyArea = "DHCP, link, adapter, router isolation"
        $confidence = "medium"
    } elseif (-not $tftpStarted) {
        $category = "TFTP_NOT_STARTED"
        $likelyArea = "DHCP boot options or TFTP port"
        $confidence = "medium"
    } elseif (-not ($kernelPass -and $cmdlinePass -and $dtbPass)) {
        $category = "TFTP_BOOTFILE_FAIL"
        $likelyArea = "TFTP file set, timeout, boot prefix"
        $confidence = "medium"
    } elseif ($TftpManifest.configContainsAutoInitramfs -and -not $initramfsPass) {
        $category = "INITRAMFS_MISSING_OR_FAIL"
        $likelyArea = "TFTP initramfs transfer"
        $confidence = "medium"
    } elseif ($nfsMountInvalidArgument) {
        $category = "NFS_MOUNT_INVALID_ARGUMENT"
        $likelyArea = "NFS provider mount protocol/options compatibility"
        $confidence = "high"
    } elseif (-not $nfsMountPass) {
        $category = "NFS_MOUNT_FAIL"
        $likelyArea = if ($nfsMountInvalidArgument) { "NFS provider mount protocol/options compatibility" } else { "NFS provider, portmap, nfsroot path, firewall" }
        $confidence = if ($nfsMountInvalidArgument) { "high" } else { "medium-high" }
    } elseif (-not $nfsRootReadPass) {
        $category = "NFS_ROOT_READ_FAIL"
        $likelyArea = "NFS export contents or rootfs path"
        $confidence = "medium"
    } elseif ($error14 -or $noInit -or ($initRead -and $repeatDhcpAfterNfs)) {
        $category = "INIT_EXEC_FAIL_PROBABLE"
        $likelyArea = "NFS root ELF execution, provider file representation, rootfs metadata"
        $confidence = if ($error14 -or $noInit) { "high" } else { "medium-high" }
    } elseif ($initRead) {
        $category = "INIT_EXEC_REACHED"
        $likelyArea = "init started or console evidence missing"
        $confidence = "medium"
        $missing += "Pi HDMI/serial console text"
    }

    if ([string]::IsNullOrWhiteSpace($ConsoleText)) {
        $missing += "Pi HDMI/serial console text"
    }

    [pscustomobject]@{
        category = $category
        passed = $passed
        diagnostic = if ($busyboxActive) { "BUSYBOX_DIAGNOSTIC_ACTIVE" } else { "SYSTEMD_OR_UNKNOWN_INIT" }
        provider = $Provider
        initVariant = $InitVariant
        likelyArea = $likelyArea
        confidence = $confidence
        missingEvidence = $missing
        facts = [pscustomobject]@{
            dhcpPass = $dhcpPass
            tftpStarted = $tftpStarted
            kernelPass = $kernelPass
            cmdlinePass = $cmdlinePass
            dtbPass = $dtbPass
            initramfsPass = $initramfsPass
            nfsMountPass = $nfsMountPass
            nfsRootReadPass = $nfsRootReadPass
            initRead = $initRead
            consoleError14 = $error14
            consoleNoWorkingInit = $noInit
            consoleNfsMountInvalidArgument = $nfsMountInvalidArgument
            busyboxDiagnosticActive = $busyboxActive
            repeatDhcpAfterNfs = $repeatDhcpAfterNfs
        }
    }
}

function Save-TextIfAny {
    param([string] $Path, [string] $Text)
    Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8
}

function Finish-Attempt {
    $attempt = Get-StartState $AttemptId
    $dir = $attempt.dir
    $state = $attempt.state

    $bootText = Read-NewText $BootLog (Select-LogOffset $state $BootLog)
    $nfsText = Read-NewText $NfsStdoutLog (Select-LogOffset $state $NfsStdoutLog)
    $nfsErrText = Read-NewText $NfsStderrLog (Select-LogOffset $state $NfsStderrLog)
    Save-TextIfAny (Join-Path $dir "rpi-boot-lite.delta.log") $bootText
    Save-TextIfAny (Join-Path $dir ("{0}.stdout.delta.log" -f $Provider.ToLowerInvariant())) $nfsText
    Save-TextIfAny (Join-Path $dir "winnfsd.stderr.delta.log") $nfsErrText
    Save-TextIfAny (Join-Path $dir "console.txt") $ConsoleText

    $rootfs = Inspect-RootfsExec
    $tftp = Get-TftpManifest
    Save-Json $rootfs (Join-Path $dir "rootfs-exec-inspection.after.json")
    Save-Json $tftp (Join-Path $dir "tftp-manifest.after.json")
    Save-Json (Get-PortSnapshot) (Join-Path $dir "ports-after.json")

    $verdict = Classify-Evidence -BootText $bootText -NfsText $nfsText -ConsoleText $ConsoleText -RootfsInspection $rootfs -TftpManifest $tftp
    Save-Json $verdict (Join-Path $dir "verdict.json")

    $timeline = @(
        "# Netboot Attempt $($attempt.id)",
        "",
        "- Started: $($state.startedAt)",
        "- Finished: $((Get-Date).ToString("o"))",
        "- Serial: $Serial",
        "- MAC: $Mac",
        "- Pi IP: $PiIp",
        "- Provider: $Provider",
        "- Init variant: $InitVariant",
        "- Verdict: **$($verdict.category)**",
        "- Diagnostic: $($verdict.diagnostic)",
        "- Likely area: $($verdict.likelyArea)",
        "- Confidence: $($verdict.confidence)",
        "",
        "## Passed",
        "",
        (($verdict.passed | ForEach-Object { "- $_" }) -join [Environment]::NewLine),
        "",
        "## Missing Evidence",
        "",
        ($(if ($verdict.missingEvidence.Count -gt 0) { ($verdict.missingEvidence | ForEach-Object { "- $_" }) -join [Environment]::NewLine } else { "- none" })),
        "",
        "## Next Thought",
        "",
        (Get-NextThought $verdict)
    )
    Set-Content -LiteralPath (Join-Path $dir "timeline.md") -Value $timeline -Encoding UTF8
    Save-Json ([pscustomobject]@{ latestAttempt = $attempt.id; verdict = $verdict }) (Join-Path $OutRoot "latest-verdict.json")

    Write-Check "OK" "attempt finished" $attempt.id
    Write-Check "VERDICT" $verdict.category "$($verdict.likelyArea), confidence=$($verdict.confidence)"
    Write-Check "EVIDENCE" "folder" $dir
}

function Get-NextThought {
    param([object] $Verdict)
    switch ($Verdict.category) {
        "INIT_EXEC_FAIL_PROBABLE" {
            if ($Verdict.diagnostic -eq "BUSYBOX_DIAGNOSTIC_ACTIVE") {
                return "Static busybox init also failed, so prioritize NFS provider or rootfs file representation over systemd. The next experiment is the same bootfs/rootfs exported by Linux nfs-kernel-server."
            }
            return "The systemd init path failed. Use the busybox-static init variant to separate NFS exec behavior from the dynamic linker and systemd chain."
        }
        "NFS_MOUNT_FAIL" { return "TFTP passed. Check nfsroot path, NFS export alias, portmap/NFS listener, and firewall first." }
        "NFS_MOUNT_INVALID_ARGUMENT" { return "The Pi reached NFS mount negotiation, but the provider/options combination was rejected. Move the same bootfs/rootfs to Linux nfs-kernel-server for the next A/B test." }
        "TFTP_BOOTFILE_FAIL" { return "DHCP passed. Check TFTP prefix, boot file set, and timeout patterns first." }
        "DHCP_FAIL" { return "The Pi did not find the server. Check link, VLAN/AP isolation, DHCP listener, and MAC reservation first." }
        default { return "Add console evidence and classify the same attempt again with finish-attempt." }
    }
}

function Collect-Latest {
    $dir = Join-Path $OutRoot ("latest-{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmss"), $Serial)
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $bootText = Get-TextWindow $BootLog 260
    $nfsText = Get-TextWindow $NfsStdoutLog 220
    Save-TextIfAny (Join-Path $dir "rpi-boot-lite.tail.log") $bootText
    Save-TextIfAny (Join-Path $dir ("{0}.stdout.tail.log" -f $Provider.ToLowerInvariant())) $nfsText
    Save-TextIfAny (Join-Path $dir "console.txt") $ConsoleText
    $preflight = Get-Preflight
    $tftp = Get-TftpManifest
    $rootfs = Inspect-RootfsExec
    $verdict = Classify-Evidence -BootText $bootText -NfsText $nfsText -ConsoleText $ConsoleText -RootfsInspection $rootfs -TftpManifest $tftp
    Save-Json $preflight (Join-Path $dir "preflight.json")
    Save-Json $tftp (Join-Path $dir "tftp-manifest.json")
    Save-Json $rootfs (Join-Path $dir "rootfs-exec-inspection.json")
    Save-Json $verdict (Join-Path $dir "verdict.json")
    Save-Json ([pscustomobject]@{ latestCollection = $dir; verdict = $verdict }) (Join-Path $OutRoot "latest-verdict.json")
    Write-Check "VERDICT" $verdict.category "$($verdict.likelyArea), confidence=$($verdict.confidence)"
    Write-Check "EVIDENCE" "folder" $dir
}

switch ($Command) {
    "preflight" {
        $data = Get-Preflight
        $data | ConvertTo-Json -Depth 8
    }
    "inspect-rootfs" {
        Inspect-RootfsExec | ConvertTo-Json -Depth 8
    }
    "start-attempt" {
        Start-Attempt
    }
    "finish-attempt" {
        Finish-Attempt
    }
    "collect-latest" {
        Collect-Latest
    }
    "classify-latest" {
        Collect-Latest
    }
}
