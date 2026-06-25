#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';

function getArg(name, fallback = null) {
  const idx = process.argv.findIndex((arg) => arg === name);
  if (idx >= 0 && process.argv[idx + 1]) return process.argv[idx + 1];
  return fallback;
}

function parseIntArg(name, fallback) {
  const raw = getArg(name, null);
  if (!raw) return fallback;
  const n = Number(raw);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
}

function ts() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}_${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
}

async function exists(p) {
  try {
    await fs.access(p);
    return true;
  } catch {
    return false;
  }
}

async function copyIfExists(from, to, copied) {
  if (!(await exists(from))) return;
  await fs.mkdir(path.dirname(to), { recursive: true });
  await fs.cp(from, to, { recursive: true, force: true });
  copied.push({ from, to });
}

async function moveIfExists(from, to, moved) {
  if (!(await exists(from))) return;
  await fs.mkdir(path.dirname(to), { recursive: true });
  try {
    await fs.rename(from, to);
  } catch {
    await fs.cp(from, to, { recursive: true, force: true });
    await fs.rm(from, { recursive: true, force: true });
  }
  moved.push({ from, to });
}

async function main() {
  const cwd = process.cwd();
  const label = (getArg('--label', 'playwright') || 'playwright').replace(/[^a-zA-Z0-9_-]/g, '_');
  const runRootArg = getArg('--run-root', '').trim();
  const mode = (getArg('--mode', 'copy') || 'copy').toLowerCase();
  const waitMs = parseIntArg('--wait-ms', 0);

  const runRoot = runRootArg
    ? (path.isAbsolute(runRootArg) ? runRootArg : path.resolve(cwd, runRootArg))
    : path.join(cwd, 'Runs', `Run_${ts()}_${label}`);
  const runId = path.basename(runRoot);

  await fs.mkdir(runRoot, { recursive: true });
  const copied = [];

  const sources = [
    path.join(cwd, 'test-results'),
    path.join(cwd, 'playwright-report'),
    path.join(cwd, 'blob-report'),
    path.join(cwd, 'junit.xml'),
    path.join(cwd, 'results.xml'),
    path.join(cwd, 'output', 'playwright-evidence.md'),
    path.join(cwd, 'output', 'trace-images'),
    path.join(cwd, 'output', 'ui-validations', label),
  ];

  if (waitMs > 0) {
    const deadline = Date.now() + waitMs;
    // Wait briefly for artifact writers to finish before copying/moving.
    while (Date.now() < deadline) {
      let anyExists = false;
      for (const src of sources) {
        if (await exists(src)) {
          anyExists = true;
          break;
        }
      }
      if (anyExists) break;
      await new Promise((r) => setTimeout(r, 500));
    }
  }

  const copier = mode === 'move' ? moveIfExists : copyIfExists;

  await copier(path.join(cwd, 'test-results'), path.join(runRoot, 'test-results'), copied);
  await copier(path.join(cwd, 'playwright-report'), path.join(runRoot, 'playwright-report'), copied);
  await copier(path.join(cwd, 'blob-report'), path.join(runRoot, 'blob-report'), copied);
  await copier(path.join(cwd, 'junit.xml'), path.join(runRoot, 'junit.xml'), copied);
  await copier(path.join(cwd, 'results.xml'), path.join(runRoot, 'results.xml'), copied);
  await copier(path.join(cwd, 'output', 'playwright-evidence.md'), path.join(runRoot, 'output', 'playwright-evidence.md'), copied);
  await copier(path.join(cwd, 'output', 'trace-images'), path.join(runRoot, 'output', 'trace-images'), copied);
  await copier(
    path.join(cwd, 'output', 'ui-validations', label),
    path.join(runRoot, 'output', 'ui-validations', label),
    copied
  );

  const manifest = {
    runId,
    createdAt: new Date().toISOString(),
    mode,
    copied,
  };
  await fs.writeFile(path.join(runRoot, 'artifact-manifest.json'), JSON.stringify(manifest, null, 2), 'utf8');

  console.log(`Archived artifacts to: ${runRoot}`);
  if (copied.length === 0) {
    console.log('No source artifact folders were found to copy/move.');
  } else {
    for (const item of copied) {
      console.log(`- ${path.relative(cwd, item.from)} -> ${path.relative(cwd, item.to)}`);
    }
  }
}

main().catch((err) => {
  console.error(err?.message || err);
  process.exit(1);
});
