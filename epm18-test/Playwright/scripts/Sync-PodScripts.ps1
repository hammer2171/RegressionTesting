param(
  [string]$SourcePod,
  [string]$TargetPod,
  [string]$RootPath = "C:\Playwright_development",
  [string]$FallbackSourceScripts = "C:\epm22_test\Mappings\ExportMapping\scripts"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Prompt-IfEmpty {
  param([string]$Value, [string]$Prompt)
  if (-not [string]::IsNullOrWhiteSpace($Value)) { return $Value }
  return (Read-Host $Prompt)
}

$SourcePod = Prompt-IfEmpty -Value $SourcePod -Prompt "Enter source pod folder (example: 22_test_FCCS)"
$TargetPod = Prompt-IfEmpty -Value $TargetPod -Prompt "Enter target pod folder (example: 11_test_FCCS)"

$sourceScripts = Join-Path (Join-Path $RootPath $SourcePod) "scripts"
$targetScripts = Join-Path (Join-Path $RootPath $TargetPod) "scripts"

if (-not (Test-Path -LiteralPath $targetScripts)) {
  New-Item -ItemType Directory -Path $targetScripts -Force | Out-Null
}

if (Test-Path -LiteralPath $sourceScripts) {
  Copy-Item -Path (Join-Path $sourceScripts "*") -Destination $targetScripts -Recurse -Force
  Write-Host "Synced scripts from pod source:"
  Write-Host "  $sourceScripts"
}
elseif (Test-Path -LiteralPath $FallbackSourceScripts) {
  Copy-Item -Path (Join-Path $FallbackSourceScripts "*") -Destination $targetScripts -Recurse -Force
  Write-Host "Source pod scripts not found. Used fallback source:"
  Write-Host "  $FallbackSourceScripts"
}
else {
  throw "No script source found. Checked:`n  $sourceScripts`n  $FallbackSourceScripts"
}

Write-Host "Target scripts folder:"
Write-Host "  $targetScripts"

Get-ChildItem -LiteralPath $targetScripts -File |
  Sort-Object Name |
  Select-Object Name, LastWriteTime |
  Format-Table -AutoSize
