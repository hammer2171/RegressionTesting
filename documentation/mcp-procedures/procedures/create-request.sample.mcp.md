# MCP Procedure: Create EDM Request

Procedure ID: `create-edm-request-sample`
Application: Oracle EDM <Folder>
URL: `https://<Folder>-a706571.epm.us2.oraclecloud.com/epmcloud`
Mode: Playwright MCP headed
Auth: Use existing Playwright storage state. If prompted, login interactively and record that auth refresh was required.

## Goal

Navigate to the target EDM view and create a request using the test data below. Capture full evidence of navigation, request creation, validation, and final outcome.

## Test Data

- View: `<enter view name>`
- Viewpoint: `<enter viewpoint name>`
- Request title: `MCP Regression Request <timestamp>`
- Node or hierarchy: `<enter node/hierarchy>`
- Requested action: `<add/update/delete/submit/other>`

## Preconditions

- The user running MCP has permission to create requests in the selected view.
- Playwright storage state exists for <Folder>, or the user is available to complete login.
- Test data values above have been filled in before execution.

## Evidence Checkpoints

- After EDM home page loads.
- After the target view is open.
- After the target viewpoint or request area is open.
- After request details are entered.
- After save/submit or final expected result.

## Steps

1. Open the URL - https://epm18-test-a706571.epm.us2.oraclecloud.com/epm
   - Expected: EDM home or landing page is visible.
   - Evidence: screenshot named `01-home.png`.

2. Navigate to `Views` and click the Views link.
   - Expected: `Views` page is visible.
   - Evidence: screenshot named `02-area.png`.

3. Click on the View `A_Entry_Entity`.
   - Expected: `A_Entry_Entity` page is visible.
   - Evidence: screenshot named `03-action.png`.

4. Click on the Viewpoint `A_Entry_Entity`.
   - Expected: `Input_EPM_Entity_Base` tab is visible.
   - Evidence: screenshot named `03-action.png`.


5. Start a new request.
   - Expected: New request panel, dialog, or request context is visible.
   - Evidence: screenshot named `05-new-request.png`.

6. Enter request title `MCP Regression Request <timestamp>`.
   - Expected: Request title is accepted.
   - Evidence: screenshot named `06-request-title.png`.

7. Perform the requested action: `<add/update/delete/submit/other>`.
   - Expected: The page shows the requested change staged in the request.
   - Evidence: screenshot named `07-request-action.png`.

8. Validate the staged change before submit/save.
   - Expected: Validation completes successfully or expected warning is displayed.
   - Evidence: screenshot named `08-validation.png`.

9. Save or submit the request as instructed by the test owner.
   - Expected: Confirmation, request number, or success message is visible.
   - Evidence: screenshot named `09-final.png`.

## MCP Notes

- Take a fresh snapshot before each click/type action.
- Use visible labels and roles first.
- If multiple matching views/viewpoints appear, stop and report ambiguity.
- Record the final request number or visible confirmation text in `steps.md`.

## Do Not

- Do not submit the request unless this procedure explicitly says submit.
- Do not delete or alter production-like data unless the test data explicitly allows it.
- Do not log credentials or storage-state details.

