# MCP Evidence Protocol

Follow this protocol whenever executing an MCP procedure markdown file for <Folder>.

## Run Folder

Create a timestamped folder under:

```text
C:\RegressionTesting\<Folder>\Runs
```

Use this naming pattern:

```text
yyyyMMdd_HHmmss_<procedure-id>
```

## Required Evidence

For every procedure run, capture:

- `procedure.md`: copy of the exact MCP markdown used for the run.
- `run.log`: timestamped execution log.
- `steps.md`: step-by-step evidence summary with pass/fail status.
- `screenshots`: folder containing checkpoint screenshots.
- `playwright-trace`: trace output when available.
- `errors`: folder for failure screenshots, page snapshots, or response bodies.

## Execution Rules

1. Open the configured URL in headed mode.
2. Use existing Playwright storage state when available.
3. If login is required, perform it interactively and save storage state only when the procedure permits it.
4. Take a Playwright MCP snapshot before clicking or typing into page elements.
5. Re-snapshot after navigation, opening menus, dialogs, drawers, or page regions that materially change.
6. Prefer accessible roles and labels. If a selector is ambiguous, record the ambiguity in `run.log`.
7. Capture a screenshot after each checkpoint listed in the procedure.
8. Record actual observed results, not only intended actions.
9. If a step fails, stop unless the procedure explicitly says to continue, then capture failure evidence.
10. Do not log passwords, auth headers, cookies, or storage-state JSON content.

## Step Log Format

Use this shape in `steps.md`:

```md
## Step 01 - <short name>

Status: Pass | Fail | Blocked

Action:
<what MCP did>

Observed:
<what was visible or returned>

Evidence:
<screenshot or trace file names>
```

