#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$Folders,
    [string]$RegressionRoot = "C:\RegressionTesting",
    [string]$TemplateRoot,
    [switch]$CopyTemplates
)

$ErrorActionPreference = "Stop"

$PodFolders = @(
    "documentation",
    "reference",
    "scripts",
    "Runs",
    "Playwright"
)

$PlaywrightFolders = @(
    "components",
    "docs",
    "output",
    "pages",
    "playwright",
    "scripts",
    "snippets",
    "tests"
)

function Write-HostLine {
    param([string]$Message)
    Write-Host "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"), $Message
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )
    if (-not (Test-Path -LiteralPath $Source)) {
        return
    }
    Ensure-Directory -Path $Destination
    robocopy $Source $Destination /E /XD node_modules Runs run runs test-results playwright-report blob-report .git /XF *.zip | Out-Host
    if ($LASTEXITCODE -gt 7) {
        throw "Robocopy failed copying '$Source' to '$Destination' with exit code $LASTEXITCODE"
    }
}

foreach ($folder in $Folders) {
    $safeFolder = ($folder.Trim() -replace '[\\/:*?"<>|]+', '-')
    if ([string]::IsNullOrWhiteSpace($safeFolder)) {
        throw "Folder names cannot be blank."
    }

    $podRoot = Join-Path $RegressionRoot $safeFolder
    $playwrightRoot = Join-Path $podRoot "Playwright"
    Write-HostLine "Provisioning $podRoot"
    Ensure-Directory -Path $podRoot

    foreach ($sub in $PodFolders) {
        Ensure-Directory -Path (Join-Path $podRoot $sub)
    }

    foreach ($sub in $PlaywrightFolders) {
        Ensure-Directory -Path (Join-Path $playwrightRoot $sub)
    }

    if ($CopyTemplates -and -not [string]::IsNullOrWhiteSpace($TemplateRoot)) {
        foreach ($sub in $PodFolders) {
            Copy-DirectoryContents -Source (Join-Path $TemplateRoot $sub) -Destination (Join-Path $podRoot $sub)
        }
        foreach ($sub in $PlaywrightFolders) {
            Copy-DirectoryContents -Source (Join-Path $TemplateRoot "Playwright\$sub") -Destination (Join-Path $playwrightRoot $sub)
        }
        Copy-DirectoryContents -Source (Join-Path $TemplateRoot "Playwright\.pod-settings.json") -Destination (Join-Path $playwrightRoot ".pod-settings.json")
    }
}

Write-HostLine "Done."
