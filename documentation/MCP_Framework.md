# Oracle Cloud EPM AI Automation Framework

## MCP Framework

### Version 1.0

**Owner:** Russell Shellhamer

---

# Purpose

This document defines how Playwright MCP will be used across Oracle Cloud EPM pods to execute browser-driven regression work from Markdown instructions.

The goal is to let a tester write a procedure in markdown, point MCP at it, and have Playwright execute the steps in headed mode with repeatable evidence.

---

# Scope

This framework applies to:

* All Oracle Cloud EPM pods used in regression testing
* Playwright headed execution
* MCP-driven browser navigation and interaction
* Evidence runs with screenshots, traces, video, and logs
* Markdown procedures that describe business intent

It does not replace Playwright tests, REST scripts, or EPMAutomate scripts.

Instead, it defines when MCP should drive the UI and how that work is turned into maintainable regression automation.

---

# Core Principle

The user writes what they want done.

MCP determines how to navigate the UI, select controls, and complete the task using live browser snapshots and Playwright evidence.

Selectors may be improvised from the live page when necessary, but the chosen route must be logged and repeatable.

---

# Pod Strategy

Each pod should have the same execution model:

* A pod folder under `C:\RegressionTesting`
* A pod-specific base URL
* A pod-specific `.env` file
* A pod-specific storage-state file
* A shared MCP procedure format
* A shared evidence protocol
* A shared Playwright scaffold

The pod should never change the strategy.

Only the configuration values change.

---

# Pod Profile Model

Each pod should have a simple profile:

* Folder name
* Pod key
* Pod URL
* Storage-state path
* Optional auth user key
* Optional environment file

Recommended examples:

* `<Folder>`
* `epm22-test`
* `epm20-test`

Each pod profile should resolve to:

* `REGRESSION_ROOT = C:\RegressionTesting\<Folder>`
* `EPM_BASE_URL`
* `PW_STORAGE_STATE`
* `PW_AUTH_USER_KEY`
* `ENV_FILE`

---

# Procedure Model

An MCP procedure is a markdown file that contains:

* Goal
* Pod or environment
* Test data
* Preconditions
* Steps
* Evidence checkpoints
* Validation expectations
* Do not rules

The markdown file is the source of truth.

Playwright generates the executable test from that file.

For new tests, start from `MCP_Test_Template.md` and fill in the required inputs, evidence checkpoints, and selector guidance before asking MCP to run it.

---

# Recommended Procedure Format

```md
# MCP Procedure: Create Request

Procedure ID: create-request
Pod: <Folder>
URL: https://...
Auth: storage-state

## Goal

Create a request and submit it.

## Test Data

- View:
- Viewpoint:
- Request title:

## Preconditions

- User has access to the view
- Storage state exists

## Steps

1. Open the pod URL.
2. Login if needed.
3. Navigate to the target view.
4. Create the request.
5. Submit the request.

## Evidence Checkpoints

- After login
- After navigation
- After request creation
- After submit
```

---

# Selector Strategy

MCP should use this order when interacting with the UI:

1. Accessible role and label
2. Visible text
3. Stable attributes
4. Page snapshot references
5. Fallback selectors only when required

When the UI is ambiguous:

* take a fresh snapshot
* record the ambiguity
* choose the least brittle path
* capture evidence before continuing

---

# Navigation Strategy

MCP should navigate like a human operator who is also keeping evidence:

* open the pod URL
* verify the landing page
* login if the storage state is missing or stale
* re-snapshot after any major page transition
* log each click path
* capture checkpoints before saving or submitting

Navigation may be improvised if the page layout changes, but the outcome must remain the same.

---

# Authentication Strategy

Authentication should use Playwright storage state by default.

Rules:

* One storage state per pod and user, when needed
* Refresh storage state only when expired
* Do not log passwords or cookies
* Keep auth files outside source control
* Use the same auth approach across pods when possible

If a pod requires a refresh, the procedure should state that explicitly.

For REST-backed steps and hybrid UI/API procedures, use the authentication pattern established in the <Folder> PowerShell scripts:

* `Invoke-Epm18RestTemplate.ps1`
* `Get-Epm18ViewsTemplate.ps1`
* `Get-Epm18ApprovalPolicies.ps1`
* `Set-Epm18ApprovalPolicyEnabledFlag.ps1`

Those scripts are the canonical examples for:

* CMS-decrypted credentials
* Basic auth header construction
* parameterized REST endpoints
* timestamped run folders
* run-level logging

MCP-driven procedures should follow the same auth and logging shape when a REST call is required alongside Playwright.

---

# Evidence Strategy

Every MCP execution should produce a timestamped run folder.

Required evidence:

* run log
* procedure markdown copy
* screenshots at checkpoints
* Playwright trace
* video.webm
* final result summary

The run folder should be treated as a disposable execution record, not a place for reusable source.

---

# Evidence Folder Shape

Recommended layout:

```text
Runs
  \ yyyyMMdd_HHmmss_<procedure-id>
      run.log
      procedure.md
      steps.md
      screenshots
      trace
      video.webm
      artifacts
```

---

# Playwright Handshake

MCP is the browser interaction layer.

Playwright is the execution and evidence layer.

That means:

* MCP explores the page
* Playwright runs the final repeatable test
* Playwright records trace, screenshot, and video
* The generated test can be rerun without MCP when selectors are stable

This keeps MCP useful without making it the only way to execute.

---

# Generation Strategy

The workflow should be:

1. Write the procedure markdown
2. Use MCP to discover selectors and page flow
3. Generate a Playwright test from the markdown
4. Run the generated test in evidence mode
5. Archive the run folder

This lets the markdown stay human-readable while the generated test becomes the regression asset.

---

# Cross-Pod Strategy

To use the same framework on all pods:

* keep the procedure format identical
* keep the evidence protocol identical
* keep the test generator identical
* swap only pod settings and auth files

The pod should be configuration, not a separate framework.

---

# Logging Strategy

Every MCP session should log:

* pod URL
* procedure ID
* current step
* chosen selector route
* navigation decisions
* validation outcome
* evidence file names

Logging should be concise, timestamped, and useful for post-run triage.

---

# Failure Strategy

If MCP cannot safely continue:

* stop
* capture a screenshot
* capture a snapshot or trace when possible
* log the blocking condition
* mark the step as failed or blocked

Do not guess through a save, submit, or destructive action when the page is ambiguous.

---

# Standards

MCP procedures should:

* be plain markdown
* avoid secrets
* include test data
* include evidence checkpoints
* be pod-neutral where possible
* name the expected business result

Generated Playwright tests should:

* be deterministic
* use the same evidence conventions
* preserve the procedure markdown as an attachment or copied artifact
* be rerunnable without manual rewrite

---

# Rollout Plan

Phase 1:

* define the MCP markdown format
* define evidence and logging rules
* define pod profiles

Phase 2:

* generate Playwright tests from MCP markdown
* run headed evidence tests
* validate on a single pod

Phase 3:

* standardize the workflow across all pods
* create reusable templates for common business tasks
* build a library of approved MCP procedures

---

# Outcome

This framework makes MCP a controlled, repeatable, pod-agnostic execution method for Playwright-driven Oracle Cloud EPM testing.

The user writes the procedure.

MCP explores and executes the flow.

Playwright preserves the evidence.

The same pattern can then be used across all pods.

