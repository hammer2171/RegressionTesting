#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProcedureId = "create-edm-request-sample-entity",
    [string]$ProcedureName = "Create-EDM-Request",
    [string]$ProceduresDirectory = "C:\RegressionTesting\documentation\mcp-procedures\procedures",
    [string]$TemplatePath = "C:\RegressionTesting\documentation\mcp-procedures\templates\create-edm-request-sample-entity.md"
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
