[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("status", "event")]
    [string] $Command = "status",

    [string] $KnowledgeRoot = ".\windows\knowledge",
    [string] $Type = "note",
    [string] $Summary = "",
    [string] $Attempt = "",
    [string] $Provider = "",
    [string] $Verdict = ""
)

$ErrorActionPreference = "Stop"

function Resolve-KnowledgeRoot {
    if (Test-Path -LiteralPath $KnowledgeRoot) {
        return (Resolve-Path -LiteralPath $KnowledgeRoot).Path
    }
    throw "Knowledge root not found: $KnowledgeRoot"
}

function Write-HermesEvent {
    $root = Resolve-KnowledgeRoot
    $path = Join-Path $root "hermes\events.jsonl"
    $parent = Split-Path -Parent $path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $event = [ordered]@{
        ts = (Get-Date).ToString("o")
        type = $Type
        summary = $Summary
    }
    if (-not [string]::IsNullOrWhiteSpace($Attempt)) { $event.attempt = $Attempt }
    if (-not [string]::IsNullOrWhiteSpace($Provider)) { $event.provider = $Provider }
    if (-not [string]::IsNullOrWhiteSpace($Verdict)) { $event.verdict = $Verdict }
    ($event | ConvertTo-Json -Compress) | Add-Content -LiteralPath $path -Encoding UTF8
    "[OK] hermes event - $path"
}

function Show-CouncilStatus {
    $root = Resolve-KnowledgeRoot
    $files = @(
        "agent-council\README.md",
        "agent-council\action-queue.md",
        "agent-council\rounds\2026-05-19-1419-hanewin-minimal.md",
        "hermes\events.jsonl",
        "gbrain\graph.json",
        "obsidian-vault\Home.md"
    )
    foreach ($file in $files) {
        $path = Join-Path $root $file
        [pscustomobject]@{
            path = $path
            exists = Test-Path -LiteralPath $path
        }
    }
}

switch ($Command) {
    "status" { Show-CouncilStatus | Format-Table -AutoSize | Out-String }
    "event" { Write-HermesEvent }
}
