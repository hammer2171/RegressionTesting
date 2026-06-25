# Playwright MCP Procedures

This folder is for human-authored MCP procedure markdown files. Each procedure tells the Playwright MCP runner what to do in headed mode and what evidence to capture.

The `.md` file is the source of truth. Keep Playwright spec files and generated evidence separate.

## Folder Layout

- `procedures`: MCP procedure markdown files that describe a test flow.
- `templates`: reusable markdown templates for new procedures.
- `evidence-protocol.md`: the standard evidence rules MCP should follow while executing a procedure.

## How To Use

1. Copy `templates/mcp-procedure-template.md` into `procedures`.
2. Rename it with a clear test id, for example `edm-request-create.mcp.md`.
3. Fill in the goal, starting URL, login/auth expectations, steps, assertions, and evidence requirements.
4. Ask Codex/MCP to execute that exact markdown file using Playwright MCP in headed mode.
5. Evidence should be written to a timestamped run folder under `C:\RegressionTesting\<Folder>\Runs`.

## Execution Prompt

Use this pattern when asking MCP to run a procedure:

```text
Use Playwright MCP in headed mode. Read and execute:
C:\RegressionTesting\<Folder>\documentation\mcp-procedures\procedures\edm-request-create.mcp.md

Follow the evidence protocol in:
C:\RegressionTesting\<Folder>\documentation\mcp-procedures\evidence-protocol.md
```

## Procedure Rules

- Write actions as numbered steps.
- Put expected results under each step when validation matters.
- Request screenshots only at useful checkpoints, not every tiny click unless the test needs it.
- Name business data explicitly: view, viewpoint, node, request title, policy name, or property value.
- Keep secrets out of markdown. Use Playwright storage state or environment/CMS-backed auth.
- If MCP has to choose a selector, it should take a fresh snapshot, use accessible labels first, and log what it clicked.

