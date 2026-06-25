param(
  [string]$PodFolderName,
  [string]$PodUrl,
  [string]$RootPath = "C:\Playwright_development",
  [string]$SourceRepo = "",
  [string]$TemplatePodFolder = "",
  [string]$TemplatePath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Require-Value {
  param(
    [string]$CurrentValue,
    [string]$Prompt
  )
  if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
    return $CurrentValue
  }
  return (Read-Host $Prompt)
}

function Validate-PodFolderName {
  param([string]$Name)
  if ($Name -notmatch '^\d+_(test|prod)_[A-Za-z0-9_]+$') {
    throw "Pod folder name must match: <podNumber>_<test|prod>_<appName>. Example: 11_test_Fccs"
  }
}

function Ensure-GlobalSetupAuthLaunchFallback {
  param([string]$FilePath)

  if (-not (Test-Path -LiteralPath $FilePath)) {
    return
  }

  $content = Get-Content -LiteralPath $FilePath -Raw
  $updated = $content

  if ($updated -notmatch 'const AUTH_HEADLESS = parseBooleanEnv\(') {
    $updated = $updated -replace "const AUTH_POLL_INTERVAL_MS = 1000;","const AUTH_POLL_INTERVAL_MS = 1000;`r`nconst AUTH_HEADLESS = parseBooleanEnv('PW_AUTH_HEADLESS', true);"
  }

  if ($updated -match "const browser = await chromium\.launch\(\{\s*channel: process\.env\.PW_CHANNEL \|\| 'msedge',\s*headless: true,\s*\}\);") {
    $updated = $updated -replace "const browser = await chromium\.launch\(\{\s*channel: process\.env\.PW_CHANNEL \|\| 'msedge',\s*headless: true,\s*\}\);","const browser = await launchAuthBrowser();"
  }

  if ($updated -notmatch "function parseBooleanEnv\(") {
    $helperBlock = @'
function parseBooleanEnv(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === null || raw === '') {
    return fallback;
  }

  const normalized = String(raw).trim().toLowerCase();
  if (['1', 'true', 'yes', 'on'].includes(normalized)) return true;
  if (['0', 'false', 'no', 'off'].includes(normalized)) return false;
  return fallback;
}

async function launchAuthBrowser() {
  const preferredChannel = (process.env.PW_CHANNEL || 'msedge').trim();
  const launchOptions = { headless: AUTH_HEADLESS };

  if (preferredChannel) {
    try {
      return await chromium.launch({
        ...launchOptions,
        channel: preferredChannel,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.warn(
        `[global-setup-auth] Failed to launch channel "${preferredChannel}" (${message}). Falling back to bundled Chromium.`
      );
    }
  }

  return chromium.launch(launchOptions);
}

'@
    $updated = $updated -replace "function parseMsEnv\(name, fallback\) \{",($helperBlock + "function parseMsEnv(name, fallback) {")
  }

  if ($updated -ne $content) {
    Set-Content -LiteralPath $FilePath -Value $updated
    Write-Host "Patched global setup launch fallback: $FilePath"
  }
}

function Copy-TemplateFileIfExists {
  param(
    [string]$TemplateRoot,
    [string]$RelativePath,
    [string]$TargetRoot,
    [string]$DestinationRelativePath = $RelativePath
  )

  $src = Join-Path $TemplateRoot $RelativePath
  if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
    return
  }

  $dest = Join-Path $TargetRoot $DestinationRelativePath
  $destDir = Split-Path -Parent $dest
  if (-not [string]::IsNullOrWhiteSpace($destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
  }
  Copy-Item -LiteralPath $src -Destination $dest -Force
}

function Copy-TemplateDirectoryIfExists {
  param(
    [string]$TemplateRoot,
    [string]$RelativePath,
    [string]$TargetRoot,
    [string]$DestinationRelativePath = $RelativePath
  )

  $src = Join-Path $TemplateRoot $RelativePath
  if (-not (Test-Path -LiteralPath $src -PathType Container)) {
    return
  }

  $dest = Join-Path $TargetRoot $DestinationRelativePath
  New-Item -ItemType Directory -Path $dest -Force | Out-Null
  Copy-Item -Path (Join-Path $src "*") -Destination $dest -Recurse -Force
}

function Remove-BootstrapExcludedContent {
  param([string]$TargetRoot)

  $excluded = @(
    "pages\pages",
    "pages\Bogus_old",
    "tests\tests",
    "tests\codegen",
    "Runs",
    "output",
    "test-results",
    "playwright-report",
    "blob-report",
    ".playwright-mcp",
    ".vscode",
    "Backups",
    "Scrape_tests",
    "_FCCS_Files_Misc",
    "node_modules",
    "components\MCP\ConsJournals"
  )

  foreach ($rel in $excluded) {
    $p = Join-Path $TargetRoot $rel
    if (Test-Path -LiteralPath $p) {
      Remove-Item -LiteralPath $p -Recurse -Force
    }
  }

  Get-ChildItem -LiteralPath $TargetRoot -File -Filter ".env.*" -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

  $authDir = Join-Path $TargetRoot "playwright\.auth"
  if (Test-Path -LiteralPath $authDir) {
    Get-ChildItem -LiteralPath $authDir -File -Filter "*.json" -ErrorAction SilentlyContinue |
      Remove-Item -Force -ErrorAction SilentlyContinue
  }
}

function Copy-CleanPodTemplate {
  param(
    [string]$TemplateRoot,
    [string]$TargetRoot
  )

  foreach ($relative in @(
    "package.json",
    "package-lock.json",
    "playwright.config.js",
    "playwright.evidence.config.js",
    "tsconfig.json",
    "AGENTS.md",
    "tests\global-setup-auth.js",
    "tests\global-teardown-auth.js"
  )) {
    Copy-TemplateFileIfExists -TemplateRoot $TemplateRoot -RelativePath $relative -TargetRoot $TargetRoot
  }

  foreach ($relative in @("tests\fixtures", "tests\helpers")) {
    Copy-TemplateDirectoryIfExists -TemplateRoot $TemplateRoot -RelativePath $relative -TargetRoot $TargetRoot
  }

  foreach ($relative in @(
    "pages\MCP\HomeShellPage.ts",
    "pages\MCP\Epm11testMainHomePage.ts",
    "pages\MCP\SignInPage.ts",
    "pages\MCP\JetFrame.ts",
    "tests\tiles\MCP\epm11testHomeNavigationAriaSnapshots.spec.ts"
  )) {
    Copy-TemplateFileIfExists -TemplateRoot $TemplateRoot -RelativePath $relative -TargetRoot $TargetRoot
  }

  foreach ($relative in @(
    "scripts\Auth-Session.ps1",
    "scripts\archive-playwright-artifacts.mjs",
    "scripts\build-run-ui-validations-from-master.mjs",
    "scripts\Build-TraceImagePdf.mjs",
    "scripts\Build-UiValidationsPdf.mjs",
    "scripts\Extract-PlaywrightTraceImages.ps1",
    "scripts\Render-PlaywrightCliYaml.mjs",
    "scripts\run-evidence-and-archive.mjs",
    "scripts\Sync-PodScripts.ps1",
    "scripts\New-PlaywrightPodWorkspace.ps1"
  )) {
    Copy-TemplateFileIfExists -TemplateRoot $TemplateRoot -RelativePath $relative -TargetRoot $TargetRoot
  }

  Remove-BootstrapExcludedContent -TargetRoot $TargetRoot

  foreach ($folder in @(
    "components",
    "docs",
    "pages",
    "pages\MCP",
    "tests",
    "tests\tiles",
    "tests\tiles\MCP",
    "playwright\.auth",
    "output\ui-validations",
    "output\playwright",
    "scripts",
    "snippets"
  )) {
    New-Item -ItemType Directory -Path (Join-Path $TargetRoot $folder) -Force | Out-Null
  }
}

if ([string]::IsNullOrWhiteSpace($SourceRepo)) {
  $SourceRepo = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
}

$PodFolderName = Require-Value -CurrentValue $PodFolderName -Prompt "Enter pod folder name (<podNumber>_<test|prod>_<appName>)"
$PodUrl = Require-Value -CurrentValue $PodUrl -Prompt "Enter pod URL (https://...)"

Validate-PodFolderName -Name $PodFolderName

if ($PodUrl -notmatch '^https?://') {
  throw "Pod URL must start with http:// or https://"
}

$targetRoot = Join-Path $RootPath $PodFolderName
$toolsRoot = Join-Path $RootPath "tools"
$folders = @(
  $RootPath,
  $toolsRoot,
  $targetRoot,
  (Join-Path $targetRoot "playwright\.auth"),
  (Join-Path $targetRoot "output\ui-validations"),
  (Join-Path $targetRoot "output\playwright"),
  (Join-Path $targetRoot "components"),
  (Join-Path $targetRoot "pages\MCP"),
  (Join-Path $targetRoot "tests\tiles\MCP"),
  (Join-Path $targetRoot "docs"),
  (Join-Path $targetRoot "scripts"),
  (Join-Path $targetRoot "snippets")
)

foreach ($folder in $folders) {
  New-Item -ItemType Directory -Path $folder -Force | Out-Null
}

$resolvedTemplatePath = ""
if (-not [string]::IsNullOrWhiteSpace($TemplatePath)) {
  $resolvedTemplatePath = $TemplatePath
}
elseif (-not [string]::IsNullOrWhiteSpace($TemplatePodFolder)) {
  $resolvedTemplatePath = Join-Path $RootPath $TemplatePodFolder
}

if (-not [string]::IsNullOrWhiteSpace($resolvedTemplatePath) -and (Test-Path -LiteralPath $resolvedTemplatePath)) {
  Write-Host "Applying clean allowlist template from: $resolvedTemplatePath"
  Copy-CleanPodTemplate -TemplateRoot $resolvedTemplatePath -TargetRoot $targetRoot
}

$rootFilesToCopy = @(
  "playwright.config.js",
  "playwright.evidence.config.js",
  "package.json",
  "package-lock.json",
  "tsconfig.json",
  "docs\Playwright-Screenshots.md",
  "tests\global-setup-auth.js",
  "tests\global-teardown-auth.js",
  "Run-Mapping-Playwright_snippet_of_code2.txt"
)

foreach ($relative in $rootFilesToCopy) {
  $src = Join-Path $SourceRepo $relative
  if (-not (Test-Path -LiteralPath $src)) {
    continue
  }

  $destRel = switch -Regex ($relative) {
    '^docs\\' { Join-Path "docs" ([IO.Path]::GetFileName($relative)); break }
    '^tests\\' { Join-Path "tests" ([IO.Path]::GetFileName($relative)); break }
    '^Run-Mapping-Playwright_snippet_of_code2\.txt$' { Join-Path "snippets" "Run-Mapping-Playwright_snippet_of_code2.txt"; break }
    default { [IO.Path]::GetFileName($relative) }
  }

  $dest = Join-Path $targetRoot $destRel
  $destDir = Split-Path -Parent $dest
  if (-not [string]::IsNullOrWhiteSpace($destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
  }
  Copy-Item -LiteralPath $src -Destination $dest -Force
}

$templateFilesToCopy = @(
  "global-setup-auth.js"
)

foreach ($fileName in $templateFilesToCopy) {
  $src = Join-Path $SourceRepo ("scripts\templates\" + $fileName)
  if (-not (Test-Path -LiteralPath $src)) {
    continue
  }

  $targetTemplateDir = Join-Path $targetRoot "scripts\templates"
  $toolsTemplateDir = Join-Path $toolsRoot "templates"
  New-Item -ItemType Directory -Path $targetTemplateDir -Force | Out-Null
  New-Item -ItemType Directory -Path $toolsTemplateDir -Force | Out-Null

  Copy-Item -LiteralPath $src -Destination (Join-Path $targetTemplateDir $fileName) -Force
  Copy-Item -LiteralPath $src -Destination (Join-Path $toolsTemplateDir $fileName) -Force
}

$scriptFilesToCopy = @(
  "Auth-Session.ps1",
  "archive-playwright-artifacts.mjs",
  "Build-UiValidationsPdf.mjs",
  "Build-SnippetSkillGuideWord.ps1",
  "Build-PlaywrightEvidence.ps1",
  "Build-TraceImageDoc.ps1",
  "Build-TraceImageWordDoc.ps1",
  "Build-TraceImagePdf.mjs",
  "Extract-PlaywrightTraceImages.ps1",
  "Render-PlaywrightCliYaml.mjs",
  "build-run-ui-validations-from-master.mjs",
  "run-evidence-and-archive.mjs",
  "Sync-PodScripts.ps1",
  "New-PlaywrightPodWorkspace.ps1"
)

foreach ($fileName in $scriptFilesToCopy) {
  $src = Join-Path $SourceRepo ("scripts\" + $fileName)
  if (-not (Test-Path -LiteralPath $src)) {
    continue
  }

  Copy-Item -LiteralPath $src -Destination (Join-Path $targetRoot ("scripts\" + $fileName)) -Force
  Copy-Item -LiteralPath $src -Destination (Join-Path $toolsRoot $fileName) -Force

  # Keep key operator scripts directly in pod root for convenience.
  if ($fileName -in @("New-PlaywrightPodWorkspace.ps1", "Auth-Session.ps1", "Sync-PodScripts.ps1")) {
    Copy-Item -LiteralPath $src -Destination (Join-Path $targetRoot $fileName) -Force
  }
}

$targetGlobalSetupPath = Join-Path $targetRoot "tests\global-setup-auth.js"
if (-not (Test-Path -LiteralPath $targetGlobalSetupPath)) {
  $templateCandidates = @(
    (Join-Path $SourceRepo "scripts\templates\global-setup-auth.js"),
    (Join-Path $PSScriptRoot "templates\global-setup-auth.js")
  )

  foreach ($candidate in $templateCandidates) {
    if (Test-Path -LiteralPath $candidate) {
      $targetTestsDir = Split-Path -Parent $targetGlobalSetupPath
      New-Item -ItemType Directory -Path $targetTestsDir -Force | Out-Null
      Copy-Item -LiteralPath $candidate -Destination $targetGlobalSetupPath -Force
      break
    }
  }
}

Ensure-GlobalSetupAuthLaunchFallback -FilePath $targetGlobalSetupPath

$safePodKey = $PodFolderName.ToLowerInvariant()
$envTemplatePath = Join-Path $targetRoot ".env.$safePodKey"
$storageState = "C:/Playwright_development/$PodFolderName/playwright/.auth/user.$safePodKey.json"

$envTemplate = @"
# Pod-specific environment for $PodFolderName
EPM_BASE_URL=$PodUrl
POD_KEY=$safePodKey
PW_STORAGE_STATE=$storageState
PW_AUTH_USER_KEY=user
EPM_SIGN_OUT=true
PW_AUTO_AUTH=true
PW_AUTH_FIELD_TIMEOUT_MS=90000
PW_AUTH_STATE_TIMEOUT_MS=180000
MCP_HOME_READY_LINKS=
MCP_HOME_TILES=

# Fill these locally (do not commit real credentials)
EPM_USERNAME=
EPM_PASSWORD=
"@

Set-Content -LiteralPath $envTemplatePath -Value $envTemplate

$podSettingsPath = Join-Path $targetRoot ".pod-settings.json"
$podSettings = [ordered]@{
  podFolderName = $PodFolderName
  podKey = $safePodKey
  podUrl = $PodUrl
}
$podSettings | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $podSettingsPath

$manifestTemplatePath = Join-Path $targetRoot "output\ui-validations\selection.txt"
$manifestTemplate = @"
# Per-test evidence manifest format:
# path|caption
# output/ui-validations/<test_name>/01-step.png|Description
"@
Set-Content -LiteralPath $manifestTemplatePath -Value $manifestTemplate

$commandsPath = Join-Path $targetRoot "docs\quickstart.md"
$quickStart = @(
  "# $PodFolderName Quickstart",
  "",
  "## Transition Rule",
  "This run can be started from ExportMapping (one-time transition).",
  "After this setup, run pod orchestration from C:\Playwright_development only.",
  "",
  "## Pod orchestration location (ongoing)",
  "Use tools from: C:\Playwright_development\tools",
  "Create new pods:",
  "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Playwright_development\tools\New-PlaywrightPodWorkspace.ps1",
  "Sync scripts between pods:",
  "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Playwright_development\tools\Sync-PodScripts.ps1",
  "",
  "## Where to run",
  "Run all pod commands from: C:\Playwright_development\$PodFolderName",
  "",
  "## 1) Reauth (pod-specific storage state, URL auto-loaded from .pod-settings.json)",
  "npm run auth:refresh -- -UserKey user",
  "npm run auth:refresh -- -UserKey aigul",
  "",
  "## 2) Run full evidence E2E for any test file",
  "npm run test:e2e:evidence:full -- tests/<your-test>.spec.ts",
  "",
  "## 3) Build curated UI validation PDF by manifest",
  "node .\scripts\Build-UiValidationsPdf.mjs --manifest .\output\ui-validations\<test_name>\selection.txt --outputPath .\output\ui-validations\<test_name>\ui_vals_<test_name>_YYYYMMDD_HHMMSS.pdf --title ""<Test Name> - UI Validations"""
)
Set-Content -LiteralPath $commandsPath -Value $quickStart

Write-Host "Created pod workspace: $targetRoot"
Write-Host "Env template: $envTemplatePath"
Write-Host "Pod settings: $podSettingsPath"
Write-Host "Quickstart: $commandsPath"
Write-Host "Shared tools folder: $toolsRoot"
if (-not [string]::IsNullOrWhiteSpace($resolvedTemplatePath)) {
  Write-Host "Template source used: $resolvedTemplatePath"
}
