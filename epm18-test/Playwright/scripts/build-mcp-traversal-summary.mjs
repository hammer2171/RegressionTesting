#!/usr/bin/env node

import fs from 'node:fs/promises';
import path from 'node:path';

const DEFAULT_LABEL = 'mcp_full_site_traversal';

function normalizePath(value) {
  return value.replace(/\\/g, '/');
}

function safeName(value) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

async function pathExists(target) {
  try {
    await fs.access(target);
    return true;
  } catch {
    return false;
  }
}

async function latestRunFolder(cwd, label) {
  const runsDir = path.join(cwd, 'Runs');
  const entries = await fs.readdir(runsDir, { withFileTypes: true });
  const candidates = [];

  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    if (label && !entry.name.includes(label)) continue;

    const fullPath = path.join(runsDir, entry.name);
    const stat = await fs.stat(fullPath);
    candidates.push({ fullPath, mtimeMs: stat.mtimeMs });
  }

  candidates.sort((a, b) => b.mtimeMs - a.mtimeMs);
  return candidates[0]?.fullPath ?? null;
}

async function walkFiles(dir) {
  const entries = await fs.readdir(dir, { withFileTypes: true }).catch(() => []);
  const files = [];

  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...await walkFiles(fullPath));
    } else if (entry.isFile()) {
      files.push(fullPath);
    }
  }

  return files;
}

function parseSnapshotPath(runFolder, filePath) {
  const rel = normalizePath(path.relative(runFolder, filePath));
  const parts = rel.split('/');
  const snapshotRoot = parts.findIndex((part) => part === 'aria-snapshots-full');
  if (snapshotRoot < 0) return null;

  const tile = parts[snapshotRoot + 1];
  const fileName = parts.at(-1);
  if (!tile || !fileName) return null;

  const jsonMatch = fileName.match(/^(\d+)-(.+)\.(aria|locators)\.json$/);
  if (jsonMatch) {
    return {
      rel,
      tile,
      step: Number(jsonMatch[1]),
      state: jsonMatch[2],
      kind: jsonMatch[3],
      fileName,
    };
  }

  const screenshotMatch = fileName.match(/^(\d+)-(.+)\.png$/);
  if (screenshotMatch) {
    return {
      rel,
      tile,
      step: Number(screenshotMatch[1]),
      state: screenshotMatch[2],
      kind: 'screenshot',
      fileName,
    };
  }

  return null;
}

async function readJson(filePath) {
  return JSON.parse(await fs.readFile(filePath, 'utf8'));
}

function summarizeLocators(data) {
  const rawScopes = Array.isArray(data?.scopes) && data.scopes.length
    ? data.scopes
    : [{ scope: 'page', links: data?.links, buttons: data?.buttons }];
  const scopes = rawScopes.map((scope) => {
    const links = Array.isArray(scope?.links) ? scope.links : [];
    const buttons = Array.isArray(scope?.buttons) ? scope.buttons : [];
    const rawRoles = scope?.roles && typeof scope.roles === 'object' ? scope.roles : {};
    const roles = Object.fromEntries(
      Object.entries(rawRoles)
        .filter(([, values]) => Array.isArray(values) && values.length)
        .map(([role, values]) => [role, values])
    );
    if (!roles.link && links.length) roles.link = links;
    if (!roles.button && buttons.length) roles.button = buttons;

    return {
      scope: scope?.scope ?? 'page',
      frameSelector: scope?.frameSelector ?? null,
      frameName: scope?.frameName ?? null,
      frameUrl: scope?.frameUrl ?? null,
      linkCount: links.length,
      buttonCount: buttons.length,
      links,
      buttons,
      roles,
      roleCounts: Object.fromEntries(Object.entries(roles).map(([role, values]) => [role, values.length])),
    };
  });
  const links = [...new Set(scopes.flatMap((scope) => scope.links))];
  const buttons = [...new Set(scopes.flatMap((scope) => scope.buttons))];
  const roleNames = [...new Set(scopes.flatMap((scope) => Object.keys(scope.roles)))].sort();
  const roles = Object.fromEntries(roleNames.map((role) => [
    role,
    [...new Set(scopes.flatMap((scope) => scope.roles[role] ?? []))],
  ]));

  return {
    linkCount: links.length,
    buttonCount: buttons.length,
    scopeCount: scopes.length,
    frameScopeCount: scopes.filter((scope) => scope.scope !== 'page').length,
    links,
    buttons,
    roles,
    roleCounts: Object.fromEntries(Object.entries(roles).map(([role, values]) => [role, values.length])),
    scopes,
  };
}

function markdownList(items) {
  if (!items.length) return '';
  return items.map((item) => `  - ${item}`).join('\n');
}

function buildMarkdown(summary) {
  const lines = [
    '# MCP Full Site Traversal Summary',
    '',
    `Run: ${summary.runId}`,
    `Generated: ${summary.generatedAt}`,
    `Status: ${summary.status}`,
    '',
    `Tiles: ${summary.totals.tiles}`,
    `ARIA snapshots: ${summary.totals.ariaSnapshots}`,
    `Locator snapshots: ${summary.totals.locatorSnapshots}`,
    `Screen snapshots: ${summary.totals.screenSnapshots}`,
    '',
  ];

  for (const tile of summary.tiles) {
    lines.push(`## ${tile.tile}`);
    lines.push('');
    lines.push('| Step | State | Scopes | Frames | Links | Buttons | Screen |');
    lines.push('| ---: | --- | ---: | ---: | ---: | ---: | --- |');

    for (const state of tile.states) {
      const screen = state.screenshotFile ? 'yes' : '';
      lines.push(`| ${state.step} | ${state.state} | ${state.scopeCount} | ${state.frameScopeCount} | ${state.linkCount} | ${state.buttonCount} | ${screen} |`);
    }

    for (const state of tile.states) {
      if (!state.links.length && !state.buttons.length && !state.scopes.length) continue;
      lines.push('');
      lines.push(`### ${tile.tile} / ${state.state}`);
      if (state.scopes.length) {
        lines.push('');
        lines.push('Scopes:');
        for (const scope of state.scopes) {
          const roleSummary = Object.entries(scope.roleCounts ?? {})
            .map(([role, count]) => `${role}=${count}`)
            .join(', ');
          lines.push(`  - ${scope.scope}: ${scope.linkCount} links, ${scope.buttonCount} buttons${roleSummary ? ` (${roleSummary})` : ''}`);
        }
      }
      if (Object.keys(state.roleCounts).length) {
        lines.push('');
        lines.push('Role counts:');
        for (const [role, count] of Object.entries(state.roleCounts).sort(([a], [b]) => a.localeCompare(b))) {
          lines.push(`  - ${role}: ${count}`);
        }
      }
      if (state.links.length) {
        lines.push('');
        lines.push('Links:');
        lines.push(markdownList(state.links));
      }
      if (state.buttons.length) {
        lines.push('');
        lines.push('Buttons:');
        lines.push(markdownList(state.buttons));
      }
    }

    lines.push('');
  }

  return `${lines.join('\n').trim()}\n`;
}

async function buildSummary(runFolder) {
  const testResultsDir = path.join(runFolder, 'test-results');
  if (!await pathExists(testResultsDir)) {
    throw new Error(`No test-results folder found under ${runFolder}`);
  }

  const files = await walkFiles(testResultsDir);
  const snapshotFiles = files
    .map((filePath) => ({ filePath, parsed: parseSnapshotPath(runFolder, filePath) }))
    .filter((item) => item.parsed);

  const byTile = new Map();

  for (const { filePath, parsed } of snapshotFiles) {
    if (!byTile.has(parsed.tile)) byTile.set(parsed.tile, new Map());
    const states = byTile.get(parsed.tile);
    const key = `${parsed.step}-${parsed.state}`;
    if (!states.has(key)) {
      states.set(key, {
        step: parsed.step,
        state: parsed.state,
        ariaFile: null,
        locatorsFile: null,
        screenshotFile: null,
        linkCount: 0,
        buttonCount: 0,
        scopeCount: 0,
        frameScopeCount: 0,
        links: [],
        buttons: [],
        roles: {},
        roleCounts: {},
        scopes: [],
      });
    }

    const state = states.get(key);
    if (parsed.kind === 'aria') {
      state.ariaFile = parsed.rel;
    } else if (parsed.kind === 'locators') {
      state.locatorsFile = parsed.rel;
      Object.assign(state, summarizeLocators(await readJson(filePath)));
    } else if (parsed.kind === 'screenshot') {
      state.screenshotFile = parsed.rel;
    }
  }

  const lastRunPath = path.join(testResultsDir, '.last-run.json');
  const lastRun = await pathExists(lastRunPath) ? await readJson(lastRunPath) : {};

  const tiles = [...byTile.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([tile, states]) => ({
      tile,
      states: [...states.values()].sort((a, b) => a.step - b.step || a.state.localeCompare(b.state)),
    }));

  return {
    runId: path.basename(runFolder),
    runFolder: normalizePath(runFolder),
    generatedAt: new Date().toISOString(),
    status: lastRun.status ?? 'unknown',
    failedTests: Array.isArray(lastRun.failedTests) ? lastRun.failedTests : [],
    totals: {
      tiles: tiles.length,
      ariaSnapshots: snapshotFiles.filter((item) => item.parsed.kind === 'aria').length,
      locatorSnapshots: snapshotFiles.filter((item) => item.parsed.kind === 'locators').length,
      screenSnapshots: snapshotFiles.filter((item) => item.parsed.kind === 'screenshot').length,
      locatorScopes: tiles.reduce((sum, tile) => sum + tile.states.reduce((stateSum, state) => stateSum + state.scopeCount, 0), 0),
      frameLocatorScopes: tiles.reduce((sum, tile) => sum + tile.states.reduce((stateSum, state) => stateSum + state.frameScopeCount, 0), 0),
    },
    tiles,
  };
}

async function main() {
  const cwd = process.cwd();
  const requested = process.argv[2];
  const runFolder = requested
    ? path.resolve(cwd, requested)
    : await latestRunFolder(cwd, DEFAULT_LABEL);

  if (!runFolder) {
    throw new Error(`No Runs folder found for label ${DEFAULT_LABEL}`);
  }

  const summary = await buildSummary(runFolder);
  const outputDir = path.join(runFolder, 'output', 'ui-validations', DEFAULT_LABEL);
  await fs.mkdir(outputDir, { recursive: true });

  const jsonPath = path.join(outputDir, `${DEFAULT_LABEL}_summary.json`);
  const mdPath = path.join(outputDir, `${DEFAULT_LABEL}_summary.md`);

  await fs.writeFile(jsonPath, `${JSON.stringify(summary, null, 2)}\n`, 'utf8');
  await fs.writeFile(mdPath, buildMarkdown(summary), 'utf8');

  console.log(`Run: ${summary.runId}`);
  console.log(`Status: ${summary.status}`);
  console.log(`Tiles: ${summary.totals.tiles}`);
  console.log(`ARIA snapshots: ${summary.totals.ariaSnapshots}`);
  console.log(`Locator snapshots: ${summary.totals.locatorSnapshots}`);
  console.log(`Screen snapshots: ${summary.totals.screenSnapshots}`);
  console.log(`Locator scopes: ${summary.totals.locatorScopes}`);
  console.log(`Frame locator scopes: ${summary.totals.frameLocatorScopes}`);
  console.log(`Wrote: ${jsonPath}`);
  console.log(`Wrote: ${mdPath}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
