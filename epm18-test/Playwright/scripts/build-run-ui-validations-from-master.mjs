#!/usr/bin/env node
import { spawn } from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

function getArg(name, fallback = null) {
  const idx = process.argv.findIndex((arg) => arg === name);
  if (idx >= 0 && process.argv[idx + 1]) return process.argv[idx + 1];
  return fallback;
}

function ts() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}_${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
}

function normalizeSlashes(v) {
  return String(v).replaceAll('\\', '/');
}

function sanitizeLabel(label) {
  return String(label || '')
    .trim()
    .replace(/[^a-zA-Z0-9_-]/g, '_');
}

async function exists(p) {
  try {
    await fs.access(p);
    return true;
  } catch {
    return false;
  }
}

async function listFilesRecursive(rootDir) {
  const out = [];

  async function walk(current) {
    const entries = await fs.readdir(current, { withFileTypes: true });
    for (const entry of entries) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) {
        await walk(full);
      } else if (entry.isFile()) {
        out.push(full);
      }
    }
  }

  await walk(rootDir);
  return out;
}

function isImagePath(p) {
  return /\.(png|jpe?g|webp)$/i.test(p);
}

function splitLines(v) {
  return String(v || '')
    .split(/\r?\n/)
    .map((x) => x.trim())
    .filter(Boolean);
}

function parseManifest(raw) {
  const lines = raw.split(/\r?\n/);
  const items = [];
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i].trim();
    if (!line || line.startsWith('#')) continue;

    const parts = line.split('|');
    const imageHint = (parts[0] || '').trim();
    if (!imageHint) continue;
    const caption = parts.slice(1).join('|').trim() || path.basename(imageHint);
    items.push({
      lineNumber: i + 1,
      imageHint,
      caption,
    });
  }
  return items;
}

function parseJsonSafe(raw) {
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function toNumberSafe(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function parseBooleanEnv(name, fallback = false) {
  const raw = process.env[name];
  if (raw === undefined || raw === null || raw === '') return fallback;
  const normalized = String(raw).trim().toLowerCase();
  if (['1', 'true', 'yes', 'on'].includes(normalized)) return true;
  if (['0', 'false', 'no', 'off'].includes(normalized)) return false;
  return fallback;
}

function parseTraceImageTimestamp(fullPath) {
  const base = path.basename(fullPath);
  const m = base.match(/-(\d+)\.(png|jpe?g|webp)$/i);
  if (!m) return null;
  return Number(m[1]);
}

function pickEvenlySpaced(items, count) {
  if (!Array.isArray(items) || items.length === 0 || count <= 0) return [];
  if (count === 1) return [items[0]];
  if (items.length === 1) return Array.from({ length: count }, () => items[0]);

  const out = [];
  const maxIdx = items.length - 1;
  for (let i = 0; i < count; i += 1) {
    const ratio = i / (count - 1);
    const idx = Math.round(ratio * maxIdx);
    out.push(items[idx]);
  }
  return out;
}

function scoreSuffixMatch(candidateSegments, hintSegments) {
  const limit = Math.min(candidateSegments.length, hintSegments.length);
  let score = 0;
  for (let i = 1; i <= limit; i += 1) {
    if (candidateSegments[candidateSegments.length - i] !== hintSegments[hintSegments.length - i]) {
      break;
    }
    score += 1;
  }
  return score;
}

function chooseCandidateFromBasename(hint, candidates, runImagesRoot) {
  if (candidates.length === 1) {
    return {
      path: candidates[0],
      reason: 'basename-unique',
      ambiguous: false,
    };
  }

  const hintSegments = normalizeSlashes(hint).toLowerCase().split('/').filter(Boolean);
  const ranked = candidates
    .map((candidatePath) => {
      const rel = normalizeSlashes(path.relative(runImagesRoot, candidatePath)).toLowerCase();
      const relSegments = rel.split('/').filter(Boolean);
      return {
        path: candidatePath,
        score: scoreSuffixMatch(relSegments, hintSegments),
      };
    })
    .sort((a, b) => {
      if (b.score !== a.score) return b.score - a.score;
      return a.path.localeCompare(b.path);
    });

  const top = ranked[0];
  const tieCount = ranked.filter((x) => x.score === top.score).length;
  return {
    path: top.path,
    reason: tieCount > 1 ? 'basename-ambiguous-picked-best-suffix' : 'basename-best-suffix',
    ambiguous: tieCount > 1,
  };
}

function buildImageIndexes(runImagesRoot, runImages) {
  const byBasename = new Map();
  const byRelative = new Map();

  for (const fullPath of runImages) {
    const base = path.basename(fullPath).toLowerCase();
    const rel = normalizeSlashes(path.relative(runImagesRoot, fullPath)).toLowerCase();

    const bucket = byBasename.get(base) || [];
    bucket.push(fullPath);
    byBasename.set(base, bucket);

    byRelative.set(rel, fullPath);
  }

  return { byBasename, byRelative };
}

function resolveMasterItemToRunImage(item, runImagesRoot, indexes) {
  const hint = item.imageHint;
  const hintNorm = normalizeSlashes(hint).toLowerCase();

  // If a manifest hint already points to a test-results relative path, use it directly.
  let stripped = hintNorm;
  const testResultsMarker = 'test-results/';
  const markerIdx = hintNorm.lastIndexOf(testResultsMarker);
  if (markerIdx >= 0) {
    stripped = hintNorm.slice(markerIdx + testResultsMarker.length);
  }
  if (indexes.byRelative.has(stripped)) {
    return {
      path: indexes.byRelative.get(stripped),
      reason: 'relative-match',
      ambiguous: false,
    };
  }

  const base = path.basename(hintNorm);
  const baseCandidates = indexes.byBasename.get(base) || [];
  if (baseCandidates.length === 0) {
    return null;
  }
  return chooseCandidateFromBasename(hint, baseCandidates, runImagesRoot);
}

function resolveMasterItemWithFallback(item, primary, secondary = null) {
  const primaryResolved = resolveMasterItemToRunImage(item, primary.root, primary.indexes);
  if (primaryResolved) {
    return {
      ...primaryResolved,
      source: primary.name,
    };
  }

  if (!secondary) return null;
  const secondaryResolved = resolveMasterItemToRunImage(item, secondary.root, secondary.indexes);
  if (secondaryResolved) {
    return {
      ...secondaryResolved,
      source: secondary.name,
    };
  }
  return null;
}

function resolveRuleRunImage(item, rule, primary) {
  const ruleHint = rule?.imageHint || rule?.path || rule?.fileName || '';
  const lookupItem = ruleHint ? { ...item, imageHint: String(ruleHint) } : item;
  return resolveMasterItemToRunImage(lookupItem, primary.root, primary.indexes);
}

async function firstExistingPath(paths) {
  for (const candidate of paths) {
    if (candidate && await exists(candidate)) return candidate;
  }
  return null;
}

async function resolveReferenceImagePath(item, cwd, masterManifest) {
  const hint = item.imageHint;
  const candidates = [];

  if (path.isAbsolute(hint)) {
    candidates.push(hint);
  } else {
    candidates.push(path.resolve(cwd, hint));
    candidates.push(path.resolve(path.dirname(masterManifest), hint));
  }

  candidates.push(path.resolve(path.dirname(masterManifest), path.basename(hint)));
  return firstExistingPath(candidates);
}

async function buildVisualMatchRankings(items, {
  cwd,
  masterManifest,
  traceFrames,
}) {
  if (!Array.isArray(traceFrames) || traceFrames.length === 0) return new Map();

  const references = [];
  for (const item of items) {
    const referencePath = await resolveReferenceImagePath(item, cwd, masterManifest);
    if (!referencePath) continue;
    references.push({
      lineNumber: item.lineNumber,
      referencePath,
    });
  }

  if (references.length === 0) return new Map();

  const pythonCommand = process.env.PYTHON || 'python';
  const probe = await runCapture(pythonCommand, ['-c', 'import PIL']);
  if (probe.code !== 0) {
    throw new Error('Python Pillow is not available for visual trace matching.');
  }

  const compareScript = String.raw`
import json
import math
import sys
from PIL import Image

try:
    RESAMPLE = Image.Resampling.BILINEAR
except AttributeError:
    RESAMPLE = Image.BILINEAR

WIDTH = 64
HEIGHT = 48

def fingerprint(image_path):
    image = Image.open(image_path).convert("RGB").resize((WIDTH, HEIGHT), RESAMPLE).convert("L")
    pixels = list(image.getdata())
    mean = sum(pixels) / len(pixels)
    variance = sum((p - mean) * (p - mean) for p in pixels) / len(pixels)
    std = math.sqrt(variance)
    edges = []
    for y in range(HEIGHT):
        for x in range(WIDTH):
            idx = y * WIDTH + x
            right = pixels[idx + 1] if x + 1 < WIDTH else pixels[idx]
            down = pixels[idx + WIDTH] if y + 1 < HEIGHT else pixels[idx]
            edges.append(abs(pixels[idx] - right) + abs(pixels[idx] - down))
    return {"pixels": pixels, "edges": edges, "mean": mean, "std": std}

def score(reference, candidate):
    pixels = reference["pixels"]
    candidate_pixels = candidate["pixels"]
    edges = reference["edges"]
    candidate_edges = candidate["edges"]
    n = min(len(pixels), len(candidate_pixels))
    edge_n = min(len(edges), len(candidate_edges))
    if n == 0:
        return 999.0
    pixel_mse = sum((pixels[i] - candidate_pixels[i]) ** 2 for i in range(n)) / n
    edge_mse = sum((edges[i] - candidate_edges[i]) ** 2 for i in range(edge_n)) / edge_n if edge_n else 255 * 255
    pixel_rmse = math.sqrt(pixel_mse) / 255.0
    edge_rmse = math.sqrt(edge_mse) / 255.0
    mean_diff = abs(reference["mean"] - candidate["mean"]) / 255.0
    std_diff = abs(reference["std"] - candidate["std"]) / 255.0
    return (pixel_rmse * 0.68) + (edge_rmse * 0.22) + (mean_diff * 0.05) + (std_diff * 0.05)

with open(sys.argv[1], "r", encoding="utf-8") as f:
    request = json.load(f)

candidate_fingerprints = []
for candidate in request["candidates"]:
    try:
        candidate_fingerprints.append({
            "path": candidate["path"],
            "timestamp": candidate.get("timestamp"),
            "fingerprint": fingerprint(candidate["path"])
        })
    except Exception:
        pass

out = []
for reference in request["references"]:
    try:
        reference_fingerprint = fingerprint(reference["referencePath"])
    except Exception:
        continue
    ranked = []
    for candidate in candidate_fingerprints:
        ranked.append({
            "path": candidate["path"],
            "timestamp": candidate["timestamp"],
            "score": score(reference_fingerprint, candidate["fingerprint"])
        })
    ranked.sort(key=lambda row: (row["score"], row["timestamp"] if row["timestamp"] is not None else 9999999999999))
    out.append({
        "lineNumber": reference["lineNumber"],
        "referencePath": reference["referencePath"],
        "ranked": ranked
    })

print(json.dumps({"references": out}))
`;

  const requestPath = path.join(
    os.tmpdir(),
    `ui-validation-match-all-${process.pid}-${Date.now()}-${Math.round(Math.random() * 1_000_000)}.json`
  );
  const request = {
    references,
    candidates: traceFrames.map((candidate) => ({
      path: candidate.path,
      timestamp: toNumberSafe(candidate.timestamp),
    })),
  };

  await fs.writeFile(requestPath, JSON.stringify(request), 'utf8');
  const result = await runCapture(pythonCommand, ['-c', compareScript, requestPath]);
  await fs.rm(requestPath, { force: true }).catch(() => {});
  if (result.code !== 0) {
    const details = (result.stderr || result.stdout || '').trim();
    throw new Error(`Python visual compare failed: ${details}`);
  }

  const parsed = parseJsonSafe(result.stdout);
  const rankings = new Map();
  for (const row of parsed?.references || []) {
    rankings.set(row.lineNumber, {
      referencePath: row.referencePath,
      ranked: (row.ranked || []).map((entry) => ({
        path: entry.path,
        timestamp: toNumberSafe(entry.timestamp),
        score: toNumberSafe(entry.score),
      })),
    });
  }
  return rankings;
}

async function pickTraceFrameByVisualMatch(item, {
  rankings,
  state,
  maxScore,
}) {
  const ranking = rankings?.get(item.lineNumber);
  if (!ranking || !Array.isArray(ranking.ranked) || ranking.ranked.length === 0) return null;

  const notBefore = toNumberSafe(state.lastTraceTimestamp);
  const chronologicalRanked =
    notBefore === null
      ? ranking.ranked
      : ranking.ranked.filter((f) => toNumberSafe(f.timestamp) !== null && f.timestamp >= notBefore);
  const selectedTraceImagePaths = state.selectedTraceImagePaths || new Set();
  const isUnusedTraceImage = (frame) =>
    frame?.path && !selectedTraceImagePaths.has(normalizeSlashes(path.resolve(frame.path)).toLowerCase());
  const unusedChronologicalRanked = chronologicalRanked.filter(isUnusedTraceImage);
  const unusedRanked = ranking.ranked.filter(isUnusedTraceImage);
  const pool =
    unusedChronologicalRanked.length > 0
      ? unusedChronologicalRanked
      : unusedRanked.length > 0
        ? unusedRanked
        : chronologicalRanked.length > 0
          ? chronologicalRanked
          : ranking.ranked;
  const best = pool[0] || null;
  const second = pool[1] || null;
  if (!best) {
    return {
      referencePath: ranking.referencePath,
      matched: false,
      reason: 'trace-visual-no-candidates',
    };
  }

  const accepted = best.score <= maxScore;
  return {
    ...best,
    referencePath: ranking.referencePath,
    matched: accepted,
    reason: accepted ? 'trace-visual-match' : 'trace-visual-low-confidence',
    secondScore: second?.score ?? null,
  };
}

function findDuplicateSelectedImages(selected) {
  const byPath = new Map();
  for (const entry of selected) {
    if (!entry?.path) continue;
    const key = normalizeSlashes(path.resolve(entry.path)).toLowerCase();
    const bucket = byPath.get(key) || [];
    bucket.push(entry);
    byPath.set(key, bucket);
  }

  return Array.from(byPath.entries())
    .filter(([, entries]) => entries.length > 1)
    .map(([imagePath, entries]) => ({
      imagePath,
      entries: entries.map((entry) => ({
        lineNumber: entry.lineNumber,
        caption: entry.caption,
        reason: entry.reason,
        imageHint: entry.imageHint,
        referencePath: entry.referencePath,
        visualScore: entry.visualScore,
        secondVisualScore: entry.secondVisualScore,
      })),
    }));
}

async function removeStaleRunPdfs(runLabelDir, label) {
  const prefix = `ui_vals_${label}_`;
  const entries = await fs.readdir(runLabelDir, { withFileTypes: true }).catch(() => []);
  await Promise.all(
    entries
      .filter((entry) => entry.isFile() && entry.name.startsWith(prefix) && entry.name.endsWith('.pdf'))
      .map((entry) => fs.rm(path.join(runLabelDir, entry.name), { force: true }).catch(() => {}))
  );
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

function runCapture(command, args) {
  return new Promise((resolve) => {
    const child = spawn(command, args, {
      stdio: ['ignore', 'pipe', 'pipe'],
      shell: false,
      windowsHide: false,
    });

    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });

    child.on('close', (code) => resolve({ code: code ?? 1, stdout, stderr }));
    child.on('error', (err) => resolve({ code: 1, stdout, stderr: String(err) }));
  });
}

function traceEventToWallTime(eventTime, context) {
  if (eventTime === null || eventTime === undefined) return null;
  const contextWall = toNumberSafe(context?.wallTime);
  const contextMono = toNumberSafe(context?.monotonicTime);
  const eventMono = toNumberSafe(eventTime);
  if (contextWall === null || contextMono === null || eventMono === null) return null;
  return Math.round(contextWall + (eventMono - contextMono));
}

function parseTraceEventsNdjson(raw) {
  const lines = splitLines(raw);
  const parsed = [];
  for (const line of lines) {
    const row = parseJsonSafe(line);
    if (!row || typeof row !== 'object') continue;
    parsed.push(row);
  }
  if (parsed.length === 0) return [];

  const context = parsed.find((row) => row.type === 'context-options') || {};
  const beforeByCallId = new Map();
  const spans = [];

  for (const row of parsed) {
    if (row.type === 'before' && row.callId) {
      beforeByCallId.set(row.callId, row);
      continue;
    }
    if (row.type !== 'after' || !row.callId) continue;
    const before = beforeByCallId.get(row.callId);
    if (!before) continue;

    const startWall = traceEventToWallTime(before.startTime, context);
    const endWall = traceEventToWallTime(row.endTime, context);
    spans.push({
      callId: row.callId,
      className: before.class || '',
      method: before.method || '',
      title: before.title || row.title || '',
      startTimeMono: toNumberSafe(before.startTime),
      endTimeMono: toNumberSafe(row.endTime),
      startWall,
      endWall,
    });
  }

  spans.sort((a, b) => {
    const aTime = a.startWall ?? Number.MAX_SAFE_INTEGER;
    const bTime = b.startWall ?? Number.MAX_SAFE_INTEGER;
    return aTime - bTime;
  });
  return spans;
}

async function collectTraceEvents(runRoot) {
  const testResultsRoot = path.join(runRoot, 'test-results');
  if (!(await exists(testResultsRoot))) return [];

  const allFiles = await listFilesRecursive(testResultsRoot);
  const traceZips = allFiles.filter((f) => path.basename(f).toLowerCase() === 'trace.zip');
  if (traceZips.length === 0) return [];

  const allSpans = [];
  for (const zip of traceZips) {
    const rawPrimary = await runCapture('tar', ['-xOf', zip, 'test.trace']);
    let raw = rawPrimary.code === 0 ? rawPrimary.stdout : '';
    if (!raw) {
      const rawFallback = await runCapture('tar', ['-xOf', zip, '0-trace.trace']);
      raw = rawFallback.code === 0 ? rawFallback.stdout : '';
    }
    if (!raw) continue;
    const spans = parseTraceEventsNdjson(raw);
    for (const s of spans) allSpans.push(s);
  }

  allSpans.sort((a, b) => {
    const aTime = a.startWall ?? Number.MAX_SAFE_INTEGER;
    const bTime = b.startWall ?? Number.MAX_SAFE_INTEGER;
    return aTime - bTime;
  });
  return allSpans;
}

function normalizeRule(rule) {
  if (!rule || typeof rule !== 'object') return null;
  return {
    ...rule,
    source: String(rule.source || '').trim().toLowerCase(),
    pick: String(rule.pick || 'nearest').trim().toLowerCase(),
    offsetMs: toNumberSafe(rule.offsetMs) ?? 0,
    percent: toNumberSafe(rule.percent),
  };
}

async function readStepRules(stepRulesPath) {
  if (!(await exists(stepRulesPath))) return null;
  const raw = await fs.readFile(stepRulesPath, 'utf8');
  const parsed = parseJsonSafe(raw);
  if (!parsed || typeof parsed !== 'object') return null;
  const steps = Array.isArray(parsed.steps) ? parsed.steps.map(normalizeRule).filter(Boolean) : [];
  return {
    path: stepRulesPath,
    steps,
    raw: parsed,
  };
}

function findStepRule(stepRules, item, idx) {
  if (!stepRules || !Array.isArray(stepRules.steps) || stepRules.steps.length === 0) return null;
  for (const r of stepRules.steps) {
    if (toNumberSafe(r.line) === item.lineNumber) return r;
  }
  for (const r of stepRules.steps) {
    if (toNumberSafe(r.index) === idx + 1) return r;
  }
  const captionNorm = String(item.caption || '').toLowerCase();
  for (const r of stepRules.steps) {
    if (!r.captionContains) continue;
    if (captionNorm.includes(String(r.captionContains).toLowerCase())) return r;
  }
  return null;
}

function matchesAnchor(span, anchor) {
  if (!anchor || typeof anchor !== 'object') return true;
  if (anchor.titleIncludes) {
    const needle = String(anchor.titleIncludes).toLowerCase();
    if (!String(span.title || '').toLowerCase().includes(needle)) return false;
  }
  if (anchor.method) {
    if (String(span.method || '').toLowerCase() !== String(anchor.method).toLowerCase()) return false;
  }
  if (anchor.className) {
    if (String(span.className || '').toLowerCase() !== String(anchor.className).toLowerCase()) return false;
  }
  if (anchor.callIdIncludes) {
    const needle = String(anchor.callIdIncludes).toLowerCase();
    if (!String(span.callId || '').toLowerCase().includes(needle)) return false;
  }
  return true;
}

function pickAnchorEvent(traceSpans, anchor) {
  const matches = traceSpans.filter((s) => matchesAnchor(s, anchor));
  if (matches.length === 0) return null;

  const occurrenceFromEnd = toNumberSafe(anchor?.occurrenceFromEnd);
  if (occurrenceFromEnd && occurrenceFromEnd > 0) {
    return matches[Math.max(0, matches.length - occurrenceFromEnd)] || null;
  }
  const occurrence = Math.max(1, toNumberSafe(anchor?.occurrence) || 1);
  return matches[Math.min(matches.length - 1, occurrence - 1)] || null;
}

function pickByTimestamp(candidates, targetTs, pickMode) {
  if (!Array.isArray(candidates) || candidates.length === 0) return null;
  const mode = String(pickMode || 'nearest').toLowerCase();
  const ts = toNumberSafe(targetTs);
  if (ts === null) return null;

  const withTs = candidates.filter((x) => toNumberSafe(x.timestamp) !== null);
  if (withTs.length === 0) return null;

  if (mode === 'before') {
    const eligible = withTs.filter((x) => x.timestamp <= ts);
    if (eligible.length === 0) return null;
    eligible.sort((a, b) => b.timestamp - a.timestamp);
    return eligible[0];
  }

  if (mode === 'after') {
    const eligible = withTs.filter((x) => x.timestamp >= ts);
    if (eligible.length === 0) return null;
    eligible.sort((a, b) => a.timestamp - b.timestamp);
    return eligible[0];
  }

  withTs.sort((a, b) => Math.abs(a.timestamp - ts) - Math.abs(b.timestamp - ts));
  return withTs[0];
}

function pickVideoFrameByRule(videoFrames, rule, state) {
  if (!Array.isArray(videoFrames) || videoFrames.length === 0) return null;
  const ordered = [...videoFrames].sort((a, b) => (a.index ?? 0) - (b.index ?? 0));
  const notBeforeIndex = Math.max(0, state.lastVideoIndex ?? 0);
  const available = ordered.filter((f) => (f.index ?? 0) >= notBeforeIndex);
  const pool = available.length > 0 ? available : ordered;

  if (rule?.position === 'last') return pool[pool.length - 1] || null;
  if (rule?.position === 'first') return pool[0] || null;

  const exactIndex = toNumberSafe(rule?.index);
  if (exactIndex !== null) {
    const idx = Math.min(Math.max(0, exactIndex - 1), pool.length - 1);
    return pool[idx] || null;
  }

  const percent = toNumberSafe(rule?.percent);
  if (percent !== null) {
    const bounded = Math.max(0, Math.min(1, percent));
    const idx = Math.round(bounded * (pool.length - 1));
    return pool[idx] || null;
  }

  return pool[Math.round((pool.length - 1) * 0.95)] || pool[pool.length - 1] || null;
}

function pickTraceFrameByRule(traceFrames, traceSpans, rule, state) {
  if (!Array.isArray(traceFrames) || traceFrames.length === 0) return null;
  const anchor = pickAnchorEvent(traceSpans, rule.anchor || {});
  if (!anchor) return null;

  const anchorPoint = String(rule.anchor?.time || 'end').toLowerCase();
  const anchorTs = anchorPoint === 'start' ? anchor.startWall : anchor.endWall;
  if (anchorTs === null || anchorTs === undefined) return null;

  const targetTs = anchorTs + (toNumberSafe(rule.offsetMs) ?? 0);
  const notBefore = toNumberSafe(state.lastTraceTimestamp);
  const chronologicalPool =
    notBefore === null
      ? traceFrames
      : traceFrames.filter((f) => toNumberSafe(f.timestamp) !== null && f.timestamp >= notBefore);

  const pool = chronologicalPool.length > 0 ? chronologicalPool : traceFrames;
  return pickByTimestamp(pool, targetTs, rule.pick || 'nearest');
}

function formatFpsArg(fps) {
  const safe = Math.max(0.2, toNumberSafe(fps) ?? 2);
  return String(Number(safe.toFixed(6)));
}

async function extractVideoFrames(videoPath, outputDir, fps) {
  await fs.mkdir(outputDir, { recursive: true });
  const outputPattern = path.join(outputDir, 'frame-%04d.png');
  const ffmpegArgs = [
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-i',
    videoPath,
    '-vf',
    `fps=${formatFpsArg(fps)}`,
    outputPattern,
  ];

  const result = await runCapture('ffmpeg', ffmpegArgs);
  if (result.code !== 0) {
    const details = (result.stderr || result.stdout || '').trim();
    throw new Error(`ffmpeg failed (${result.code}) ${details}`.trim());
  }

  const images = (await listFilesRecursive(outputDir)).filter(isImagePath).sort((a, b) =>
    a.localeCompare(b)
  );
  const safeFps = Math.max(0.2, toNumberSafe(fps) ?? 2);
  return images.map((imgPath, idx) => ({
    path: imgPath,
    index: idx,
    timestampMs: Math.round((idx * 1000) / safeFps),
  }));
}

async function collectVideoFrames(runRoot, label) {
  const testResultsRoot = path.join(runRoot, 'test-results');
  if (!(await exists(testResultsRoot))) return [];

  const allFiles = await listFilesRecursive(testResultsRoot);
  const videos = allFiles.filter((f) => path.basename(f).toLowerCase() === 'video.webm');
  if (videos.length === 0) return [];

  const frameRoot = path.join(runRoot, 'output', 'ui-validations', label, 'video-frames');
  await fs.rm(frameRoot, { recursive: true, force: true }).catch(() => {});
  await fs.mkdir(frameRoot, { recursive: true });

  const frameStepMs = toNumberSafe(process.env.UI_VALIDATION_VIDEO_FRAME_MS);
  const fpsFromEnv = toNumberSafe(process.env.UI_VALIDATION_VIDEO_FPS);
  const captureFps = fpsFromEnv ?? (frameStepMs ? 1000 / Math.max(1, frameStepMs) : 2);
  const collected = [];
  for (let i = 0; i < videos.length; i += 1) {
    const videoPath = videos[i];
    const outDir = path.join(frameRoot, `video-${String(i + 1).padStart(2, '0')}`);
    try {
      const frames = await extractVideoFrames(videoPath, outDir, captureFps);
      for (const frame of frames) collected.push(frame);
    } catch (err) {
      const message = err?.message || String(err);
      console.log(`[run-ui-validations] Video extraction failed: ${message}`);
    }
  }
  return collected;
}

async function collectTraceSnapshotImages(runRoot, label) {
  const testResultsRoot = path.join(runRoot, 'test-results');
  if (!(await exists(testResultsRoot))) return [];

  const allFiles = await listFilesRecursive(testResultsRoot);
  const traceZips = allFiles.filter((f) => path.basename(f).toLowerCase() === 'trace.zip');
  if (traceZips.length === 0) return [];

  const traceImagesRoot = path.join(runRoot, 'output', 'ui-validations', label, 'trace-images');
  await fs.rm(traceImagesRoot, { recursive: true, force: true }).catch(() => {});
  await fs.mkdir(traceImagesRoot, { recursive: true });

  for (let i = 0; i < traceZips.length; i += 1) {
    const zip = traceZips[i];
    const listResult = await runCapture('tar', ['-tf', zip]);
    if (listResult.code !== 0) continue;

    const entries = splitLines(listResult.stdout);
    let snapshotEntries = entries.filter((e) => /^resources\/page@.+\.(png|jpe?g|webp)$/i.test(e));

    if (snapshotEntries.length === 0) {
      snapshotEntries = entries.filter((e) => /^resources\/.+\.(png|jpe?g|webp)$/i.test(e));
    }
    if (snapshotEntries.length === 0) continue;

    const outDir = path.join(traceImagesRoot, `tracezip-${String(i + 1).padStart(2, '0')}`);
    await fs.mkdir(outDir, { recursive: true });

    const chunkSize = 120;
    for (let start = 0; start < snapshotEntries.length; start += chunkSize) {
      const chunk = snapshotEntries.slice(start, start + chunkSize);
      const extractArgs = ['-xf', zip, '-C', outDir, ...chunk];
      await runCapture('tar', extractArgs);
    }
  }

  const extracted = (await listFilesRecursive(traceImagesRoot)).filter(isImagePath).sort((a, b) =>
    a.localeCompare(b)
  );
  return extracted;
}

async function main() {
  const cwd = process.cwd();

  const labelRaw = getArg('--label', process.env.EVIDENCE_LABEL || '');
  const label = sanitizeLabel(labelRaw);
  if (!label) {
    console.log('[run-ui-validations] Skipping: label is empty.');
    return;
  }

  const runRootArg = (getArg('--run-root', '') || '').trim();
  if (!runRootArg) {
    console.log('[run-ui-validations] Skipping: --run-root is required.');
    return;
  }
  const runRoot = path.isAbsolute(runRootArg) ? runRootArg : path.resolve(cwd, runRootArg);

  const runImagesRoot = path.join(runRoot, 'test-results');
  if (!(await exists(runImagesRoot))) {
    console.log(`[run-ui-validations] Skipping: run test-results folder not found at ${runImagesRoot}`);
    return;
  }

  const allRunFiles = await listFilesRecursive(runImagesRoot);
  const runImages = allRunFiles.filter(isImagePath).sort((a, b) => a.localeCompare(b));
  if (runImages.length === 0) {
    console.log('[run-ui-validations] Skipping: no run images found in test-results.');
    return;
  }

  const masterManifestArg = (getArg('--master-manifest', '') || '').trim();
  const masterRootArg = (getArg('--master-root', path.join('output', 'ui-validations')) || '').trim();
  const masterManifest = masterManifestArg
    ? (path.isAbsolute(masterManifestArg) ? masterManifestArg : path.resolve(cwd, masterManifestArg))
    : path.resolve(cwd, masterRootArg, label, 'selection.txt');

  if (!(await exists(masterManifest))) {
    // First-time run for a new label: generate a run-local draft only, keeping
    // curated baseline folders under output/ui-validations human-controlled.
    const seedLines = [
      '# Draft selection list from this run.',
      '# You and Aigul should curate this file, then save final list as selection.txt',
      '# Format: path|caption',
      '# Paths below point to run test-results structure for remapping in future runs.',
      '',
      ...runImages.map((img) => {
        const relFromRunRoot = normalizeSlashes(path.relative(runRoot, img));
        return `${relFromRunRoot}|${path.basename(img)}`;
      }),
    ];

    const runDraftDir = path.join(runRoot, 'output', 'ui-validations', label);
    await fs.mkdir(runDraftDir, { recursive: true });
    const runDraftManifest = path.join(runDraftDir, 'selection.draft.from-run.txt');
    await fs.writeFile(runDraftManifest, seedLines.join('\n'), 'utf8');

    console.log(`[run-ui-validations] Master selection.txt not found for label "${label}".`);
    console.log(`[run-ui-validations] Run-local draft created at: ${runDraftManifest}`);
    console.log('[run-ui-validations] Skipping final run-level PDF until curated selection.txt exists.');
    return;
  }

  const rawManifest = await fs.readFile(masterManifest, 'utf8');
  const masterItems = parseManifest(rawManifest);
  if (masterItems.length === 0) {
    console.log('[run-ui-validations] Skipping: master manifest has no selection entries.');
    return;
  }

  const runLabelDir = path.join(runRoot, 'output', 'ui-validations', label);
  await fs.mkdir(runLabelDir, { recursive: true });
  await fs.rm(path.join(runLabelDir, 'ui-validation-duplicate-images.json'), { force: true }).catch(() => {});
  await removeStaleRunPdfs(runLabelDir, label);

  const traceImages = await collectTraceSnapshotImages(runRoot, label);
  const traceFrames = traceImages
    .map((p) => ({
      path: p,
      timestamp: parseTraceImageTimestamp(p),
    }))
    .filter((x) => toNumberSafe(x.timestamp) !== null)
    .sort((a, b) => a.timestamp - b.timestamp);
  const traceSpans = await collectTraceEvents(runRoot);

  const stepRulesArg = (getArg('--step-rules', '') || '').trim();
  const stepRulesPath = stepRulesArg
    ? path.resolve(cwd, stepRulesArg)
    : path.join(path.dirname(masterManifest), 'step-rules.json');
  const stepRules = await readStepRules(stepRulesPath);

  const requiresVideoFrames = Boolean(
    stepRules &&
      Array.isArray(stepRules.steps) &&
      stepRules.steps.some((s) => String(s.source || '').toLowerCase() === 'video-frames')
  );
  const videoFrames = requiresVideoFrames ? await collectVideoFrames(runRoot, label) : [];

  const primarySource = {
    name: 'test-results',
    root: runImagesRoot,
    indexes: buildImageIndexes(runImagesRoot, runImages),
  };
  const secondarySource =
    traceImages.length > 0
      ? {
          name: 'trace-images',
          root: path.join(runRoot, 'output', 'ui-validations', label, 'trace-images'),
          indexes: buildImageIndexes(path.join(runRoot, 'output', 'ui-validations', label, 'trace-images'), traceImages),
        }
      : null;
  const sampledTraceByStep = pickEvenlySpaced(traceImages, masterItems.length);
  const visualMatchEnabled = parseBooleanEnv('UI_VALIDATION_TRACE_VISUAL_MATCH', true);
  const visualMatchMaxScore = toNumberSafe(process.env.UI_VALIDATION_VISUAL_MATCH_MAX_SCORE) ?? 0.23;
  let visualRankings = new Map();
  if (visualMatchEnabled && traceFrames.length > 0) {
    try {
      visualRankings = await buildVisualMatchRankings(masterItems, {
        cwd,
        masterManifest,
        traceFrames,
      });
    } catch (err) {
      console.log(`[run-ui-validations] Visual trace matcher unavailable: ${err?.message || err}`);
    }
  }

  const runImageDirs = Array.from(new Set(runImages.map((img) => path.dirname(img)))).sort((a, b) =>
    a.localeCompare(b)
  );
  const primaryRunImageDir = runImageDirs[0] || runImagesRoot;
  const selected = [];
  const missing = [];
  const ambiguous = [];
  const selectionState = {
    lastTraceTimestamp: null,
    lastVideoIndex: null,
    selectedTraceImagePaths: new Set(),
  };

  for (let idx = 0; idx < masterItems.length; idx += 1) {
    const item = masterItems[idx];

    const matchedRule = findStepRule(stepRules, item, idx);
    if (matchedRule) {
      const source = String(matchedRule.source || 'trace-images').toLowerCase();
      if (['test-results', 'run-images', 'screenshots'].includes(source)) {
        const chosenRunImage = resolveRuleRunImage(item, matchedRule, primarySource);
        if (chosenRunImage?.path) {
          selected.push({
            path: chosenRunImage.path,
            caption: item.caption,
            lineNumber: item.lineNumber,
            imageHint: item.imageHint,
            reason: `step-rule:${source}`,
          });
        } else {
          const missingExpectedPath = path.join(primaryRunImageDir, path.basename(matchedRule.imageHint || item.imageHint));
          missing.push({
            ...item,
            expectedRunPath: missingExpectedPath,
          });
          selected.push({
            path: missingExpectedPath,
            caption: item.caption,
            lineNumber: item.lineNumber,
            imageHint: item.imageHint,
            reason: `missing-step-rule:${source}`,
          });
        }
        continue;
      }

      if (source === 'video-frames') {
        const chosenVideo = pickVideoFrameByRule(videoFrames, matchedRule, selectionState);
        if (chosenVideo?.path) {
          selected.push({
            path: chosenVideo.path,
            caption: item.caption,
            lineNumber: item.lineNumber,
            imageHint: item.imageHint,
            reason: `step-rule:video-frames`,
          });
          selectionState.lastVideoIndex = toNumberSafe(chosenVideo.index) ?? selectionState.lastVideoIndex;
          continue;
        }
      } else {
        const chosenTrace = pickTraceFrameByRule(traceFrames, traceSpans, matchedRule, selectionState);
        if (chosenTrace?.path) {
          selected.push({
            path: chosenTrace.path,
            caption: item.caption,
            lineNumber: item.lineNumber,
            imageHint: item.imageHint,
            reason: `step-rule:trace-images`,
          });
          selectionState.lastTraceTimestamp =
            toNumberSafe(chosenTrace.timestamp) ?? selectionState.lastTraceTimestamp;
          continue;
        }
      }
    }

    const hintBase = path.basename(item.imageHint).toLowerCase();
    const normalizedHint = normalizeSlashes(item.imageHint).toLowerCase();
    const looksLikeMasterPlaceholder =
      /^test-finished-\d+\.(png|jpe?g|webp)$/i.test(hintBase) &&
      (normalizedHint.includes('/output/ui-validations/') || normalizedHint.startsWith('output/ui-validations/'));
    if (!looksLikeMasterPlaceholder) {
      const resolved = resolveMasterItemWithFallback(item, primarySource, secondarySource);
      if (resolved) {
        if (resolved.ambiguous) {
          ambiguous.push({
            lineNumber: item.lineNumber,
            imageHint: item.imageHint,
            chosenPath: resolved.path,
          });
        }
        selected.push({
          path: resolved.path,
          caption: item.caption,
          lineNumber: item.lineNumber,
          imageHint: item.imageHint,
          reason: `${resolved.reason}:${resolved.source}`,
        });
        continue;
      }
    }

    const visualTraceCandidate = await pickTraceFrameByVisualMatch(item, {
      rankings: visualRankings,
      state: selectionState,
      maxScore: visualMatchMaxScore,
    });
    if (visualTraceCandidate?.matched) {
      selected.push({
        path: visualTraceCandidate.path,
        caption: item.caption,
        lineNumber: item.lineNumber,
        imageHint: item.imageHint,
        reason: visualTraceCandidate.reason,
        referencePath: visualTraceCandidate.referencePath,
        visualScore: Number(visualTraceCandidate.score.toFixed(6)),
        secondVisualScore:
          visualTraceCandidate.secondScore === null
            ? null
            : Number(visualTraceCandidate.secondScore.toFixed(6)),
      });
      selectionState.lastTraceTimestamp =
        toNumberSafe(visualTraceCandidate.timestamp) ?? selectionState.lastTraceTimestamp;
      selectionState.selectedTraceImagePaths.add(
        normalizeSlashes(path.resolve(visualTraceCandidate.path)).toLowerCase(),
      );
      continue;
    }
    if (visualTraceCandidate?.referencePath && looksLikeMasterPlaceholder) {
      const missingExpectedPath = path.join(primaryRunImageDir, path.basename(item.imageHint));
      missing.push({
        ...item,
        expectedRunPath: missingExpectedPath,
        referencePath: visualTraceCandidate.referencePath,
        visualScore:
          visualTraceCandidate.score === undefined ? null : Number(visualTraceCandidate.score.toFixed(6)),
        maxScore: visualMatchMaxScore,
      });
      selected.push({
        path: missingExpectedPath,
        caption: item.caption,
        lineNumber: item.lineNumber,
        imageHint: item.imageHint,
        reason: visualTraceCandidate.reason,
        referencePath: visualTraceCandidate.referencePath,
        visualScore:
          visualTraceCandidate.score === undefined ? null : Number(visualTraceCandidate.score.toFixed(6)),
      });
      continue;
    }

    const chronologicalTracePool =
      selectionState.lastTraceTimestamp === null
        ? traceFrames
        : traceFrames.filter((f) => f.timestamp >= selectionState.lastTraceTimestamp);
    const traceCandidate = chronologicalTracePool[0] || null;
    if (traceCandidate?.path) {
      selected.push({
        path: traceCandidate.path,
        caption: item.caption,
        lineNumber: item.lineNumber,
        imageHint: item.imageHint,
        reason: 'trace-chronological-fallback',
      });
      selectionState.lastTraceTimestamp = traceCandidate.timestamp;
      continue;
    }

    const resolved = resolveMasterItemWithFallback(item, primarySource, secondarySource);
    if (resolved) {
      if (resolved.ambiguous) {
        ambiguous.push({
          lineNumber: item.lineNumber,
          imageHint: item.imageHint,
          chosenPath: resolved.path,
        });
      }
      selected.push({
        path: resolved.path,
        caption: item.caption,
        lineNumber: item.lineNumber,
        imageHint: item.imageHint,
        reason: `${resolved.reason}:${resolved.source}`,
      });
      continue;
    }

    const sampledTrace = sampledTraceByStep[idx] || null;
    if (sampledTrace) {
      selected.push({
        path: sampledTrace,
        caption: item.caption,
        lineNumber: item.lineNumber,
        imageHint: item.imageHint,
        reason: 'trace-sampled-by-step',
      });
      continue;
    }

    const missingExpectedPath = path.join(primaryRunImageDir, path.basename(item.imageHint));
    missing.push({
      ...item,
      expectedRunPath: missingExpectedPath,
    });

    selected.push({
      path: missingExpectedPath,
      caption: item.caption,
      lineNumber: item.lineNumber,
      imageHint: item.imageHint,
      reason: 'missing-run-image-placeholder',
    });
  }

  if (selected.length === 0) {
    console.log('[run-ui-validations] Skipping: no run images matched master manifest entries.');
    return;
  }

  const duplicateSelections = findDuplicateSelectedImages(selected);
  if (duplicateSelections.length > 0) {
    const duplicateSummaryPath = path.join(runLabelDir, 'ui-validation-duplicate-images.json');
    await fs.writeFile(
      duplicateSummaryPath,
      JSON.stringify(
        {
          runRoot,
          label,
          masterManifest,
          duplicateCount: duplicateSelections.length,
          duplicates: duplicateSelections,
        },
        null,
        2
      ),
      'utf8'
    );
    console.log(
      '[run-ui-validations] Refusing to build dated PDF: multiple slides resolved to the same image.'
    );
    console.log(`[run-ui-validations] Duplicate summary: ${duplicateSummaryPath}`);
    process.exitCode = 1;
    return;
  }

  const generatedManifestPath = path.join(runLabelDir, 'selection.generated.from-master.txt');
  const generatedLines = [];
  generatedLines.push(`# Auto-generated from master manifest: ${masterManifest}`);
  generatedLines.push(`# Generated at: ${new Date().toISOString()}`);
  generatedLines.push('# Format: imagePath|caption');
  generatedLines.push('');
  for (const entry of selected) {
    generatedLines.push(`${entry.path}|${entry.caption}`);
  }
  if (missing.length > 0 || ambiguous.length > 0) {
    generatedLines.push('');
    generatedLines.push('# Notes');
    for (const item of missing) {
      generatedLines.push(`# MISSING line ${item.lineNumber}: ${item.imageHint}`);
    }
    for (const item of ambiguous) {
      generatedLines.push(`# AMBIGUOUS line ${item.lineNumber}: ${item.imageHint} -> ${item.chosenPath}`);
    }
  }
  await fs.writeFile(generatedManifestPath, generatedLines.join('\n'), 'utf8');

  const summaryPath = path.join(runLabelDir, 'ui-validation-build-summary.json');
  const buildSummary = (generatedPdf) => ({
    runRoot,
    label,
    masterManifest,
    stepRulesPath: stepRules?.path || null,
    traceEventCount: traceSpans.length,
    traceFrameCount: traceFrames.length,
    videoFrameCount: videoFrames.length,
    visualMatchEnabled,
    visualMatchMaxScore,
    generatedManifest: generatedManifestPath,
    generatedPdf,
    selectedCount: selected.length,
    missingCount: missing.length,
    ambiguousCount: ambiguous.length,
    selected,
    missing,
    ambiguous,
  });

  if (missing.length > 0) {
    await fs.writeFile(summaryPath, JSON.stringify(buildSummary(null), null, 2), 'utf8');
    console.log('[run-ui-validations] Refusing to build dated PDF: one or more slides have no current-run image match.');
    console.log(`[run-ui-validations] Summary: ${summaryPath}`);
    process.exitCode = 1;
    return;
  }

  const pdfPath = path.join(runLabelDir, `ui_vals_${label}_${ts()}.pdf`);
  const title = `${label} - UI Validations (${path.basename(runRoot)})`;

  const builderScript = path.join(cwd, 'scripts', 'Build-UiValidationsPdf.mjs');
  if (!(await exists(builderScript))) {
    console.log(`[run-ui-validations] Skipping: PDF builder script not found at ${builderScript}`);
    return;
  }

  const builderExit = await run(process.execPath, [
    builderScript,
    '--manifest',
    generatedManifestPath,
    '--outputPath',
    pdfPath,
    '--title',
    title,
    '--allow-missing',
    'true',
  ]);

  const summary = buildSummary(builderExit === 0 ? pdfPath : null);
  await fs.writeFile(summaryPath, JSON.stringify(summary, null, 2), 'utf8');

  if (builderExit !== 0) {
    console.log('[run-ui-validations] PDF build failed. See summary JSON for details.');
    return;
  }

  console.log(`[run-ui-validations] Run-level UI validation PDF created: ${pdfPath}`);
  console.log(`[run-ui-validations] Summary: ${summaryPath}`);
}

main().catch((err) => {
  console.error(err?.message || err);
  process.exit(1);
});
