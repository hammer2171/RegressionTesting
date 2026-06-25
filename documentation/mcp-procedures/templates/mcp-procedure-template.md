# MCP Procedure: <procedure name>

Procedure ID: `<lowercase-id>`
Application: Oracle EDM <Folder>
URL: `https://<Folder>-a706571.epm.us2.oraclecloud.com/epmcloud`
Mode: Playwright MCP headed
Auth: Use existing Playwright storage state. If prompted, login interactively and record that auth refresh was required.

## Goal

Describe the business outcome MCP should complete.

## Test Data

- View:
- Viewpoint:
- Request title:
- Node or hierarchy:
- Other values:

## Preconditions

- Storage state exists or user is available to complete login.
- Required view/viewpoint/data exists.
- Browser should start from the <Folder> URL above.

## Evidence Checkpoints

- After successful login or landing page load.
- After navigating to the target work area.
- Before submitting or saving changes.
- After final success message or expected result.

## Steps

1. Open the <Folder> URL.
   - Expected: EDM home or landing page is visible.
   - Evidence: screenshot named `01-home.png`.

2. Navigate to `<area>`.
   - Expected: `<area>` page is visible.
   - Evidence: screenshot named `02-area.png`.

3. Perform `<business action>`.
   - Expected: `<expected result>`.
   - Evidence: screenshot named `03-action.png`.

4. Validate the final result.
   - Expected: `<final validation>`.
   - Evidence: screenshot named `04-final.png`.

## MCP Notes

- Take a fresh snapshot before interacting with navigation, menus, forms, or dialogs.
- Prefer visible text, accessible labels, and roles over brittle CSS selectors.
- If an element cannot be found, capture a screenshot and page snapshot, then stop as Blocked.
- Record every clicked label and typed value in the run log.

## Do Not

- Do not expose passwords, cookies, storage-state content, or auth headers.
- Do not continue after a failed save/submit unless explicitly instructed.

