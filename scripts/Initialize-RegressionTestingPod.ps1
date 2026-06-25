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

$StandardFolders = @(
    "documentation",
    "reference",
    "scripts",
    "Runs",
    "Playwright"
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

    $root = Join-Path $RegressionRoot $safeFolder
    Write-HostLine "Provisioning $root"
    Ensure-Directory -Path $root

    foreach ($sub in $StandardFolders) {
        Ensure-Directory -Path (Join-Path $root $sub)
    }

    if ($CopyTemplates -and -not [string]::IsNullOrWhiteSpace($TemplateRoot)) {
        foreach ($sub in $StandardFolders) {
            $source = Join-Path $TemplateRoot $sub
            $dest = Join-Path $root $sub
            Copy-DirectoryContents -Source $source -Destination $dest
        }
    }
}

Write-HostLine "Done."
