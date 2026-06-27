const fs = require('fs');
const path = require('path');
const { chromium } = require('@playwright/test');
const dotenv = require('dotenv');

const PROJECT_ROOT = path.resolve(__dirname, '..');

dotenv.config({ path: resolveEnvFilePath() });

const DEFAULT_EPM_BASE_URL =
  'https://epm18-test-a706571.epm.us2.oraclecloud.com/epm';
const DEFAULT_STORAGE_STATE_PATH = path.join(PROJECT_ROOT, 'playwright', '.auth', 'user.json');
const AUTH_HEADLESS = parseBooleanEnv('PW_AUTH_HEADLESS', true);

module.exports = async function globalTeardown() {
  const autoAuth = (process.env.PW_AUTO_AUTH ?? 'true').toLowerCase();
  if (autoAuth === 'false' || autoAuth === '0' || autoAuth === 'no') {
    return;
  }

  const baseUrl = process.env.EPM_BASE_URL ?? DEFAULT_EPM_BASE_URL;
  const storageStatePath = resolveStorageStatePath();

  if (!fs.existsSync(storageStatePath)) {
    return;
  }

  const browser = await launchBrowser();
  const context = await browser.newContext({ storageState: storageStatePath });
  const page = await context.newPage();

  try {
    await page.goto(baseUrl, { waitUntil: 'domcontentloaded' });
    await page.waitForLoadState('networkidle').catch(() => null);

    const state = await detectAuthState(page);
    if (state !== 'home') {
      return;
    }

    const userMenuLink = page.locator('a.efs-user-name').first();
    if (!(await userMenuLink.isVisible().catch(() => false))) {
      return;
    }

    try {
      await userMenuLink.click();
      await page.getByRole('link', { name: /^Sign Out$/i }).click();
      await page.getByRole('button', { name: /^OK$/i }).click();
      await page.waitForLoadState('networkidle').catch(() => null);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (
        /Target page, context or browser has been closed/i.test(message) ||
        /Target closed/i.test(message)
      ) {
        return;
      }
      throw error;
    }
  } finally {
    await context.close().catch(() => null);
    await browser.close().catch(() => null);
  }
};

async function detectAuthState(page) {
  if (await isHomePadVisible(page)) {
    return 'home';
  }

  if (await isLoginPromptVisible(page)) {
    return 'login';
  }

  return 'unknown';
}

async function isHomePadVisible(page) {
  const userImage = await page.getByTitle(/current user image/i).first().isVisible().catch(() => false);
  if (userImage) return true;

  const userMenu = await page.locator('a.efs-user-name').first().isVisible().catch(() => false);
  if (userMenu) return true;

  const appLink = await page.getByRole('link', { name: 'Application' }).isVisible().catch(() => false);
  const dataLink = await page.getByRole('link', { name: /^Data$/i }).isVisible().catch(() => false);
  return appLink || dataLink;
}

async function isLoginPromptVisible(page) {
  const currentUrl = page.url().toLowerCase();
  if (currentUrl.includes('/ui/v1/signin') || currentUrl.includes('/login')) {
    return true;
  }

  const usernameVisible = await page
    .locator('input[name="username"], input[id*="user" i], input[placeholder*="user" i], input[placeholder*="email" i]')
    .first()
    .isVisible()
    .catch(() => false);
  const passwordVisible = await page
    .locator('input[type="password"], input[name="password"], input[id*="pass" i]')
    .first()
    .isVisible()
    .catch(() => false);
  const signInVisible = await page.getByRole('button', { name: /sign in/i }).isVisible().catch(() => false);
  return (usernameVisible && passwordVisible) || (signInVisible && (usernameVisible || passwordVisible));
}

function parseBooleanEnv(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === null || raw === '') {
    return fallback;
  }

  const normalized = String(raw).trim().toLowerCase();
  if (['1', 'true', 'yes', 'on'].includes(normalized)) return true;
  if (['0', 'false', 'no', 'off'].includes(normalized)) return false;
  return fallback;
}

async function launchBrowser() {
  const preferredChannel = (process.env.PW_CHANNEL || 'msedge').trim();
  const launchOptions = { headless: AUTH_HEADLESS };

  if (preferredChannel) {
    try {
      return await chromium.launch({
        ...launchOptions,
        channel: preferredChannel,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.warn(
        `[global-teardown-auth] Failed to launch channel "${preferredChannel}" (${message}). Falling back to bundled Chromium.`
      );
    }
  }

  return chromium.launch(launchOptions);
}

function resolveStorageStatePath() {
  const configuredPath = (process.env.PW_STORAGE_STATE || '').trim();
  const podKey = normalizeKey(process.env.POD_KEY);
  const userKey = normalizeKey(process.env.PW_AUTH_USER_KEY || process.env.EPM_AUTH_USER || 'user') || 'user';
  const podScopedPath = podKey
    ? path.join(PROJECT_ROOT, 'playwright', '.auth', `${userKey}.${podKey}.json`)
    : null;

  if (configuredPath) {
    if (path.isAbsolute(configuredPath)) {
      return configuredPath;
    }
    return path.join(PROJECT_ROOT, configuredPath);
  }

  if (podScopedPath) {
    return podScopedPath;
  }
  return DEFAULT_STORAGE_STATE_PATH;
}

function normalizeKey(value) {
  if (!value) return '';
  return String(value).trim().toLowerCase().replace(/[^a-z0-9_]+/g, '_').replace(/^_+|_+$/g, '');
}

function resolveEnvFilePath() {
  const configured = (process.env.ENV_FILE || '').trim();
  if (configured) {
    const configuredPath = path.isAbsolute(configured) ? configured : path.resolve(process.cwd(), configured);
    if (fs.existsSync(configuredPath)) return configuredPath;
  }

  const podScopedPath = resolvePodScopedEnvPath();
  if (podScopedPath) {
    return podScopedPath;
  }

  const cwdDefault = path.resolve(process.cwd(), '.env');
  if (fs.existsSync(cwdDefault)) return cwdDefault;
  return path.resolve(PROJECT_ROOT, '.env');
}

function resolvePodScopedEnvPath() {
  const podSettingsPath = path.resolve(process.cwd(), '.pod-settings.json');
  if (!fs.existsSync(podSettingsPath)) return null;

  try {
    const raw = fs.readFileSync(podSettingsPath, 'utf8');
    const settings = JSON.parse(raw);
    const podKey = normalizeKey(settings && settings.podKey);
    if (!podKey) return null;
    const candidate = path.resolve(process.cwd(), `.env.${podKey}`);
    return fs.existsSync(candidate) ? candidate : null;
  } catch {
    return null;
  }
}

