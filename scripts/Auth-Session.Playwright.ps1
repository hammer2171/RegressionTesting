#Requires -Version 5.1
param(
  [ValidateSet("refresh", "reuse")]
  [string]$Mode = "refresh",
  [string]$Folder = "epm18-test",
  [string]$RegressionRoot = "C:\RegressionTesting",
  [string]$ProjectRoot,
  [string]$UserKey,
  [string]$PodKey,
  [string]$BaseUrl,
  [string]$Channel = "msedge"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-EnvValueFromFile {
  param(
    [string]$Path,
    [string]$Name
  )
  if (-not (Test-Path -LiteralPath $Path)) { return $null }

  $pattern = "^\s*$([Regex]::Escape($Name))\s*=\s*(.*)\s*$"
  foreach ($line in Get-Content -LiteralPath $Path) {
    if ($line -match $pattern) {
      $value = $matches[1].Trim()
      if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
        $value = $value.Substring(1, $value.Length - 2)
      }
      return $value
    }
  }
  return $null
}

function Normalize-Key {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
  return ($Value.Trim().ToLowerInvariant() -replace '[^a-z0-9_]+', '_').Trim('_')
}

function Get-PodSettings {
  param([Parameter(Mandatory)][string]$Root)
  $path = Join-Path $Root ".pod-settings.json"
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  try {
    $raw = Get-Content -Raw -LiteralPath $path
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
  }
  catch {
    return $null
  }
}

function Set-Or-AppendEnvValue {
  param(
    [string]$Path,
    [string]$Name,
    [string]$Value
  )

  if ([string]::IsNullOrWhiteSpace($Path)) { return }
  if (-not (Test-Path -LiteralPath $Path)) {
    Set-Content -LiteralPath $Path -Value "$Name=$Value"
    return
  }

  $lines = @(Get-Content -LiteralPath $Path)
  $pattern = "^\s*$([Regex]::Escape($Name))\s*="
  $updated = $false
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match $pattern) {
      $lines[$i] = "$Name=$Value"
      $updated = $true
      break
    }
  }
  if (-not $updated) { $lines += "$Name=$Value" }
  Set-Content -LiteralPath $Path -Value $lines
}

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
  $ProjectRoot = Join-Path (Join-Path $RegressionRoot $Folder) "Playwright"
}

$podSettings = Get-PodSettings -Root $ProjectRoot

if ([string]::IsNullOrWhiteSpace($UserKey)) {
  $UserKey = Read-Host "Enter user key (blank/user for you; collaborator first name lower-case)"
}

$UserKey = Normalize-Key -Value $UserKey
if ([string]::IsNullOrWhiteSpace($UserKey) -or $UserKey -eq "user") { $UserKey = "user" }

if ([string]::IsNullOrWhiteSpace($PodKey)) {
  if ($podSettings -and $podSettings.podKey) { $PodKey = [string]$podSettings.podKey }
  else { $PodKey = Read-Host "Enter pod key (optional, e.g. 11_test_fccs). Leave blank for default" }
}
$PodKey = Normalize-Key -Value $PodKey

$fileStem = if ([string]::IsNullOrWhiteSpace($PodKey)) { $UserKey } else { "$UserKey.$PodKey" }
$storageStatePath = Join-Path $ProjectRoot "playwright\.auth\$fileStem.json"

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
  if ($podSettings -and $podSettings.podUrl) { $BaseUrl = [string]$podSettings.podUrl }
}

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
  $envFile = if ($env:ENV_FILE) { $env:ENV_FILE } else { Join-Path $ProjectRoot ".env" }
  $baseFromFile = Get-EnvValueFromFile -Path $envFile -Name "EPM_BASE_URL"
  $BaseUrl = if ($env:EPM_BASE_URL) { $env:EPM_BASE_URL } elseif ($baseFromFile) { $baseFromFile } else { "" }
}

if ([string]::IsNullOrWhiteSpace($BaseUrl)) { $BaseUrl = Read-Host "Enter pod URL (https://...)" }
if ($BaseUrl -notmatch '^https?://') { throw "BaseUrl must start with http:// or https://" }

New-Item -ItemType Directory -Path (Join-Path $ProjectRoot "playwright\.auth") -Force | Out-Null

$envFile = if ($env:ENV_FILE) { $env:ENV_FILE } elseif (-not [string]::IsNullOrWhiteSpace($PodKey)) { Join-Path $ProjectRoot ".env.$PodKey" } else { Join-Path $ProjectRoot ".env" }
Set-Or-AppendEnvValue -Path $envFile -Name "PW_STORAGE_STATE" -Value "playwright/.auth/$fileStem.json"
Set-Or-AppendEnvValue -Path $envFile -Name "PW_AUTH_USER_KEY" -Value $UserKey
Set-Or-AppendEnvValue -Path $envFile -Name "FOLDER" -Value $Folder
Set-Or-AppendEnvValue -Path $envFile -Name "REGRESSION_ROOT" -Value $RegressionRoot

$args = @("playwright", "codegen", "--channel=$Channel")
if (Test-Path -LiteralPath $storageStatePath) { $args += "--load-storage=$storageStatePath" }
if ($Mode -eq "refresh") { $args += "--save-storage=$storageStatePath" }
$args += $BaseUrl

Write-Host "Using storage state: $storageStatePath"
Write-Host "Using URL: $BaseUrl"
Write-Host "Command: npx $($args -join ' ')"

& npx @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Done. Storage state file: $storageStatePath"
Write-Host "Tip: set PW_STORAGE_STATE=$storageStatePath for this user/pod when running tests."
