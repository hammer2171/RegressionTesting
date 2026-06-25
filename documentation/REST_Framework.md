# Oracle Cloud EPM AI Automation Framework

## REST Automation Framework

### Version 1.0

**Owner:** Russell Shellhamer

---

# Purpose

This document defines the native REST API execution pattern for Oracle Cloud EPM pods.

The framework supports parameterized REST calls, batch execution, looping through JSON-driven inputs, timestamped run folders, and special handling for simulate concurrent usage runs.

---

# Scope

This framework applies to:

* Native Oracle Cloud EPM REST API calls
* Batch execution from JSON input
* REST-only automation
* Hybrid REST plus UI verification when needed
* Simulate concurrent usage workflows
* Audit record verification

It does not replace Playwright UI tests. It complements them.

---

# Core Principle

The REST script should be generic enough to handle the common request types:

* GET/list
* POST/create
* PATCH/update
* enable/disable operations
* polling or follow-up validation calls

The JSON input file controls the batch of operations.

---

# Run Folder Strategy

Each pod or test family should live under its own root folder:

```text
C:\RegressionTesting\<Folder>
```

Examples:

* `C:\RegressionTesting\epm-test`
* `C:\RegressionTesting\<Folder>`
* future pods as they are added

Normal REST runs should write to:

```text
<ProjectRoot>\Runs\<Run_Label>_yyyyMMdd_HHmmss
```

Simulate concurrent usage runs should write to:

```text
<ProjectRoot>\scu\Runs\<Run_Label>_yyyyMMdd_HHmmss
```

`Run_Label` should come from the zip file name used for the SCU test.

---

# Input Strategy

JSON is the main input source.

Each JSON file should describe:

* target environment
* base URL
* auth settings
* run label
* operations to execute
* expected responses
* audit verification rules
* notification expectations
* retry and polling rules
* throttling rules

The script should loop through the JSON-defined operations instead of hard-coding each endpoint.

---

# Authentication Strategy

Use the CMS Basic-auth pattern established in the `scripts` folder for REST calls.

Use Playwright storage state only for UI work.

REST scripts should:

* decrypt CMS credentials
* build Basic auth headers
* log the auth source
* avoid writing secrets to logs

---

# SCU Strategy

SCU runs should:

* use the `scu\Runs` folder layout
* read run label from the zip file name
* process the JSON input that describes the concurrent workload
* check the pod notification for pass/fail
* download audit records from the pod
* verify the audit records against the test outcome

OpenForm tests should be excluded from audit record verification.

The following SCU settings should be parameterized per pod or workload:

* notification source
* notification success pattern
* notification failure pattern
* audit download endpoint
* retry count
* polling interval
* throttle milliseconds between calls
* timeout for long-running workloads

---

# Audit Strategy

Audit verification should:

* download audit records after the SCU run
* confirm the run outcome from the notification message
* verify the records align with the executed operations
* ignore `OpenForm` entries when reviewing audit records

The audit download endpoint should be parameterized because the exact pod route may vary.

The notification source should also be parameterized because pods may expose the completion message differently.

---

# Logging Strategy

Each run should include:

* timestamped run folder
* `run.log`
* request and response capture
* per-operation result summary
* audit download output
* notification text

The script should record:

* endpoint
* method
* request label
* response status
* pass/fail outcome
* audit verification status

---

# Evidence Strategy

At minimum, REST runs should capture:

* request payloads
* response payloads
* run log
* summary file
* downloaded audit records when applicable
* notification text when applicable

SCU runs should additionally capture:

* workload identifier
* notification pass/fail result
* audit record download files
* exclusion notes for `OpenForm`

---

# SCU Compatibility With Aigul's Method

The SCU framework must preserve the behavior proved in the original `simulateConcurrentUsage` work:

* `C:\simulateConcurrentUsage` remains the legacy source anchor for epm28 planning work.
* New folder-oriented work should resolve from `C:\RegressionTesting\<Folder>\scu`.
* Keep pod roots separate from package folders and from generated evidence.
* Keep OpenForm and SaveForm package families separate.
* Build OpenForm before SaveForm when a pod is being bootstrapped.
* Use audit proof, not report success alone, to prove SaveForm persistence.

Legacy Planning roots to respect when translating the method:

* `C:\simulateConcurrentUsage\28\_epm28-test`
* `C:\simulateConcurrentUsage\29\_epm29-test`
* `C:\simulateConcurrentUsage\30\_epm30-test`

Current folder-aware roots should follow the same shape under RegressionTesting:

* `C:\RegressionTesting\epm-test\scu`
* `C:\RegressionTesting\epm18-test\scu`
* `C:\RegressionTesting\epm2-test\scu`

The SCU runner should keep Aigul's evidence layout:

* `Runs\Run_<RunTag>`
* `logs`
* `json`
* `reports`
* `email`

SCU package execution rules that must survive the migration:

* Use the ZIP file name as the simulation input file name.
* Do not pass `inbox\<zip>` to `simulateConcurrentUsage`.
* Keep `testMode=3` tied to a required `testName`.
* Preserve `testMode=4` user-driven flows when they are part of the package design.
* Download `report_*.csv` only when Oracle returns a report filename in the failure details.
* Save the notification text and any downloaded report into the run folder.
* Ignore `OpenForm` entries when auditing SCU outcomes.

Aigul's original method also established these durable checks:

* `SimCon passed` does not prove save persistence.
* Audit proving the unique submitted value is the real save proof.
* UTF-8 without BOM matters for `requirement.csv`.
* Flex SaveFormSV row-add behavior must not be assumed unless it is audit-proven.
* A failed notification can still coexist with saved data when the attached rule or prompt fails after save.

---

# Output Strategy

Recommended run contents:

```text
run.log
summary.json
summary.csv
requests
responses
downloads
audit
notification.txt
```

---

# Supported Operation Types

The generic REST engine should support:

* list operations
* create operations
* update operations
* enable/disable operations
* delete operations when explicitly requested
* follow-up validation calls
* retry or polling loops

---

# Failure Strategy

If a REST call fails:

* log the HTTP status code
* log the error body when available
* mark the operation failed
* continue only if the JSON input marks the operation as non-blocking

If the notification or audit verification fails in SCU mode:

* mark the run failed
* save the notification text
* save the audit download output

---

# Template Standard

Use the same JSON-driven style for all pods.

Only these values should change by pod:

* folder
* base URL
* auth source
* audit endpoint
* notification source
* notification pass/fail patterns
* polling/retry settings
* run label
* workload zip name

---

# Relationship To Playwright

REST is the primary driver for backend validation.

Playwright should be used only when the test requires UI confirmation, login, notification viewing, or other browser-only evidence.

---

# Outcome

This framework provides a repeatable REST execution model that can be used across pods and across both normal and SCU runs.

