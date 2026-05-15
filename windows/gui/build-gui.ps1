$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $PSScriptRoot "RpiNetbootManagerGui.cs"
$icon = Join-Path $PSScriptRoot "rpi-netboot.ico"
$manifest = Join-Path $PSScriptRoot "app.manifest"
$adminManifest = Join-Path $PSScriptRoot "app-admin.manifest"
$target = Join-Path $projectRoot "RPI-Netboot-Manager.exe"
$adminTarget = Join-Path $projectRoot "RPI-Netboot-Manager-Admin.exe"
$adminUpdateTarget = Join-Path $projectRoot "RPI-Netboot-Manager-Admin-Update.exe"

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

$adminGuiBuilt = $true
$adminGuiPath = $adminTarget
$adminProcess = Get-Process -Name "RPI-Netboot-Manager-Admin" -ErrorAction SilentlyContinue
if ($adminProcess) {
    $adminGuiPath = $adminUpdateTarget
    Write-Warning "RPI-Netboot-Manager-Admin.exe is running, so the updated admin GUI will be built as RPI-Netboot-Manager-Admin-Update.exe."
} else {
    if (Test-Path -LiteralPath $adminUpdateTarget) {
        try {
            Remove-Item -LiteralPath $adminUpdateTarget -Force
        } catch {
            Write-Warning "Could not remove stale RPI-Netboot-Manager-Admin-Update.exe. The GUI will prefer the newer admin exe by timestamp."
        }
    }
    & $csc /nologo /target:winexe /optimize+ /platform:anycpu /codepage:65001 `
        /reference:System.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll `
        /win32manifest:$adminManifest /win32icon:$icon /out:$adminTarget $source
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to build admin GUI."
    }
}

if ($adminProcess) {
    & $csc /nologo /target:winexe /optimize+ /platform:anycpu /codepage:65001 `
        /reference:System.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll `
        /win32manifest:$adminManifest /win32icon:$icon /out:$adminUpdateTarget $source
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to build updated admin GUI."
    }
}

[pscustomobject]@{
    GuiExe = $target
    AdminGuiExe = $adminGuiPath
    AdminGuiBuilt = $adminGuiBuilt
    Icon = $icon
    Compiler = $csc
}
