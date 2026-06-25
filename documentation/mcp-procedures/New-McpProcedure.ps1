#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProcedureId,
    [string]$ProcedureName,
    [string]$ProceduresDirectory = (Join-Path $PSScriptRoot "procedures"),
    [string]$TemplatePath = (Join-Path $PSScriptRoot "templates\mcp-procedure-template.md")
)

$ErrorActionPreference = "Stop"

function Convert-ToSafeFileName {
    param([Parameter(Mandatory)][string]$Value)
    $safe = ($Value.Trim().ToLowerInvariant() -replace '[^a-z0-9_.-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safe)) { throw "ProcedureId produced an empty filename." }
    return $safe
}

if ([string]::IsNullOrWhiteSpace($ProcedureName)) {
    $ProcedureName = $ProcedureId
}

if (-not (Test-Path -LiteralPath $TemplatePath)) {
    throw "Template not found: $TemplatePath"
}

if (-not (Test-Path -LiteralPath $ProceduresDirectory)) {
    New-Item -ItemType Directory -Path $ProceduresDirectory -Force | Out-Null
}

$safeId = Convert-ToSafeFileName -Value $ProcedureId
$outPath = Join-Path $ProceduresDirectory "$safeId.mcp.md"
if (Test-Path -LiteralPath $outPath) {
    throw "Procedure already exists: $outPath"
}

$content = Get-Content -LiteralPath $TemplatePath -Raw
$content = $content.Replace("<procedure name>", $ProcedureName)
$content = $content.Replace("<lowercase-id>", $safeId)
Set-Content -LiteralPath $outPath -Value $content -Encoding UTF8

Write-Host "Created MCP procedure: $outPath"
