# Oracle Cloud EPM AI Automation Framework

## MCP + Playwright + EPMAutomate + REST APIs

### Master Design Document (Version 1.0)

**Author:** Russell Shellhamer

**Framework:** Oracle Cloud EPM Automation Framework

**Status:** Design Phase

---

# Vision

Create an AI-driven Oracle Cloud EPM automation framework where the user simply describes **what** they want accomplished in a Markdown document, and the framework determines **how** to execute the request using the most appropriate Oracle Cloud EPM automation technologies.

The framework should minimize manual test development while maximizing reuse, maintainability, scalability, and automation coverage across Oracle Cloud EPM.

---

# Primary Objective

Move from:

> Record → Edit → Execute

to

> Describe → AI Executes → Framework Generates → Regression Suite Updated

The Markdown document becomes the single source of truth.

---

# Overall Architecture

```
Markdown Task
        │
        ▼
ChatGPT
        │
        ▼
Task Parser
        │
        ▼
Execution Engine
        │
        ├───────────────┐
        │               │
        ▼               ▼
Playwright MCP      Oracle APIs
        │               │
        ▼               ▼
Oracle Cloud EPM
        │
        ▼
Validation Engine
        │
        ▼
Artifacts
```

---

# Framework Components

## User Layer

The user creates a Markdown file describing:

* Business process
* Module
* Environment
* Inputs
* Validations
* Evidence required
* Desired outputs

No implementation details are required.

---

## AI Layer

ChatGPT should:

* Read Markdown
* Understand intent
* Build execution plan
* Select correct tools
* Execute tasks
* Validate results
* Produce artifacts

---

## Execution Layer

Execution may use one or more of:

* Playwright MCP Server
* Playwright
* EPMAutomate
* Replay
* simulateConcurrentUsage
* REST APIs
* Huron Integration Framework
* OCUST
* JMeter
* LoadRunner

The user never specifies which technology.

The framework determines that automatically.

---

# Oracle Cloud EPM Modules

The framework will support:

* EDM
* FCCS
* Planning
* Workforce Planning
* Capex Planning
* Sales Planning
* FreeForm Planning
* PCMCS
* Narrative Reporting
* TRCS
* ARCS

Additional modules can be added without changing the framework architecture.

---

# Task Types

## Task.md

Executes a single Oracle Cloud EPM task.

Examples:

* Create Base Member
* Delete Entity
* Create Cost Center
* Run Business Rule
* Load Data
* Execute Data Map

---

## Workflow.md

Executes an end-to-end business process.

Examples:

* Monthly Close
* Quarterly Forecast
* Year-End Processing
* Metadata Promotion
* Financial Consolidation

---

## Regression.md

Executes an entire regression suite.

Examples:

* Planning Smoke Test
* FCCS Regression
* EDM Regression
* ARCS Regression

---

## Performance.md

Executes performance and stress testing.

Examples:

* simulateConcurrentUsage
* Replay
* Concurrent Users
* JMeter
* LoadRunner

Collect:

* Response Times
* Errors
* Performance Metrics
* CPU Usage
* Duration
* Screenshots

---

## Investigation.md

Allows AI to investigate problems.

Examples:

* Why did this test fail?
* Why is Save disabled?
* Find broken locator.
* Explain business rule failure.
* Compare previous execution.

---

# Standard Markdown Format

```yaml
Task: Create Base Member

Module: EDM

Environment:

    Pod: epm18-test

Goal:

    Create new Base Entity

Inputs:

    Parent: Operations

    Member:

        Name: USA_10001

        Description: Created by MCP

Validation:

    - Member Exists

    - Parent Correct

    - Request Successful

Evidence:

    Screenshot: true

    Trace: true

Output:

    Test

    Report

    Screenshots
```

---

# Framework Responsibilities

The framework should automatically:

Read Markdown

Understand user intent

Launch Oracle Cloud EPM

Authenticate using Storage State

Navigate application

Perform requested task

Validate outcome

Collect evidence

Generate Playwright test

Generate reusable Page Objects

Generate helper methods

Generate reports

Store artifacts

---

# Oracle Cloud EPM Tool Integration

The framework should support:

## Playwright

* Functional Testing
* UI Automation
* Recording
* Replay
* Screenshots
* Trace Viewer

---

## Playwright MCP Server

AI-driven browser interaction.

Capabilities:

* Navigate Oracle EPM
* Read page
* Locate controls
* Inspect DOM
* Generate selectors
* Execute tasks
* Debug failures

---

## EPMAutomate

Execute:

* Business Rules
* Data Loads
* Refresh Cubes
* Snapshots
* Reports
* Metadata Imports
* File Transfers

---

## Replay

Replay recorded Oracle EPM user activity.

---

## simulateConcurrentUsage

Stress testing

Performance testing

Concurrent user testing

---

## REST APIs

Execute Oracle Cloud EPM REST APIs.

Validate responses.

Retrieve status.

Compare results.

---

## Huron Integration Framework

Execute:

* Integrations
* Data movement
* Orchestration

---

## OCUST

Future integration for Oracle Cloud regression automation.

---

## Performance Tools

Support:

* JMeter
* LoadRunner
* Dynatrace
* AppDynamics
* New Relic

---

# Generated Artifacts

The framework should automatically create:

Playwright Tests

Page Objects

Reusable Components

Helper Methods

Reports

Evidence

Videos

Screenshots

Trace Files

Performance Metrics

Regression Results

---

# Project Structure

```
Playwright
│
├── automation
│   ├── tasks
│   ├── workflows
│   ├── regression
│   ├── performance
│   └── investigation
│
├── pages
├── components
├── helpers
├── snippets
├── fixtures
├── tests
│
│   ├── edm
│   ├── planning
│   ├── fccs
│   ├── arcs
│   ├── trcs
│   ├── narrative
│   ├── workforce
│   ├── capex
│   ├── sales
│   └── freeform
│
├── reports
├── traces
├── screenshots
└── videos
```

---

# Long-Term Vision

The Oracle Cloud EPM AI Automation Framework becomes an intelligent automation platform capable of:

* Recording tests
* Generating tests
* Refactoring tests
* Executing regression suites
* Running stress tests
* Running performance tests
* Executing Oracle REST APIs
* Running EPMAutomate
* Executing Replay
* Executing simulateConcurrentUsage
* Investigating failures
* Explaining failures
* Generating reports
* Producing evidence

The user describes **WHAT** they want.

The framework determines **HOW** to accomplish it.

---

# Phase 2 Goals

The next phase of development will focus on building:

1. A Markdown Domain-Specific Language (DSL) for Oracle Cloud EPM automation.
2. A parser that interprets Markdown task definitions.
3. An execution engine that selects and orchestrates the appropriate technologies (Playwright MCP, EPMAutomate, REST APIs, Replay, performance tools).
4. Automatic generation of Playwright tests, reusable Page Objects, helper methods, evidence, and reports.
5. A unified AI-driven workflow where a business-oriented task description becomes a fully executable Oracle Cloud EPM automation process.

This document serves as the master blueprint for implementing the Oracle Cloud EPM AI Automation Framework.
