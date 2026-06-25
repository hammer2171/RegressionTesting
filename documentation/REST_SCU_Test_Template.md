# SCU REST API Test Template

## Test Identity

* Test name:
* Test ID:
* Folder:
* Pod:
* Pod URL:
* Run label:
* SCU zip file name:
* Package kind:
* Test mode:
* Iterations:
* Lag time:
* Notification emails:
* Work dir:
* Runs root:
* Owner:

## Goal

Describe the simulated concurrent usage workload and the backend operations it should exercise.

## What I Need To Run This

* Auth method:
* CMS secret path:
* Certificate thumbprint or subject:
* Project root folder:
* JSON workload file:
* Base URL:
* Notification source:
* Notification success pattern:
* Notification failure pattern:
* Audit download endpoint:
* Any follow-up validation endpoint:
* Any chunk size or throttle requirement:
* Retry count:
* Poll seconds:
* Timeout seconds:
* Any pod-specific report filename rule:
* Any pod-specific notification escape text:

## Run Folder Rules

* SCU run folder:
  * `scu\Runs\<Run_label>_yyyyMMdd_HHmmss`
* Project root:
  * `C:\RegressionTesting\<Folder>`
* Legacy source root:
  * `C:\simulateConcurrentUsage\<pod-number>\_epmXX-test`
* `Run_label` comes from the zip file name.

## Folder Model

Use the same workflow shape across pods:

* `documentation`
* `scripts`
* `scu\Runs`
* `info`
* `ChatMemory`
* `Skill`

Keep generated evidence inside the run folder, not beside the scripts.

## Workload Definition

Describe the JSON payload that drives the SCU run.

* Top-level fields:
* Operation array field:
* Concurrency or loop count:
* Retry policy:
* Polling policy:
* Throttle policy:
* Any per-operation overrides:
* Any package family override:
* Any pod-specific audit exclusion list:

## SCU JSON Contract

Recommended top-level JSON fields:

* `runLabel`
* `zipFileName`
* `baseUrl`
* `folder`
* `packageKind`
* `testName`
* `testMode`
* `iterations`
* `lagTime`
* `notificationEmails`
* `workDir`
* `runsRoot`
* `notification`
  * `source`
  * `successPattern`
  * `failurePattern`
  * `pollSeconds`
  * `timeoutSeconds`
* `audit`
  * `endpoint`
  * `ignoreOperations`
  * `ignoreOpenForm`
* `retry`
  * `count`
  * `delaySeconds`
  * `throttleMilliseconds`
* `operations`
  * `name`
  * `method`
  * `endpoint`
  * `requestBody`
  * `expectedStatus`
  * `nonBlocking`

## Operations

List each backend operation that the SCU workload will execute.

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

## Notification Verification

* Check the completion notification after the workload ends.
* Pass if the message clearly indicates success.
* Fail if the message indicates failure, timeout, or invalid workload completion.
* Save the notification text into the run folder.
* If a pod varies, use pod-specific pass/fail patterns.
* Keep any exception text or workaround notes in the run log, not in the template.

## Audit Verification

* Download the audit records from the pod.
* Verify the records match the executed operations.
* Ignore `OpenForm` entries during audit verification.
* Save the audit output into the run folder.
* Do not treat report success as audit proof.
* Do not infer row-add support for Flex SaveFormSV unless the audit proves it.

## Evidence Required

* Run log
* Summary file
* Downloaded audit records
* Notification capture
* Request and response capture
* Report CSV when Oracle returns one
* Any package-specific `.msg` evidence when used

## Do Not

* Do not include `OpenForm` in audit verification.
* Do not guess through a failed notification.
* Do not expose secrets.
* Do not continue after a failed blocking operation unless the workload explicitly allows retries.

## Notes For Codex

* Include workload zip name in the run label.
* Include any pod-specific audit download route.
* Include any SCU throttling or chunking rules.
* Include any expected pass/fail phrases from the notification text.
* Preserve `testMode=3` and `testName` coupling.
* Preserve `simulateConcurrentUsage` ZIP-name invocation rules.
* Preserve the save proof distinction: SimCon success is not the same as Audit save.
