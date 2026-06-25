# 28_test_FINPLAN Quickstart

## Transition Rule
This run can be started from ExportMapping (one-time transition).
After this setup, run pod orchestration from C:\Playwright_development only.

## Pod orchestration location (ongoing)
Use tools from: C:\Playwright_development\tools
Create new pods:
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Playwright_development\tools\New-PlaywrightPodWorkspace.ps1
Sync scripts between pods:
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Playwright_development\tools\Sync-PodScripts.ps1

## Where to run
Run all pod commands from: C:\Playwright_development\28_test_FINPLAN

## 1) Saved storage state first
Always use the saved Playwright storage state when possible. For this pod the expected user state is:

```powershell
C:\Playwright_development\28_test_FINPLAN\playwright\.auth\user.28_test_finplan.json
```

Use a refresh only when the saved state is missing, expired, or the test lands on the login screen.

## 2) Reauth (pod-specific storage state, URL auto-loaded from .pod-settings.json)
npm run auth:refresh -- -UserKey user
npm run auth:refresh -- -UserKey aigul

## 3) FINPLAN MCP traversal smoke
Run traversal from the server-local `C:` path, not the mapped `M:` drive:

```powershell
cd C:\Playwright_development\28_test_FINPLAN
$env:ENV_FILE=".env.28_test_finplan"
$env:START_URL="https://epm28-test-a706571.epm.us-phoenix-1.ocs.oraclecloud.com/epmcloud"
$env:EPM_BASE_URL=$env:START_URL
$env:PW_HEADLESS="1"
$env:PW_AUTO_AUTH="false"
$env:PW_SKIP_AUTH_CHECK="1"
$env:MCP_EXPLORE_ACTIONS="0"
$env:NODE_OPTIONS="--max-old-space-size=4096"
npx playwright test tests/tiles/MCP/epm11testFullSiteTraversal.mcp.spec.ts --grep "tile 1-1 Tasks" --project=edge --workers=1 --reporter=list --timeout=300000
```

## 4) Full traversal evidence
Use the evidence wrapper when collecting a durable run:

```powershell
cd C:\Playwright_development\28_test_FINPLAN
$env:ENV_FILE=".env.28_test_finplan"
$env:EVIDENCE_LABEL="finplan_mcp_full_traversal"
$env:NODE_OPTIONS="--max-old-space-size=4096"
node .\scripts\run-evidence-and-archive.mjs tests/tiles/MCP/epm11testFullSiteTraversal.mcp.spec.ts
```

## 5) Run full evidence E2E for any test file
npm run test:e2e:evidence:full -- tests/<your-test>.spec.ts

## 6) Build curated UI validation PDF by manifest
node .\scripts\Build-UiValidationsPdf.mjs --manifest .\output\ui-validations\<test_name>\selection.txt --outputPath .\output\ui-validations\<test_name>\ui_vals_<test_name>_YYYYMMDD_HHMMSS.pdf --title "<Test Name> - UI Validations"
