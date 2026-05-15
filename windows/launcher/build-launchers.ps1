$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $PSScriptRoot "RpiNetbootManagerLauncher.cs"
$csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path -LiteralPath $csc)) {
    $csc = Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe"
}
if (-not (Test-Path -LiteralPath $csc)) {
    throw "csc.exe was not found."
}

$normal = Join-Path $projectRoot "RPI-Netboot-Manager.exe"
$admin = Join-Path $projectRoot "RPI-Netboot-Manager-Admin.exe"

& $csc /nologo /target:winexe /optimize+ /platform:anycpu /reference:System.Windows.Forms.dll /out:$normal $source
if ($LASTEXITCODE -ne 0) {
    throw "Failed to build $normal"
}

& $csc /nologo /target:winexe /optimize+ /platform:anycpu /reference:System.Windows.Forms.dll /out:$admin $source
if ($LASTEXITCODE -ne 0) {
    throw "Failed to build $admin"
}

[pscustomobject]@{
    NormalLauncher = $normal
    AdminLauncher = $admin
    Compiler = $csc
}
