# MCP Procedure Skills

- Treat `.mcp.md` files in `procedures` as the source of truth for Playwright MCP execution.
- Execute procedures in headed mode and follow `evidence-protocol.md`.
- Keep procedure markdown separate from generated Playwright tests, logs, screenshots, traces, and run evidence.
- Use fresh MCP snapshots before interacting with elements and after meaningful page changes.
- Prefer accessible roles, labels, and visible text over brittle selectors.
- Write run artifacts to timestamped folders under `C:\RegressionTesting\<Folder>\Runs`.
- Stop and capture failure evidence when a step cannot be completed or the UI is ambiguous.

