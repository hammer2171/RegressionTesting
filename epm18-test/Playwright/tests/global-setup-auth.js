const fs = require('fs');
const path = require('path');
const { chromium } = require('@playwright/test');
const dotenv = require('dotenv');

dotenv.config({ path: process.env.ENV_FILE || '.env' });

const DEFAULT_EPM_BASE_URL =
  'https://epm18-test-a706571.epm.us2.oraclecloud.com/epm';
const DEFAULT_STORAGE_STATE_PATH = 'playwright/.auth/user.json';
const AUTH_FIELD_TIMEOUT_MS = parseMsEnv('PW_AUTH_FIELD_TIMEOUT_MS', 60000);
const AUTH_STATE_TIMEOUT_MS = parseMsEnv('PW_AUTH_STATE_TIMEOUT_MS', 120000);
const AUTH_POLL_INTERVAL_MS = 1000;
const AUTH_HEADLESS = parseBooleanEnv('PW_AUTH_HEADLESS', true);

module.exports = async function globalSetup() {
  const autoAuth = (process.env.PW_AUTO_AUTH ?? 'true').toLowerCase();
  if (autoAuth === 'false' || autoAuth === '0' || autoAuth === 'no') {
    return;
  }

  const baseUrl = process.env.EPM_BASE_URL ?? DEFAULT_EPM_BASE_URL;
  const storageStatePath = resolveStorageStatePath();
  const username = process.env.EPM_USERNAME;
  const password = process.env.EPM_PASSWORD;

  await fs.promises.mkdir(path.dirname(storageStatePath), { recursive: true });

  const browser = await launchAuthBrowser();

  let context;
  if (fs.existsSync(storageStatePath)) {
    context = await browser.newContext({ storageState: storageStatePath });
  } else {
    context = await browser.newContext();
  }

  const page = await context.newPage();
  await page.goto(baseUrl, { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle').catch(() => null);

  let state = await detectAuthState(page);
  if (state === 'login') {
    if (!username || !password) {
      await context.close();
      await browser.close();
      throw new Error(
        'Auth is expired and credentials are missing. Set EPM_USERNAME/EPM_PASSWORD (in ENV_FILE or .env), or run "npm run auth:refresh".'
      );
    }

    await loginWithCredentials(page, username, password);
    await page.waitForLoadState('networkidle').catch(() => null);
    state = await waitForHomeOrLogin(page);
    if (state !== 'home') {
      await context.close();
      await browser.close();
      throw new Error('Automatic auth refresh did not reach the EPM home page. Run "npm run auth:refresh".');
    }
  }

  if (state === 'unknown') {
    if (!username || !password) {
      await context.close();
      await browser.close();
      throw new Error(
        'Auth state is unknown and credentials are missing. Set EPM_USERNAME/EPM_PASSWORD, or run "npm run auth:refresh".'
      );
    }

    await loginWithCredentials(page, username, password);
    await page.waitForLoadState('networkidle').catch(() => null);
  }

  await context.storageState({ path: storageStatePath });
  await context.close();
  await browser.close();
};

async function waitForHomeOrLogin(page) {
  const deadline = Date.now() + AUTH_STATE_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const state = await detectAuthState(page);
    if (state !== 'unknown') {
      return state;
    }
    await page.waitForTimeout(AUTH_POLL_INTERVAL_MS);
  }
  return 'unknown';
}

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
    .locator(
      'input[name="username"], input[id*="user" i], input[placeholder*="user" i], input[placeholder*="email" i]'
    )
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

async function loginWithCredentials(page, username, password) {
  const usernameInput = page
    .locator('input[name="username"], input[id*="user" i], input[placeholder*="user" i], input[placeholder*="email" i]')
    .first();
  const passwordInput = page
    .locator('input[type="password"], input[name="password"], input[id*="pass" i]')
    .first();

  await usernameInput.waitFor({ state: 'visible', timeout: AUTH_FIELD_TIMEOUT_MS });
  await passwordInput.waitFor({ state: 'visible', timeout: AUTH_FIELD_TIMEOUT_MS });
  await usernameInput.fill(username);
  await passwordInput.fill(password);

  const signInButton = page.getByRole('button', { name: /sign in/i });
  if (await signInButton.isVisible().catch(() => false)) {
    await signInButton.click();
  } else {
    await passwordInput.press('Enter');
  }
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

async function launchAuthBrowser() {
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
        `[global-setup-auth] Failed to launch channel "${preferredChannel}" (${message}). Falling back to bundled Chromium.`
      );
    }
  }

  return chromium.launch(launchOptions);
}
function parseMsEnv(name, fallback) {
  const raw = process.env[name];
  if (!raw) return fallback;
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return parsed;
}

function resolveStorageStatePath() {
  const configuredPath = (process.env.PW_STORAGE_STATE || '').trim();
  const podKey = normalizeKey(process.env.POD_KEY);
  const userKey = normalizeKey(process.env.PW_AUTH_USER_KEY || process.env.EPM_AUTH_USER || 'user') || 'user';
  const podScopedPath = podKey ? path.join('playwright', '.auth', `${userKey}.${podKey}.json`) : null;

  if (configuredPath) {
    if (fs.existsSync(configuredPath)) {
      return configuredPath;
    }
    if (podScopedPath && fs.existsSync(podScopedPath)) {
      return podScopedPath;
    }
    return configuredPath;
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


