$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $PSScriptRoot "RpiNetbootManagerGui.cs"
$icon = Join-Path $PSScriptRoot "rpi-netboot.ico"
$manifest = Join-Path $PSScriptRoot "app.manifest"
$target = Join-Path $projectRoot "RPI-Netboot-Manager.exe"

$csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path -LiteralPath $csc)) {
    $csc = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe"
}
if (-not (Test-Path -LiteralPath $csc)) {
    throw "csc.exe was not found."
}

if (-not (Test-Path -LiteralPath $icon)) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "make-icon.ps1")
}

& $csc /nologo /target:winexe /optimize+ /platform:anycpu /codepage:65001 `
    /reference:System.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll `
    /win32manifest:$manifest /win32icon:$icon /out:$target $source
if ($LASTEXITCODE -ne 0) {
    throw "Failed to build normal GUI."
}

[pscustomobject]@{
    GuiExe = $target
    Icon = $icon
    Compiler = $csc
}
