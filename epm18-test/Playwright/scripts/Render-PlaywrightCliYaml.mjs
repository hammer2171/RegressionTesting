#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

function parseArgs(argv) {
  const args = { input: null, outdir: null };
  for (let i = 2; i < argv.length; i++) {
    const token = argv[i];
    if (token === '--input' || token === '-i') {
      args.input = argv[++i];
    } else if (token === '--outdir' || token === '-o') {
      args.outdir = argv[++i];
    } else if (!args.input) {
      args.input = token;
    }
  }
  return args;
}

function usage() {
  console.log(
    'Usage:\n' +
      '  node scripts/Render-PlaywrightCliYaml.mjs --input <file-or-folder> [--outdir <folder>]\n\n' +
      'Examples:\n' +
      '  node scripts/Render-PlaywrightCliYaml.mjs --input output/playwright/.../.playwright-cli/page-2026-...yml\n' +
      '  node scripts/Render-PlaywrightCliYaml.mjs --input output/playwright/epm22test-export-map_0151_20260409_160956/.playwright-cli\n'
  );
}

function escapeHtml(text) {
  return text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function getIndentLevel(line) {
  let spaces = 0;
  while (spaces < line.length && line[spaces] === ' ') {
    spaces++;
  }
  return Math.floor(spaces / 2);
}

function lineToLabel(line) {
  const trimmed = line.trim();
  if (trimmed.startsWith('- ')) {
    return trimmed.slice(2);
  }
  return trimmed;
}

function yamlToTreeHtml(content) {
  const lines = content.split(/\r?\n/).filter((line) => line.trim().length > 0);
  let html = '<ul class="tree">';
  let prevLevel = 0;

  for (let idx = 0; idx < lines.length; idx++) {
    const line = lines[idx];
    const level = getIndentLevel(line);
    const label = escapeHtml(lineToLabel(line));

    if (idx === 0) {
      prevLevel = level;
      html += `<li><span class="node">${label}</span>`;
      continue;
    }

    if (level > prevLevel) {
      for (let i = prevLevel; i < level; i++) {
        html += '<ul>';
      }
    } else if (level < prevLevel) {
      for (let i = level; i < prevLevel; i++) {
        html += '</li></ul>';
      }
      html += '</li>';
    } else {
      html += '</li>';
    }

    html += `<li><span class="node">${label}</span>`;
    prevLevel = level;
  }

  for (let i = 0; i < prevLevel; i++) {
    html += '</li></ul>';
  }
  html += '</li></ul>';
  return html;
}

function buildPage(title, sourcePath, treeHtml) {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escapeHtml(title)}</title>
  <style>
    :root {
      --bg: #f6f8fb;
      --panel: #ffffff;
      --text: #1e293b;
      --muted: #64748b;
      --line: #dbe3ef;
      --accent: #0f766e;
    }
    body {
      margin: 0;
      font-family: "Segoe UI", Tahoma, Arial, sans-serif;
      background: linear-gradient(180deg, #eef4ff 0%, var(--bg) 100%);
      color: var(--text);
    }
    .wrap {
      max-width: 1200px;
      margin: 24px auto;
      padding: 0 16px;
    }
    .card {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 12px;
      padding: 16px;
      box-shadow: 0 4px 14px rgba(15, 23, 42, 0.08);
    }
    h1 {
      margin: 0 0 8px 0;
      font-size: 1.2rem;
    }
    .meta {
      margin: 0 0 14px 0;
      color: var(--muted);
      font-size: 0.92rem;
      word-break: break-all;
    }
    .toolbar {
      display: flex;
      gap: 8px;
      margin-bottom: 12px;
    }
    input[type="search"] {
      flex: 1;
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 8px 10px;
      font-size: 0.95rem;
    }
    button {
      border: 1px solid var(--line);
      background: #ffffff;
      border-radius: 8px;
      padding: 8px 10px;
      cursor: pointer;
      color: var(--text);
    }
    button:hover {
      border-color: var(--accent);
    }
    .tree, .tree ul {
      list-style: none;
      margin: 0;
      padding-left: 18px;
    }
    .tree ul {
      border-left: 1px dashed var(--line);
      margin-left: 6px;
    }
    .tree li {
      margin: 4px 0;
    }
    .node {
      display: inline-block;
      background: #f8fafc;
      border: 1px solid #e6edf6;
      border-radius: 8px;
      padding: 5px 8px;
      font-size: 0.9rem;
      line-height: 1.35;
      word-break: break-word;
    }
    .hidden {
      display: none !important;
    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="card">
      <h1>Playwright CLI YAML Viewer</h1>
      <p class="meta">Source: ${escapeHtml(sourcePath)}</p>
      <div class="toolbar">
        <input id="q" type="search" placeholder="Filter nodes..." />
        <button id="expand" type="button">Expand All</button>
        <button id="collapse" type="button">Collapse All</button>
      </div>
      <div id="tree-root">
        ${treeHtml}
      </div>
    </div>
  </div>
  <script>
    const q = document.getElementById('q');
    const labels = Array.from(document.querySelectorAll('.node'));
    q.addEventListener('input', () => {
      const needle = q.value.trim().toLowerCase();
      for (const label of labels) {
        const li = label.closest('li');
        const hit = !needle || label.textContent.toLowerCase().includes(needle);
        li.classList.toggle('hidden', !hit);
      }
    });
    document.getElementById('expand').addEventListener('click', () => {
      document.querySelectorAll('ul').forEach((el) => el.classList.remove('hidden'));
    });
    document.getElementById('collapse').addEventListener('click', () => {
      document.querySelectorAll('.tree ul').forEach((el) => el.classList.add('hidden'));
    });
  </script>
</body>
</html>`;
}

function collectYamlFiles(targetPath) {
  const stat = fs.statSync(targetPath);
  if (stat.isFile()) {
    return [targetPath];
  }

  const out = [];
  const stack = [targetPath];
  while (stack.length) {
    const current = stack.pop();
    const entries = fs.readdirSync(current, { withFileTypes: true });
    for (const entry of entries) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) {
        stack.push(full);
      } else if (entry.isFile() && /\.(yml|yaml)$/i.test(entry.name)) {
        out.push(full);
      }
    }
  }
  return out.sort();
}

function writeIndex(outdir, generated) {
  const items = generated
    .map((g) => {
      const rel = path.relative(outdir, g.htmlPath).replaceAll('\\', '/');
      return `<li><a href="${escapeHtml(rel)}">${escapeHtml(path.basename(g.htmlPath))}</a><br /><small>${escapeHtml(g.sourcePath)}</small></li>`;
    })
    .join('\n');

  const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Playwright CLI YAML Dashboard</title>
  <style>
    body { font-family: "Segoe UI", Tahoma, Arial, sans-serif; background: #f4f7fb; color: #1e293b; margin: 0; }
    .wrap { max-width: 1000px; margin: 24px auto; padding: 0 16px; }
    .card { background: #fff; border: 1px solid #dbe3ef; border-radius: 12px; padding: 16px; }
    h1 { margin-top: 0; }
    ul { padding-left: 18px; }
    li { margin: 10px 0; }
    a { color: #0f766e; text-decoration: none; font-weight: 600; }
    a:hover { text-decoration: underline; }
    small { color: #64748b; }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="card">
      <h1>Playwright CLI YAML Dashboard</h1>
      <p>Generated files: ${generated.length}</p>
      <ul>${items}</ul>
    </div>
  </div>
</body>
</html>`;

  const indexPath = path.join(outdir, 'index.html');
  fs.writeFileSync(indexPath, html, 'utf8');
  return indexPath;
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function toSafeName(sourcePath) {
  return sourcePath.replace(/[:\\\/]+/g, '__');
}

function main() {
  const args = parseArgs(process.argv);
  if (!args.input) {
    usage();
    process.exit(1);
  }

  const inputPath = path.resolve(args.input);
  if (!fs.existsSync(inputPath)) {
    console.error(`Input path not found: ${inputPath}`);
    process.exit(1);
  }

  const yamlFiles = collectYamlFiles(inputPath);
  if (yamlFiles.length === 0) {
    console.error(`No .yml/.yaml files found under: ${inputPath}`);
    process.exit(1);
  }

  const outdir = args.outdir
    ? path.resolve(args.outdir)
    : fs.statSync(inputPath).isFile()
      ? path.dirname(inputPath)
      : inputPath;
  ensureDir(outdir);

  const generated = [];

  for (const filePath of yamlFiles) {
    const content = fs.readFileSync(filePath, 'utf8');
    const treeHtml = yamlToTreeHtml(content);
    const page = buildPage(path.basename(filePath), filePath, treeHtml);

    let htmlPath;
    if (fs.statSync(inputPath).isFile()) {
      htmlPath = path.join(outdir, `${path.basename(filePath)}.html`);
    } else {
      const relative = path.relative(inputPath, filePath);
      const safe = toSafeName(relative);
      htmlPath = path.join(outdir, `${safe}.html`);
    }

    fs.writeFileSync(htmlPath, page, 'utf8');
    generated.push({ sourcePath: filePath, htmlPath });
  }

  const indexPath = writeIndex(outdir, generated);
  console.log(`Generated ${generated.length} HTML file(s).`);
  console.log(`Dashboard: ${indexPath}`);
}

main();
