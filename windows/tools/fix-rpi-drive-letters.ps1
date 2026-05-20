param(
    [string] $RpiLabel = "rpi",
    [char] $RpiDrive = "D",
    [char] $SdDrive = "S"
)

$ErrorActionPreference = "Stop"

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script from an elevated PowerShell session."
    }
}

function Get-FreeDriveLetter {
    param([char[]] $Preferred)
    $used = @{}
    foreach ($volume in Get-Volume) {
        if ($volume.DriveLetter) {
            $used[[string]$volume.DriveLetter] = $true
        }
    }
    foreach ($letter in $Preferred) {
        if (-not $used.ContainsKey([string]$letter)) {
            return $letter
        }
    }
    throw "No free drive letter found."
}

Assert-Admin

$rpiVolume = Get-Volume |
    Where-Object {
        $_.FileSystemLabel -eq $RpiLabel -and
        $_.FileSystem -eq "NTFS" -and
        $_.DriveType -eq "Fixed"
    } |
    Select-Object -First 1

if (-not $rpiVolume) {
    throw "Could not find a fixed NTFS volume labeled '$RpiLabel'."
}

$rpiPartition = Get-Partition -DriveLetter $rpiVolume.DriveLetter
$desiredPartition = Get-Partition -DriveLetter $RpiDrive -ErrorAction SilentlyContinue

if ($desiredPartition) {
    $samePartition =
        $desiredPartition.DiskNumber -eq $rpiPartition.DiskNumber -and
        $desiredPartition.PartitionNumber -eq $rpiPartition.PartitionNumber

    if (-not $samePartition) {
        $newLetter = Get-FreeDriveLetter @($SdDrive, "T", "U", "V", "W", "X", "Y", "Z")
        Set-Partition -DiskNumber $desiredPartition.DiskNumber -PartitionNumber $desiredPartition.PartitionNumber -NewDriveLetter $newLetter
    }
}

$rpiPartition = Get-Partition -DiskNumber $rpiPartition.DiskNumber -PartitionNumber $rpiPartition.PartitionNumber
if ($rpiPartition.DriveLetter -ne $RpiDrive) {
    Set-Partition -DiskNumber $rpiPartition.DiskNumber -PartitionNumber $rpiPartition.PartitionNumber -NewDriveLetter $RpiDrive
}

Get-Volume | Sort-Object DriveLetter |
    Format-Table DriveLetter,FileSystemLabel,FileSystem,DriveType,HealthStatus,SizeRemaining,Size -AutoSize
