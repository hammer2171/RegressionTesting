param(
  [string]$SnippetPath = ".\Run-Mapping-Playwright_snippet_of_code2.txt",
  [string]$OutputPath = ".\output\Playwright_Skill_Guide.docx",
  [string]$Title = "Playwright Pod Skill Guide"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $SnippetPath)) {
  throw "Snippet file not found: $SnippetPath"
}

function Is-CommandLine {
  param([string]$Line)
  if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
  $trim = $Line.Trim()
  return (
    $trim -match '^\$env:' -or
    $trim -match '^npm\s' -or
    $trim -match '^npx\s' -or
    $trim -match '^node\s' -or
    $trim -match '^cd\s' -or
    $trim -match '^Get-' -or
    $trim -match '^Copy-' -or
    $trim -match '^New-Item' -or
    $trim -match '^Test-Path' -or
    $trim -match '^param\(' -or
    $trim -match '^#\s*\d+\)'
  )
}

function Sanitize-Line {
  param([string]$Line)
  $out = $Line
  $out = $out -replace '(?i)(EPM_PASSWORD\s*=\s*).+', '$1XXXX'
  $out = $out -replace '(?i)(EPM_USERNAME\s*=\s*)[^#\r\n]+', '$1XXXX'
  $out = $out -replace "(?i)(password['""]?\s*[:=]\s*['""])[^'""]+(['""])", '$1XXXX$2'
  $out = $out -replace "(?i)(fill\()['""][^'""]+(['""]\))", '$1XXXX$2'
  return $out
}

function Get-SectionDescription {
  param([string]$Heading)
  $h = $Heading.ToLowerInvariant()
  if ($h -like '*reauth*' -or $h -like '*auth*') { return "Authentication and storage-state setup commands." }
  if ($h -like '*evidence*' -or $h -like '*trace*') { return "Evidence capture and trace/report commands." }
  if ($h -like '*report*') { return "Reporter and result viewing commands." }
  if ($h -like '*codegen*' -or $h -like '*write tests*') { return "Test generation and recording commands." }
  if ($h -like '*play back*' -or $h -like '*run test*') { return "Test execution commands." }
  if ($h -like '*yml*') { return "Commands to inspect YAML output artifacts." }
  if ($h -like '*pod scrape*') { return "Pod scraping and discovery commands." }
  return "Operational Playwright snippet commands for this workflow section."
}

function New-BookmarkName {
  param(
    [string]$Heading,
    [int]$Index
  )
  $base = ($Heading.ToLowerInvariant() -replace '[^a-z0-9]+', '_').Trim('_')
  if ([string]::IsNullOrWhiteSpace($base)) {
    $base = "section"
  }
  if ($base.Length -gt 28) {
    $base = $base.Substring(0, 28)
  }
  return "sec_{0}_{1}" -f $Index, $base
}

$lines = Get-Content -LiteralPath $SnippetPath
$sections = New-Object System.Collections.Generic.List[object]
$current = $null
$buffer = New-Object System.Collections.Generic.List[string]

foreach ($line in $lines) {
  $trim = $line.Trim()
  if (-not [string]::IsNullOrWhiteSpace($trim) -and -not (Is-CommandLine -Line $trim) -and -not $trim.StartsWith("--")) {
    if ($current -ne $null -or $buffer.Count -gt 0) {
      $sections.Add([PSCustomObject]@{
        Heading = if ($current) { $current } else { "General Commands" }
        Commands = @($buffer)
      })
      $buffer.Clear()
    }
    $current = $trim
    continue
  }

  if (-not [string]::IsNullOrWhiteSpace($trim)) {
    $buffer.Add((Sanitize-Line -Line $line))
  }
}

if ($current -ne $null -or $buffer.Count -gt 0) {
  $sections.Add([PSCustomObject]@{
    Heading = if ($current) { $current } else { "General Commands" }
    Commands = @($buffer)
  })
}

$outputDir = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path -LiteralPath $outputDir)) {
  New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$word = $null
$doc = $null
try {
  $word = New-Object -ComObject Word.Application
  $word.Visible = $false
  $doc = $word.Documents.Add()
  $sel = $word.Selection

  $wdCollapseEnd = 0
  $wdStyleHeading1 = -2
  $wdStyleHeading2 = -3
  $wdStyleNormal = -1
  $wdPageBreak = 7

  $sel.Style = $doc.Styles.Item($wdStyleHeading1)
  $sel.TypeText($Title)
  $sel.TypeParagraph()
  $sel.Style = $doc.Styles.Item($wdStyleNormal)
  $sel.TypeText("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
  $sel.TypeParagraph()
  $sel.TypeText("Source snippet: $SnippetPath")
  $sel.TypeParagraph()
  $sel.TypeParagraph()

  $tocInsertPos = $sel.Range.End
  $tocEntries = New-Object System.Collections.Generic.List[object]
  $sectionIndex = 1

  foreach ($section in $sections) {
    $sel.Style = $doc.Styles.Item($wdStyleHeading1)
    $headingStart = $sel.Range.Start
    $sel.TypeText($section.Heading)
    $headingEnd = $sel.Range.End
    $bookmarkName = New-BookmarkName -Heading $section.Heading -Index $sectionIndex
    [void]$doc.Bookmarks.Add($bookmarkName, $doc.Range($headingStart, $headingEnd))
    $tocEntries.Add([PSCustomObject]@{ Title = $section.Heading; Bookmark = $bookmarkName })
    $sectionIndex++
    $sel.TypeParagraph()

    $sel.Style = $doc.Styles.Item($wdStyleNormal)
    $sel.TypeText((Get-SectionDescription -Heading $section.Heading))
    $sel.TypeParagraph()
    $sel.TypeParagraph()

    $sel.Style = $doc.Styles.Item($wdStyleHeading2)
    $sel.TypeText("Snippet")
    $sel.TypeParagraph()

    $sel.Style = $doc.Styles.Item($wdStyleNormal)
    foreach ($cmd in $section.Commands) {
      if ([string]::IsNullOrWhiteSpace($cmd)) {
        $sel.TypeParagraph()
      } else {
        $sel.Font.Name = "Consolas"
        $sel.Font.Size = 10
        $sel.TypeText($cmd)
        $sel.TypeParagraph()
      }
    }
    $sel.Font.Name = "Calibri"
    $sel.Font.Size = 11
    $sel.TypeParagraph()
  }

  $sel.Style = $doc.Styles.Item($wdStyleHeading1)
  $headingStart = $sel.Range.Start
  $sel.TypeText("Transition Rule")
  $headingEnd = $sel.Range.End
  $bookmarkName = New-BookmarkName -Heading "Transition Rule" -Index $sectionIndex
  [void]$doc.Bookmarks.Add($bookmarkName, $doc.Range($headingStart, $headingEnd))
  $tocEntries.Add([PSCustomObject]@{ Title = "Transition Rule"; Bookmark = $bookmarkName })
  $sectionIndex++
  $sel.TypeParagraph()
  $sel.Style = $doc.Styles.Item($wdStyleNormal)
  $sel.TypeText("For this run only, start from C:\epm22_test\Mappings\ExportMapping. After this setup, use C:\Playwright_development for all pod operations.")
  $sel.TypeParagraph()
  $sel.Font.Name = "Consolas"
  $sel.Font.Size = 10
  $sel.TypeText("powershell -NoProfile -ExecutionPolicy Bypass -File C:\epm22_test\Mappings\ExportMapping\scripts\New-PlaywrightPodWorkspace.ps1")
  $sel.TypeParagraph()
  $sel.TypeText("powershell -NoProfile -ExecutionPolicy Bypass -File C:\Playwright_development\tools\New-PlaywrightPodWorkspace.ps1")
  $sel.TypeParagraph()
  $sel.TypeText("powershell -NoProfile -ExecutionPolicy Bypass -File C:\Playwright_development\tools\Sync-PodScripts.ps1")
  $sel.TypeParagraph()
  $sel.Font.Name = "Calibri"
  $sel.Font.Size = 11
  $sel.TypeParagraph()

  $sel.Style = $doc.Styles.Item($wdStyleHeading1)
  $headingStart = $sel.Range.Start
  $sel.TypeText("Pod Bootstrap Best Practice")
  $headingEnd = $sel.Range.End
  $bookmarkName = New-BookmarkName -Heading "Pod Bootstrap Best Practice" -Index $sectionIndex
  [void]$doc.Bookmarks.Add($bookmarkName, $doc.Range($headingStart, $headingEnd))
  $tocEntries.Add([PSCustomObject]@{ Title = "Pod Bootstrap Best Practice"; Bookmark = $bookmarkName })
  $sectionIndex++
  $sel.TypeParagraph()
  $sel.Style = $doc.Styles.Item($wdStyleNormal)
  $sel.TypeText("Run pod setup from C:\ so all pod folders are created under C:\Playwright_development.")
  $sel.TypeParagraph()
  $sel.Font.Name = "Consolas"
  $sel.Font.Size = 10
  $sel.TypeText("powershell -NoProfile -ExecutionPolicy Bypass -File C:\epm22_test\Mappings\ExportMapping\scripts\New-PlaywrightPodWorkspace.ps1")
  $sel.TypeParagraph()
  $sel.TypeText("powershell -NoProfile -ExecutionPolicy Bypass -File C:\epm22_test\Mappings\ExportMapping\scripts\New-PlaywrightPodWorkspace.ps1 -PodFolderName 11_test_FCCS -PodUrl https://<pod-url> -TemplatePodFolder 22_test_FCCS")
  $sel.TypeParagraph()
  $sel.TypeText("powershell -NoProfile -ExecutionPolicy Bypass -File C:\epm22_test\Mappings\ExportMapping\scripts\New-PlaywrightPodWorkspace.ps1 -PodFolderName 11_test_FCCS -PodUrl https://<pod-url> -TemplatePath C:\Playwright_development\22_test_FCCS")
  $sel.TypeParagraph()
  $sel.Font.Name = "Calibri"
  $sel.Font.Size = 11
  $sel.TypeParagraph()

  $sel.Style = $doc.Styles.Item($wdStyleHeading1)
  $headingStart = $sel.Range.Start
  $sel.TypeText("Runs Folder Retention")
  $headingEnd = $sel.Range.End
  $bookmarkName = New-BookmarkName -Heading "Runs Folder Retention" -Index $sectionIndex
  [void]$doc.Bookmarks.Add($bookmarkName, $doc.Range($headingStart, $headingEnd))
  $tocEntries.Add([PSCustomObject]@{ Title = "Runs Folder Retention"; Bookmark = $bookmarkName })
  $sectionIndex++
  $sel.TypeParagraph()
  $sel.Style = $doc.Styles.Item($wdStyleNormal)
  $sel.TypeText("Archive every evidence run into a timestamped Runs folder to preserve trace, report, and UI evidence artifacts.")
  $sel.TypeParagraph()
  $sel.Font.Name = "Consolas"
  $sel.Font.Size = 10
  $sel.TypeText("npm run evidence:archive-latest -- --label <test_name>")
  $sel.TypeParagraph()
  $sel.TypeText("npm run test:epm22:import-all-maps-cleaned:e2e:evidence:full:archived")
  $sel.TypeParagraph()
  $sel.Font.Name = "Calibri"
  $sel.Font.Size = 11
  $sel.TypeParagraph()

  $sel.Style = $doc.Styles.Item($wdStyleHeading1)
  $headingStart = $sel.Range.Start
  $sel.TypeText("Parameterized Auth Refresh")
  $headingEnd = $sel.Range.End
  $bookmarkName = New-BookmarkName -Heading "Parameterized Auth Refresh" -Index $sectionIndex
  [void]$doc.Bookmarks.Add($bookmarkName, $doc.Range($headingStart, $headingEnd))
  $tocEntries.Add([PSCustomObject]@{ Title = "Parameterized Auth Refresh"; Bookmark = $bookmarkName })
  $sectionIndex++
  $sel.TypeParagraph()
  $sel.Style = $doc.Styles.Item($wdStyleNormal)
  $sel.TypeText("Use parameterized auth commands to prevent collaborators from writing credentials to user.json.")
  $sel.TypeParagraph()
  $sel.Font.Name = "Consolas"
  $sel.Font.Size = 10
  $sel.TypeText("npm run auth:refresh -- -UserKey user")
  $sel.TypeParagraph()
  $sel.TypeText("npm run auth:refresh -- -UserKey aigul")
  $sel.TypeParagraph()
  $sel.TypeText("npm run auth:refresh -- -UserKey aigul -PodKey 11_test_fccs -BaseUrl https://<pod-url>")
  $sel.TypeParagraph()
  $sel.Font.Name = "Calibri"
  $sel.Font.Size = 11
  $sel.TypeText("Storage naming: user -> playwright/.auth/user.json; collaborator -> playwright/.auth/<name>.json; collaborator+pod -> playwright/.auth/<name>.<podkey>.json")
  $sel.TypeParagraph()

  $tocRange = $doc.Range($tocInsertPos, $tocInsertPos)
  $tocRange.InsertAfter("Table of Contents (Hyperlinked)`r`n")
  $tocRange.Collapse($wdCollapseEnd) | Out-Null
  foreach ($entry in $tocEntries) {
    [void]$doc.Hyperlinks.Add($tocRange, "", $entry.Bookmark, "", $entry.Title)
    $tocRange.InsertAfter("`r`n")
    $tocRange.Collapse($wdCollapseEnd) | Out-Null
  }
  $tocRange.InsertAfter("`r`n")
  $tocRange.Collapse($wdCollapseEnd) | Out-Null

  $fullOut = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $OutputPath))
  $doc.SaveAs([string]$fullOut, 16) | Out-Null
  Write-Host "Word guide written to $fullOut"
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
