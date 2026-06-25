param(
  [string]$ImagesDir = ".\output\trace-images",
  [string]$OutputPath = ".\output\trace-images.md"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ImagesDir)) {
  throw "Images directory not found: $ImagesDir"
}

$repoRoot = (Get-Location).Path.TrimEnd('\')
$outputDir = Split-Path -Path $OutputPath -Parent
if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path -LiteralPath $outputDir)) {
  New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$images = Get-ChildItem -LiteralPath $ImagesDir -File -Include *.png, *.jpg, *.jpeg, *.webp |
  Sort-Object Name

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Trace Images (Ordered)")
$lines.Add("")
$lines.Add("- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add("- Source Folder: $ImagesDir")
$lines.Add("- Image Count: $($images.Count)")
$lines.Add("")

if ($images.Count -eq 0) {
  $lines.Add("No images found.")
}
else {
  $index = 1
  foreach ($img in $images) {
    if ($img.FullName.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
      $relative = $img.FullName.Substring($repoRoot.Length).TrimStart('\')
    }
    else {
      $relative = $img.FullName
    }
    $relative = $relative.Replace('\', '/')
    $lines.Add("## Frame $index")
    $lines.Add("")
    $lines.Add("- File: $relative")
    $lines.Add("")
    $lines.Add("![$($img.Name)]($relative)")
    $lines.Add("")
    $index++
  }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines((Join-Path $repoRoot $OutputPath), $lines, $utf8NoBom)
Write-Host "Trace image doc written to $OutputPath"
