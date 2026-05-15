param(
    [string] $Config = ".\lab-10.73.json",
    [string] $GeneratedTftp = ".\generated\lab-10.73\tftp",
    [switch] $VerifyOnly
)

$ErrorActionPreference = "Stop"

function Test-NonZeroFile {
    param([string] $Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -eq 0) { return $false }
    foreach ($byte in $bytes) {
        if ($byte -ne 0) { return $true }
    }
    return $false
}

$configObject = Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json
$targetTftp = $configObject.tftp_root

if (-not (Test-Path -LiteralPath $GeneratedTftp)) {
    throw "Generated TFTP folder not found: $GeneratedTftp"
}

if ($VerifyOnly) {
    if (-not (Test-Path -LiteralPath $targetTftp)) {
        throw "Target TFTP folder not found: $targetTftp"
    }
} else {
    New-Item -ItemType Directory -Force -Path $targetTftp | Out-Null
    Copy-Item -Path (Join-Path $GeneratedTftp "*") -Destination $targetTftp -Recurse -Force
}

$files = Get-ChildItem -LiteralPath $targetTftp -Recurse -File |
    Where-Object { $_.Name -eq "cmdline.txt" -or $_.Name -eq "config.txt" }
$bad = foreach ($file in $files) {
    if (-not (Test-NonZeroFile $file.FullName)) {
        $file.FullName
    }
}

$clientDirs = @(Get-ChildItem -LiteralPath $targetTftp -Directory).Count
$modeText = if ($VerifyOnly) { "읽기 전용 검증" } else { "복사 후 검증" }

Write-Output "[정상] TFTP 검증 모드 - $modeText"
Write-Output "[정상] TFTP 대상 폴더 - $targetTftp"
Write-Output "[정상] Pi별 TFTP 폴더 - ${clientDirs}개"
Write-Output "[정상] cmdline/config 검사 - $($files.Count)개 검사, 문제 $(@($bad).Count)개"

if (@($bad).Count -gt 0) {
    $bad | Select-Object -First 20
    throw "TFTP sync finished with invalid cmdline/config files."
}


