#Requires -Version 5.1

<#
.SYNOPSIS
    Runs a Playwright MCP Procedure.

.DESCRIPTION
    Version 1

    - Validates the procedure exists.
    - Validates the evidence protocol exists.
    - Creates a timestamped run folder.
    - Copies procedure and protocol into the run folder.
    - Builds an MCP prompt.
    - Copies the prompt to the clipboard.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Procedure,

    [string]$Root = "C:\RegressionTesting",

    [switch]$Headed
)

Write-Host "Procedure = '$Procedure'"

$ErrorActionPreference = "Stop"

#
# Paths
#

$ProcedureRoot      = Join-Path $Root "documentation\mcp-procedures"
$ProceduresFolder   = Join-Path $ProcedureRoot "procedures"
$ProcedureFile      = Join-Path $ProceduresFolder $Procedure
$EvidenceProtocol   = Join-Path $ProcedureRoot "evidence-protocol.md"

#
# Validate
#

if (!(Test-Path $ProcedureFile)) {
    throw "Procedure not found:`n$ProcedureFile"
}

if (!(Test-Path $EvidenceProtocol)) {
    throw "Evidence protocol not found:`n$EvidenceProtocol"
}

#
# Run Folder
#

$TimeStamp = Get-Date -Format "yyyyMMdd-HHmmss"

$RunFolder = Join-Path $Root "epm18-test\Runs\$TimeStamp"

New-Item `
    -ItemType Directory `
    -Path $RunFolder `
    -Force | Out-Null

Copy-Item `
    -LiteralPath $ProcedureFile `
    -Destination (Join-Path $RunFolder "procedure.md") `
    -Force

Copy-Item `
    -LiteralPath $EvidenceProtocol `
    -Destination (Join-Path $RunFolder "evidence-protocol.md") `
    -Force

#
# MCP Prompt
#

$Prompt = @"
Use Playwright MCP.

Run in headed mode.

Read and execute:

$ProcedureFile

Follow the evidence protocol:

$EvidenceProtocol

Store all screenshots,
videos,
logs,
trace files,
and evidence into:

$RunFolder

When complete return:

• Pass / Fail

• Summary

• Blockers

• Evidence Generated

"@

$PromptFile = Join-Path $RunFolder "mcp-prompt.txt"

$Prompt | Set-Content `
    -LiteralPath $PromptFile `
    -Encoding UTF8

#
# Clipboard
#

try {
    Set-Clipboard -Value $Prompt
    $ClipboardStatus = "Prompt copied to clipboard."
}
catch {
    $ClipboardStatus = "Unable to copy prompt to clipboard."
}

#
# Output
#

Write-Host ""
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host " Playwright MCP Procedure Runner v1" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Procedure:"
Write-Host "  $ProcedureFile"
Write-Host ""

Write-Host "Evidence Protocol:"
Write-Host "  $EvidenceProtocol"
Write-Host ""

Write-Host "Run Folder:"
Write-Host "  $RunFolder"
Write-Host ""

Write-Host "Prompt File:"
Write-Host "  $PromptFile"
Write-Host ""

Write-Host $ClipboardStatus -ForegroundColor Green
Write-Host ""

Write-Host "===============================================" -ForegroundColor Yellow
Write-Host " MCP PROMPT" -ForegroundColor Yellow
Write-Host "===============================================" -ForegroundColor Yellow
Write-Host ""

Write-Host $Prompt
Write-Host ""

Write-Host "Done."

