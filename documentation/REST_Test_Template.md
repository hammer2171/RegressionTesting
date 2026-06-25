# REST API Test Template

## Test Identity

* Test name:
* Test ID:
* Folder:
* Module:
* Pod:
* Pod URL:
* Run type: `Normal` or `SCU`
* Run label:
* Owner:

## Goal

Describe what the REST run must accomplish.

## What I Need To Run This

Fill in everything required to execute the REST batch without guessing.

* Auth method:
* CMS secret path:
* Certificate thumbprint or subject:
* Project root folder:
* Base URL:
* JSON input file:
* Audit endpoint:
* Notification source:
* Notification success pattern:
* Notification failure pattern:
* Run label source:
* SCU zip file name:
* Download location for audit records:
* Any follow-up validation endpoint:
* Retry count:
* Poll seconds:
* Throttle milliseconds:

## Run Folder Rules

* Normal runs:
  * `Runs\<Run_Label>_yyyyMMdd_HHmmss`
* SCU runs:
  * `scu\Runs\<Run_Label>_yyyyMMdd_HHmmss`
* Project root:
  * `C:\RegressionTesting\<Folder>`
* `Run_Label` comes from:
  * normal runs: the test label
  * SCU runs: the zip file name

## Preconditions

* The pod is reachable.
* The auth material exists.
* The JSON input file is valid.
* Any required test data already exists.
* The notification area or API is available for SCU verification.
* The audit download endpoint is known for this pod.

## JSON Input

Describe the JSON structure that will drive the batch.

* File name:
* Top-level fields:
* Operation list field:
* Optional filters:
* Paging or chunk size:
* Pod-specific fields:
  * audit endpoint
  * notification source
  * notification pass/fail patterns
  * retry/poll/throttle values

## Operations

List the operations the script must execute.

1. Operation name:
   * Endpoint:
   * Method:
   * Request body:
   * Expected result:

2. Operation name:
   * Endpoint:
   * Method:
   * Request body:
   * Expected result:

## Notification Rules

For SCU runs:

* Check the notification message after the workload completes.
* Pass only if the message clearly indicates success.
* Fail if the message indicates a failure, timeout, or validation issue.
* Save the notification text into the run folder.
* Use pod-specific pass/fail text patterns if they differ.

## Audit Rules

For SCU runs:

* Download audit records from the pod.
* Verify the audit records match the executed operations.
* Ignore `OpenForm` tests when reviewing audit records.
* Save the audit output into the run folder.
* Use the pod-specific audit download endpoint if required.

## Evidence Required

* Run log: `Yes` / `No`
* Request and response capture: `Yes` / `No`
* Summary file: `Yes` / `No`
* Downloaded audit records: `Yes` / `No`
* Notification capture: `Yes` / `No`
* Screenshot or UI evidence: `Yes` / `No`

## Selector Or UI Guidance

Only fill this in when the REST test includes UI verification.

* Playwright storage state needed:
* UI page or notification area:
* Known selectors or labels:

## Expected Results

Describe exactly how success is proven.

* HTTP status:
* Expected response shape:
* Expected notification text:
* Expected audit result:
* Any files created or downloaded:

## Do Not

* Do not expose secrets.
* Do not guess through ambiguous notifications.
* Do not include `OpenForm` in audit verification.
* Do not continue after a failed hard-blocking operation unless the run explicitly allows it.

## Notes For Codex

* Include retries if the endpoint is async.
* Include pagination if the list is large.
* Include chunking or throttling if SCU needs it.
* Include pod-specific notification and audit parameters where they vary.
* Include response assertions that prove the operation did what it should.
