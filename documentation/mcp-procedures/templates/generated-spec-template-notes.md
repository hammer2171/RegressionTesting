# Generated Test Notes

Generated MCP procedure specs are intentionally split into two phases:

1. Generate a Playwright evidence test shell from the `.mcp.md` file.
2. Use Codex with Playwright MCP headed snapshots to fill in the action code inside each generated `test.step`.

This keeps the markdown as the business instruction source while letting Playwright produce repeatable evidence: screenshots, trace, video.webm, HTML report, JUnit, blob report, and archived run output.

Selector/navigation policy:

- MCP may improvise selectors and navigation from live snapshots.
- Use accessible roles, labels, visible text, and stable URLs first.
- Log the chosen route in the generated test comments or step notes when the navigation is not obvious.
- Re-snapshot after page transitions, menus, dialogs, drawers, and save/submit actions.
