#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';

function getArg(name, fallback = '') {
  const idx = process.argv.findIndex((arg) => arg === name);
  if (idx >= 0 && process.argv[idx + 1]) return process.argv[idx + 1];
  return fallback;
}

function hasArg(name) {
  return process.argv.includes(name);
}

function slugify(value, fallback = 'mcp-procedure') {
  const slug = String(value || '')
    .trim()
    .toLowerCase()
    .replace(/`/g, '')
    .replace(/[^a-z0-9_.-]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return slug || fallback;
}

function escapeTs(value) {
  return String(value ?? '')
    .replace(/\\/g, '\\\\')
    .replace(/`/g, '\\`')
    .replace(/\$\{/g, '\\${');
}

function getFirstMatch(markdown, regex, fallback = '') {
  const match = markdown.match(regex);
  return match ? match[1].trim() : fallback;
}

function parseSteps(markdown) {
  const lines = markdown.split(/\r?\n/);
  const steps = [];
  let current = null;

  for (const line of lines) {
    const stepMatch = line.match(/^(\d+)\.\s+(.+?)\s*$/);
    if (stepMatch) {
      if (current) steps.push(current);
      current = {
        number: Number(stepMatch[1]),
        title: stepMatch[2].trim(),
        lines: [],
      };
      continue;
    }

    if (current) current.lines.push(line);
  }

  if (current) steps.push(current);
  return steps;
}

function buildStepImplementation(step, index) {
  const stepId = String(index + 1).padStart(2, '0');
  const detail = step.lines.join('\n').trim();
  return `  await test.step(\`${stepId} - ${escapeTs(step.title)}\`, async () => {
    await recordStep(testInfo, \`${stepId}\`, \`${escapeTs(step.title)}\`, \`${escapeTs(detail)}\`);

    /*
     * MCP implementation area:
     * - Take a fresh Playwright MCP snapshot before choosing selectors.
     * - Improvise navigation/selectors from accessible roles, labels, and visible text.
     * - Replace this comment with concrete Playwright actions after MCP exploration.
     */

    await page.screenshot({ path: testInfo.outputPath(\`${stepId}-checkpoint.png\`), fullPage: true });
  });`;
}

async function main() {
  const procedureArg = getArg('--procedure', getArg('-p'));
  if (!procedureArg) {
    console.error('Usage: node scripts/New-McpProcedureSpec.mjs --procedure mcp-procedures/procedures/name.mcp.md');
    process.exit(1);
  }

  const cwd = process.cwd();
  const procedurePath = path.resolve(cwd, procedureArg);
  const markdown = await fs.readFile(procedurePath, 'utf8');
  const title = getFirstMatch(markdown, /^#\s+MCP Procedure:\s*(.+)$/m, path.basename(procedurePath, '.md'));
  const declaredId = getFirstMatch(markdown, /^Procedure ID:\s*`?([^`\r\n]+)`?/m, '');
  const url = getFirstMatch(markdown, /^URL:\s*`?([^`\r\n]+)`?/m, '');
  const procedureId = slugify(declaredId || path.basename(procedurePath).replace(/\.mcp\.md$/i, ''), 'mcp-procedure');
  const steps = parseSteps(markdown);
  const relativeProcedurePath = path.relative(cwd, procedurePath).replace(/\\/g, '/');
  const outDir = path.resolve(cwd, getArg('--out-dir', 'tests/mcp-procedures'));
  const outPath = path.join(outDir, `${procedureId}.spec.ts`);
  const overwrite = hasArg('--force');

  if (!overwrite) {
    try {
      await fs.access(outPath);
      throw new Error(`Spec already exists: ${outPath}. Use --force to overwrite.`);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }

  await fs.mkdir(outDir, { recursive: true });

  const spec = `import fs from 'node:fs/promises';
import path from 'node:path';
import { test, expect, type TestInfo } from '@playwright/test';

const procedurePath = path.resolve(process.cwd(), '${escapeTs(relativeProcedurePath)}');
const procedureId = '${escapeTs(procedureId)}';
const procedureTitle = \`${escapeTs(title)}\`;
const procedureUrl = '${escapeTs(url)}';

test.describe(\`MCP Procedure - \${procedureTitle}\`, () => {
  test(\`\${procedureId} full evidence run\`, async ({ page, baseURL }, testInfo) => {
    const procedureMarkdown = await fs.readFile(procedurePath, 'utf8');
    await testInfo.attach('mcp-procedure.md', {
      body: procedureMarkdown,
      contentType: 'text/markdown',
    });

    const targetUrl = procedureUrl || baseURL;
    expect(targetUrl, 'Procedure URL or Playwright baseURL must be configured.').toBeTruthy();

    await page.goto(targetUrl!);
    await page.waitForLoadState('domcontentloaded');
    await page.screenshot({ path: testInfo.outputPath('00-start.png'), fullPage: true });

${steps.length ? steps.map(buildStepImplementation).join('\n\n') : `    throw new Error('No numbered steps were found in the MCP procedure markdown.');`}
  });
});

async function recordStep(testInfo: TestInfo, stepId: string, title: string, details: string): Promise<void> {
  const logPath = testInfo.outputPath('mcp-steps.md');
  const body = [
    \`## Step \${stepId} - \${title}\`,
    '',
    'Status: Pending MCP implementation',
    '',
    'Procedure Details:',
    details || '(none)',
    '',
  ].join('\\n');
  await fs.appendFile(logPath, body, 'utf8');
}
`;

  await fs.writeFile(outPath, spec, 'utf8');
  console.log(`Generated MCP procedure spec: ${outPath}`);
  console.log(`Steps found: ${steps.length}`);
  console.log('Next: use Playwright MCP headed snapshots to replace each MCP implementation area with concrete actions.');
}

main().catch((error) => {
  console.error(error?.message || error);
  process.exit(1);
});
