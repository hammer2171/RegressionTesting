# MCP Test Template

## Test Identity

* Test name:
* Test ID:
* Folder:
* Module:
* Pod:
* Pod URL:
* Procedure type: `UI`, `Hybrid`, or `REST-assisted`
* Owner:

## Goal

Describe the business outcome in one or two sentences.

## What I Need To Run This

Fill in everything required for MCP to execute without guessing.

* Auth method:
* Storage state available: `Yes` / `No`
* Project root folder:
* Login required: `Yes` / `No`
* Test data ready: `Yes` / `No`
* Required access or role:
* Known view / viewpoint / request / policy / location:
* Required environment variables or `.env` file:
* REST endpoint needed, if any:
* File uploads, downloads, or attachments needed:
* Any data that must already exist:

## Preconditions

List the state that must already be true before execution starts.

* Example:
  * User can open the pod URL
  * User has access to the target view
  * Required test data exists

## Test Data

Provide the exact values MCP should use.

* View:
* Viewpoint:
* Request name:
* Policy name:
* Node or member:
* Other values:

## Steps

Write the business steps in plain language.

1. Open the pod URL.
2. Login if required.
3. Navigate to the target area.
4. Perform the action.
5. Validate the result.

## Expected Results

Describe what success looks like.

* Page or dialog that should be visible
* Messages that should appear
* Data that should be created, updated, enabled, disabled, or submitted

## Evidence Required

Select what must be captured.

* Screenshots: `Yes` / `No`
* Trace: `Yes` / `No`
* Video: `Yes` / `No`
* Run log: `Yes` / `No`
* Final summary: `Yes` / `No`

## Evidence Checkpoints

List the moments when MCP must capture evidence.

* After login
* After navigation
* Before save or submit
* After final success message
* After any failure

## Selector Guidance

Tell MCP how much freedom it has.

* Selector policy: `Use accessible roles first; improvise if needed`
* Navigation policy: `Improvise navigation if the UI changes`
* Stop if ambiguous: `Yes` / `No`

## REST Guidance

Use this section when the test requires REST calls or a hybrid UI/API flow.

* REST endpoint(s):
* HTTP method(s):
* Authentication source:
* Request body requirements:
* Expected response:

## Do Not

List anything MCP must avoid.

* Do not submit unless explicitly instructed
* Do not delete production data
* Do not expose secrets
* Do not guess through ambiguous controls

## Notes For Codex

Add anything that would help generate the executable Playwright test.

* Known flaky areas:
* Alternate selectors:
* Special timing concerns:
* Validation rules:
