import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { chromium } from '@playwright/test';

function getArg(name, fallback) {
  const idx = process.argv.findIndex((arg) => arg === name);
  if (idx >= 0 && process.argv[idx + 1]) {
    return process.argv[idx + 1];
  }
  return fallback;
}

const cwd = process.cwd();
const imagesDirArg = getArg('--imagesDir', './output/trace-images');
const outputPathArg = getArg('--outputPath', './output/trace-images.pdf');

const imagesDir = path.resolve(cwd, imagesDirArg);
const outputPath = path.resolve(cwd, outputPathArg);
const outputDir = path.dirname(outputPath);

async function main() {
  const dirEntries = await fs.readdir(imagesDir, { withFileTypes: true });
  const images = dirEntries
    .filter((d) => d.isFile())
    .map((d) => d.name)
    .filter((name) => /\.(png|jpe?g|webp)$/i.test(name))
    .sort((a, b) => a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' }));

  if (images.length === 0) {
    throw new Error(`No images found in ${imagesDir}`);
  }

  await fs.mkdir(outputDir, { recursive: true });
  const tempHtmlPath = path.join(outputDir, `trace-images-${Date.now()}.html`);

  const imageBlocks = images
    .map((name, i) => {
      const imagePath = path.join(imagesDir, name);
      const imageUrl = pathToFileURL(imagePath).href;
      const pageBreakClass = i < images.length - 1 ? 'page-break' : '';
      return `
      <section class="sheet ${pageBreakClass}">
        <div class="caption">${name}</div>
        <img src="${imageUrl}" alt="${name}" />
      </section>`;
    })
    .join('\n');

  const html = `<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>Trace Images PDF</title>
    <style>
      @page { size: Letter; margin: 0.5in; }
      body { margin: 0; font-family: Arial, sans-serif; }
      .sheet {
        width: 100%;
        height: calc(11in - 1in);
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
      }
      .page-break { break-after: page; page-break-after: always; }
      .caption {
        font-size: 10pt;
        margin-bottom: 0.12in;
        color: #333;
      }
      img {
        max-width: 100%;
        max-height: calc(100% - 0.25in);
        object-fit: contain;
      }
    </style>
  </head>
  <body>
    ${imageBlocks}
  </body>
</html>`;

  await fs.writeFile(tempHtmlPath, html, 'utf8');

  const browser = await chromium.launch({ headless: true, channel: 'msedge' });
  try {
    const page = await browser.newPage();
    await page.goto(pathToFileURL(tempHtmlPath).href, { waitUntil: 'networkidle' });
    await page.pdf({
      path: outputPath,
      printBackground: true,
      format: 'Letter',
      margin: { top: '0.5in', right: '0.5in', bottom: '0.5in', left: '0.5in' }
    });
  } finally {
    await browser.close();
    await fs.unlink(tempHtmlPath).catch(() => {});
  }

  console.log(`Trace PDF written to ${outputPath}`);
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
