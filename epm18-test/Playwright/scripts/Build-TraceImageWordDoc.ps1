param(
  [string]$ImagesDir = ".\output\trace-images",
  [string]$OutputPath = ".\output\trace-images.docx"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ImagesDir)) {
  throw "Images directory not found: $ImagesDir"
}

$images = Get-ChildItem -LiteralPath $ImagesDir -File -Include *.png, *.jpg, *.jpeg |
  Sort-Object Name

if ($images.Count -eq 0) {
  throw "No PNG/JPG images found in $ImagesDir"
}

$outputDir = Split-Path -Path $OutputPath -Parent
if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path -LiteralPath $outputDir)) {
  New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$word = $null
$doc = $null

try {
  $word = New-Object -ComObject Word.Application
  $word.Visible = $false
  $doc = $word.Documents.Add()
  $selection = $word.Selection

  # Word constants
  $wdPageBreak = 7
  $wdCollapseEnd = 0
  $wdAlignParagraphCenter = 1
  $msoTrue = -1

  $pageWidth = $doc.PageSetup.PageWidth - $doc.PageSetup.LeftMargin - $doc.PageSetup.RightMargin
  $pageHeight = $doc.PageSetup.PageHeight - $doc.PageSetup.TopMargin - $doc.PageSetup.BottomMargin

  for ($i = 0; $i -lt $images.Count; $i++) {
    $img = $images[$i]
    $selection.EndKey() | Out-Null
    $selection.ParagraphFormat.Alignment = $wdAlignParagraphCenter

    $shape = $selection.InlineShapes.AddPicture($img.FullName, $false, $true)
    $shape.LockAspectRatio = $msoTrue

    $scaleRatio = [Math]::Min($pageWidth / $shape.Width, $pageHeight / $shape.Height)
    if ($scaleRatio -lt 1) {
      $shape.Width = [Math]::Floor($shape.Width * $scaleRatio)
    }

    if ($i -lt ($images.Count - 1)) {
      $selection.Collapse($wdCollapseEnd) | Out-Null
      $selection.InsertBreak($wdPageBreak) | Out-Null
    }
  }

  $outputFile = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $OutputPath))

  # 16 = wdFormatDocumentDefault (.docx)
  $doc.SaveAs([string]$outputFile, 16)
  Write-Host "Word doc written to $outputFile"
}
finally {
  if ($doc -ne $null) {
    $doc.Close($false) | Out-Null
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc)
  }
  if ($word -ne $null) {
    $word.Quit() | Out-Null
    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($word)
  }
  [GC]::Collect()
  [GC]::WaitForPendingFinalizers()
}
