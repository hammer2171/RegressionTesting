#!/usr/bin/env node
import { spawn } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';

async function exists(p) {
  try {
    await fs.access(p);
    return true;
  } catch {
    return false;
  }
}

function run(command, args) {
  return new Promise((resolve) => {
    const child = spawn(command, args, {
      stdio: 'inherit',
      shell: false,
      windowsHide: false,
    });
    child.on('close', (code) => resolve(code ?? 1));
    child.on('error', () => resolve(1));
  });
}

function ts() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}_${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
}

const passthroughArgs = process.argv.slice(2);
const nodeCommand = process.execPath;
const playwrightCli = path.join('node_modules', '@playwright', 'test', 'cli.js');
const archiveLabel = (process.env.EVIDENCE_LABEL || 'full_evidence').replace(/[^a-zA-Z0-9_-]/g, '_');
const runHeadless = /^(1|true|yes)$/i.test(process.env.PW_HEADLESS ?? '');
const runId = `Run_${ts()}_${archiveLabel}`;
const runRoot = path.join(process.cwd(), 'Runs', runId);

await fs.mkdir(runRoot, { recursive: true });
await fs.writeFile(
  path.join(runRoot, 'run-context.json'),
  JSON.stringify(
    {
      runId,
      label: archiveLabel,
      startedAt: new Date().toISOString(),
      cwd: process.cwd(),
      command: ['playwright', 'test', ...passthroughArgs],
    },
    null,
    2
  ),
  'utf8'
);

const playwrightArgs = [
  playwrightCli,
  'test',
  '--project=edge',
  ...(runHeadless ? [] : ['--headed']),
  '-c',
  'playwright.evidence.config.js',
  '--reporter=list,html,junit,blob',
  ...passthroughArgs,
];

const playwrightExitCode = await run(nodeCommand, playwrightArgs);

const archiveScript = path.join('scripts', 'archive-playwright-artifacts.mjs');
await run(nodeCommand, [
  archiveScript,
  '--label',
  archiveLabel,
  '--run-root',
  runRoot,
  '--mode',
  'copy',
  '--wait-ms',
  '30000',
]);

const runTestResults = path.join(runRoot, 'test-results');
if (!(await exists(runTestResults))) {
  const rootTestResults = path.join(process.cwd(), 'test-results');
  console.log('[run-evidence] Skipping run-level UI validation PDF.');
  console.log(`[run-evidence] Archive did not populate the intended run folder: ${runTestResults}`);
  if (await exists(rootTestResults)) {
    console.log(`[run-evidence] Root test-results exists at: ${rootTestResults}`);
    console.log('[run-evidence] This usually means archive wrote somewhere unexpected or was interrupted.');
  } else {
    console.log('[run-evidence] Root test-results was not found either.');
    console.log('[run-evidence] This usually means the Playwright run stopped before artifacts were created.');
  }
  process.exit(playwrightExitCode);
}

const runUiValidationScript = path.join('scripts', 'build-run-ui-validations-from-master.mjs');
if (await exists(runUiValidationScript)) {
  const uiValidationExitCode = await run(nodeCommand, [
    runUiValidationScript,
    '--label',
    archiveLabel,
    '--run-root',
    runRoot,
  ]);
  if (uiValidationExitCode !== 0) {
    console.log('[run-evidence] Run-level UI validation PDF step failed (non-blocking).');
  }
}

process.exit(playwrightExitCode);
