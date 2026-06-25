param(
  [Parameter(Mandatory = $true)]
  [string]$TraceZip,
  [string]$OutputDir = ".\output\trace-images"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-FileKind {
  param([byte[]]$Bytes)
  if ($Bytes.Length -ge 8 -and $Bytes[0] -eq 0x89 -and $Bytes[1] -eq 0x50 -and $Bytes[2] -eq 0x4E -and $Bytes[3] -eq 0x47) {
    return "png"
  }
  if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xD8 -and $Bytes[2] -eq 0xFF) {
    return "jpg"
  }
  if ($Bytes.Length -ge 12 -and
      $Bytes[0] -eq 0x52 -and $Bytes[1] -eq 0x49 -and $Bytes[2] -eq 0x46 -and $Bytes[3] -eq 0x46 -and
      $Bytes[8] -eq 0x57 -and $Bytes[9] -eq 0x45 -and $Bytes[10] -eq 0x42 -and $Bytes[11] -eq 0x50) {
    return "webp"
  }
  return $null
}

if (-not (Test-Path -LiteralPath $TraceZip)) {
  throw "Trace zip not found: $TraceZip"
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
  New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("pw-trace-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
  Expand-Archive -LiteralPath $TraceZip -DestinationPath $tempRoot -Force
  $allFiles = Get-ChildItem -LiteralPath $tempRoot -Recurse -File
  $index = 1
  $saved = 0

  foreach ($file in $allFiles) {
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    if ($bytes.Length -eq 0) {
      continue
    }

    $kind = Get-FileKind -Bytes $bytes
    if (-not $kind) {
      continue
    }

    $dest = Join-Path $OutputDir ("trace-image-{0:D4}.{1}" -f $index, $kind)
    [System.IO.File]::WriteAllBytes($dest, $bytes)
    $index++
    $saved++
  }

  Write-Host "Extracted $saved image(s) to $OutputDir"
}
finally {
  if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
  }
}
