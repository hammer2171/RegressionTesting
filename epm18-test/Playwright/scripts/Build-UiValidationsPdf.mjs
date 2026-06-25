#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { chromium } from '@playwright/test';

function getArg(name, fallback = null) {
  const idx = process.argv.findIndex((arg) => arg === name);
  if (idx >= 0 && process.argv[idx + 1]) return process.argv[idx + 1];
  return fallback;
}

function parseBooleanArg(name, fallback = false) {
  const raw = getArg(name, null);
  if (raw === null || raw === undefined || raw === '') return fallback;
  const normalized = String(raw).trim().toLowerCase();
  if (['1', 'true', 'yes', 'on'].includes(normalized)) return true;
  if (['0', 'false', 'no', 'off'].includes(normalized)) return false;
  return fallback;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function normalizeSlashes(v) {
  return v.replaceAll('\\', '/');
}

async function fileExists(p) {
  try {
    await fs.access(p);
    return true;
  } catch {
    return false;
  }
}

async function listImages(imagesDir) {
  const entries = await fs.readdir(imagesDir, { withFileTypes: true });
  return entries
    .filter((e) => e.isFile())
    .map((e) => e.name)
    .filter((name) => /\.(png|jpe?g|webp)$/i.test(name))
    .sort((a, b) => a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' }))
    .map((name) => ({
      path: path.join(imagesDir, name),
      caption: name,
    }));
}

async function parseManifest(manifestPath, repoRoot) {
  const raw = await fs.readFile(manifestPath, 'utf8');
  const rows = raw.split(/\r?\n/);
  const items = [];

  for (const row of rows) {
    const line = row.trim();
    if (!line || line.startsWith('#')) continue;

    const parts = line.split('|');
    const imageRaw = parts[0]?.trim();
    if (!imageRaw) continue;

    const caption = parts[1]?.trim() || path.basename(imageRaw);
    const resolved = path.isAbsolute(imageRaw) ? imageRaw : path.resolve(repoRoot, imageRaw);
    items.push({ path: resolved, caption });
  }
  return items;
}

function buildHtml({ title, sections }) {
  const body = sections
    .map((s, i) => {
      const breakClass = i < sections.length - 1 ? 'page-break' : '';
      const content = s.missing
        ? `<div class="missing">Step Failed - No Image available. Need to retest.</div>`
        : `<img src="${escapeHtml(s.imageUrl)}" alt="${escapeHtml(s.caption)}" />`;
      return `
      <section class="sheet ${breakClass}">
        <h2>${escapeHtml(s.caption)}</h2>
        ${content}
        <p class="meta">${escapeHtml(normalizeSlashes(s.path))}</p>
      </section>`;
    })
    .join('\n');

  return `<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>${escapeHtml(title)}</title>
    <style>
      @page { size: Letter; margin: 0.5in; }
      body { margin: 0; font-family: "Segoe UI", Tahoma, Arial, sans-serif; color: #1f2937; }
      .sheet {
        width: 100%;
        height: calc(11in - 1in);
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: flex-start;
      }
      .page-break { break-after: page; page-break-after: always; }
      h2 {
        margin: 0 0 0.12in 0;
        font-size: 14pt;
        line-height: 1.2;
        text-align: center;
      }
      img {
        max-width: 100%;
        max-height: calc(100% - 1.2in);
        object-fit: contain;
        border: 1px solid #d1d5db;
      }
      .missing {
        width: 100%;
        min-height: 3in;
        display: flex;
        align-items: center;
        justify-content: center;
        text-align: center;
        border: 2px dashed #b91c1c;
        background: #fef2f2;
        color: #991b1b;
        font-size: 14pt;
        font-weight: 600;
        padding: 0.5in;
        box-sizing: border-box;
      }
      .meta {
        margin-top: 0.1in;
        font-size: 8.5pt;
        color: #6b7280;
        word-break: break-all;
      }
    </style>
  </head>
  <body>${body}
  </body>
</html>`;
}

async function main() {
  const cwd = process.cwd();
  const imagesDirArg = getArg('--imagesDir', './output/ui-validations');
  const manifestArg = getArg('--manifest', null);
  const outputPathArg = getArg('--outputPath', './output/test_ui_validations.pdf');
  const title = getArg('--title', 'Test UI Validations');
  const allowMissing = parseBooleanArg('--allow-missing', false);

  const imagesDir = path.resolve(cwd, imagesDirArg);
  const outputPath = path.resolve(cwd, outputPathArg);
  const outputDir = path.dirname(outputPath);
  const manifestPath = manifestArg ? path.resolve(cwd, manifestArg) : null;

  let selected = [];
  if (manifestPath) {
    if (!(await fileExists(manifestPath))) {
      throw new Error(`Manifest not found: ${manifestPath}`);
    }
    selected = await parseManifest(manifestPath, cwd);
  } else {
    if (!(await fileExists(imagesDir))) {
      throw new Error(`Images directory not found: ${imagesDir}`);
    }
    selected = await listImages(imagesDir);
  }

  if (selected.length === 0) {
    throw new Error('No images selected for PDF.');
  }

  await fs.mkdir(outputDir, { recursive: true });
  const htmlPath = path.join(outputDir, `ui-validations-${Date.now()}.html`);

  const sections = [];
  for (const item of selected) {
    const exists = await fileExists(item.path);
    if (!exists && !allowMissing) {
      throw new Error(`Image not found: ${item.path}`);
    }

    sections.push({
      path: item.path,
      caption: item.caption,
      imageUrl: exists ? pathToFileURL(item.path).href : null,
      missing: !exists,
    });
  }

  await fs.writeFile(htmlPath, buildHtml({ title, sections }), 'utf8');

  const browser = await chromium.launch({ headless: true, channel: 'msedge' });
  try {
    const page = await browser.newPage();
    await page.goto(pathToFileURL(htmlPath).href, { waitUntil: 'networkidle' });
    await page.pdf({
      path: outputPath,
      format: 'Letter',
      printBackground: true,
      margin: { top: '0.5in', right: '0.5in', bottom: '0.5in', left: '0.5in' },
    });
  } finally {
    await browser.close();
    await fs.unlink(htmlPath).catch(() => {});
  }

  console.log(`UI validation PDF written to ${outputPath}`);
  console.log(`Pages: ${selected.length}`);
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
