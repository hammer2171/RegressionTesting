# Playwright Screenshots And Evidence Doc

## How screenshot capture works

- In `playwright.config.js`, `screenshot: 'only-on-failure'` captures screenshots only when a test fails.
- For evidence runs, use `--screenshot on` so each test produces screenshots even on pass.

## Run an evidence test

```powershell
npm run test:epm22:import-all-maps-cleaned:e2e:evidence:full
```

Or use the npm shortcut:

```powershell
npm run test:e2e:evidence -- tests/oracle-epm-0057_import_all_maps.cleaned.spec.ts
```

## Build a Markdown evidence report

```powershell
npm run evidence:build
```

This generates:

- `output/playwright-evidence.md`

The report includes discovered screenshots from `test-results` and embeds each image so the file can be reviewed as one test evidence doc.

## Extract images from a trace zip

If you want image artifacts directly out of `trace.zip`, run:

```powershell
npm run evidence:extract-trace -- -TraceZip "C:\epm22_test\Mappings\ExportMapping\test-results\<run-folder>\trace.zip" -OutputDir ".\output\trace-images"
```

This writes detected image payloads to `output/trace-images`.

Notes:
- Trace extraction may include many technical snapshots, not only user-facing key frames.
- For cleaner evidence, prefer explicit screenshot capture in the test run plus `npm run evidence:build`.

## Build a PDF document (one image per page)

```powershell
npm run evidence:build-trace-pdf -- --imagesDir ".\output\trace-images" --outputPath ".\output\trace-images.pdf"
```

This creates a PDF where each extracted image is placed on its own page (sheet).

## Build curated UI validation evidence PDF (recommended)

If you want only key scenes (for example: `Successfully`, `Completed`, `Saved`, `Signed Out`) in a final evidence deck:

1. Watch the run video (`.webm`) and capture only the scenes you want.
2. Save those images into `output/ui-validations/`.
3. Build PDF:

```powershell
npm run evidence:build-ui-validations-pdf
```

This creates:

- `output/test_ui_validations.pdf`

### Optional: exact order + custom captions via manifest

Create `output/ui-validations/selection.txt` with one image per line:

```text
# path|caption
output/ui-validations/01-login-success.png|Login Successful
output/ui-validations/02-map-import-completed.png|Map Import Completed
output/ui-validations/03-save-confirmation.png|Save Confirmation
output/ui-validations/04-signout-complete.png|Signed Out
```

Then build:

```powershell
npm run evidence:build-ui-validations-pdf:manifest
```
