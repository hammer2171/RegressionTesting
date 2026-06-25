# Oracle Cloud EPM AI Automation Framework

## Playwright Framework

### Version 1.0

**Owner:** Russell Shellhamer

---

# Purpose

This document defines the Playwright execution model for Oracle Cloud EPM regression testing across multiple pod folders.

The goal is to keep one Playwright framework version while allowing multiple folder roots such as `epm-test`, `<Folder>`, and future pod folders under `C:\RegressionTesting`.

---

# Folder Model

Each pod should have its own root folder:

```text
C:\RegressionTesting\<Folder>
```

Inside each pod root, Playwright lives at:

```text
C:\RegressionTesting\<Folder>\Playwright
```

The pod folder is configuration, not code.

---

# Core Principle

The Playwright framework should be able to run from any supported pod folder without changing source code.

Only these values should change:

* folder name
* pod URL
* storage state path
* `.env` file
* auth user key

---

# Project Structure

Recommended pod structure:

```text
C:\RegressionTesting\<Folder>
  documentation
  reference
  scripts
  Runs
  Playwright
```

Recommended Playwright structure:

```text
Playwright
  components
  docs
  output
  pages
  playwright
  scripts
  snippets
  tests
```

---

# Configuration Strategy

The Playwright config should resolve:

* pod root
* regression root
* base URL
* storage state
* env file
* headless mode
* slow motion

The config should prefer pod-local settings when available and fall back to defaults when not.

---

# Authentication Strategy

Use storage state by default for UI runs.

Use the auth session helper to refresh or reuse storage state in the current pod folder.

Rules:

* one storage state per pod/user when needed
* never commit auth JSON
* keep auth files inside the pod folder
* allow env override for special cases

---

# Evidence Strategy

Playwright evidence runs should capture:

* trace
* screenshots
* video
* HTML report
* JUnit and blob reports when requested

Evidence should land inside the current pod folder and its `Runs` tree.

---

# Run Strategy

Normal Playwright runs should write to:

```text
C:\RegressionTesting\<Folder>\Runs\<Run_Label>_yyyyMMdd_HHmmss
```

Evidence-oriented runs should include:

* screenshots
* trace
* video.webm
* final summary

---

# Pod Provisioning

Use one provisioning script to stamp multiple pod folders from the same Playwright version.

The provisioner should create:

* outer pod folder
* `documentation`
* `reference`
* `scripts`
* `Runs`
* `Playwright`

It may also copy template contents from an existing pod folder when requested.

---

# Cross-Pod Strategy

To support many pods with one Playwright version:

* keep selectors reusable
* keep auth behavior consistent
* keep evidence rules the same
* parameterize the folder and base URL

The pod folder should be a runtime input, not a separate code branch.

---

# Outcome

This framework lets one Playwright scaffold support multiple Oracle Cloud EPM pods with consistent evidence, auth, and run-folder behavior.

