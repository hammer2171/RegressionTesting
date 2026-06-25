param(
  [string]$ResultsRoot = ".\test-results",
  [string]$OutputPath = ".\output\playwright-evidence.md"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-AbsolutePath {
  param([string]$Path)
  return (Resolve-Path -LiteralPath $Path).Path
}

function Ensure-Directory {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

$repoRoot = (Get-Location).Path
$resultsAbs = Resolve-AbsolutePath -Path $ResultsRoot
$outputDir = Split-Path -Path $OutputPath -Parent
if ([string]::IsNullOrWhiteSpace($outputDir)) {
  $outputDir = "."
}
Ensure-Directory -Path $outputDir

$screenshots = Get-ChildItem -LiteralPath $resultsAbs -Recurse -File -Include *.png |
  Sort-Object LastWriteTime -Descending

$repoRootNormalized = $repoRoot.TrimEnd('\')

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Playwright Screenshot Evidence")
$lines.Add("")
$lines.Add("- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add("- Results Root: $ResultsRoot")
$lines.Add("- Screenshot Count: $($screenshots.Count)")
$lines.Add("")

if ($screenshots.Count -eq 0) {
  $lines.Add("No screenshots were found in $ResultsRoot.")
  $lines.Add("")
  $lines.Add("Run tests with screenshot capture enabled, then rebuild this report:")
  $lines.Add("")
  $lines.Add("- npx playwright test --headed --trace on --screenshot on tests/oracle-epm-0057_import_all_maps.cleaned.spec.ts")
  $lines.Add("- npm run evidence:build")
}
else {
  $lines.Add("## Artifacts")
  $lines.Add("")
  foreach ($shot in $screenshots) {
    if ($shot.FullName.StartsWith($repoRootNormalized, [System.StringComparison]::OrdinalIgnoreCase)) {
      $relative = $shot.FullName.Substring($repoRootNormalized.Length).TrimStart('\')
    }
    else {
      $relative = $shot.FullName
    }
    $relative = $relative.Replace('\', '/')
    $lines.Add("### $relative")
    $lines.Add("")
    $lines.Add("- Last Write: $($shot.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))")
    $lines.Add("")
    $lines.Add("![${relative}]($relative)")
    $lines.Add("")
  }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines((Join-Path $repoRoot $OutputPath), $lines, $utf8NoBom)
Write-Host "Evidence report written to $OutputPath"
