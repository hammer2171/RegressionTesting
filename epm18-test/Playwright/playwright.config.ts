import fs from 'fs';
import path from 'path';
import { defineConfig } from '@playwright/test';
import dotenv from 'dotenv';

const PROJECT_ROOT = __dirname;
const POD_SETTINGS = readPodSettings();
dotenv.config({ path: resolveEnvFilePath() });

const EPM_BASE_URL =
  process.env.EPM_BASE_URL ??
  POD_SETTINGS?.podUrl ??
  'https://epm18-test-a706571.epm.us2.oraclecloud.com/epmcloud';

const STORAGE_STATE_PATH = resolveStorageStatePath();
const PW_SLOWMO = Number(process.env.PW_SLOWMO ?? 0);
const PW_HEADLESS = /^(1|true|yes)$/i.test(process.env.PW_HEADLESS ?? '');

export default defineConfig({
  globalSetup: require.resolve('./tests/global-setup-auth.js'),
  testDir: './tests',
  testMatch: ['**/*.spec.ts', '**/*.test.ts', '**/*.spec.js', '**/*.test.js'],
  testIgnore: ['**/*.old.spec.ts', '**/tests-bogus/**'],
  timeout: 120000,
  use: {
    baseURL: EPM_BASE_URL,
    storageState: STORAGE_STATE_PATH,
    headless: PW_HEADLESS,
    viewport: PW_HEADLESS ? { width: 1920, height: 1080 } : null,
    launchOptions: {
      slowMo: Number.isFinite(PW_SLOWMO) ? PW_SLOWMO : 0,
      args: PW_HEADLESS ? ['--window-size=1920,1080'] : ['--start-maximized'],
    },
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [
    {
      name: 'edge',
      use: {
        channel: 'msedge',
      },
    },
  ],
});

function resolveEnvFilePath(): string {
  const configured = (process.env.ENV_FILE || '').trim();
  if (configured) {
    const configuredPath = path.isAbsolute(configured) ? configured : path.join(PROJECT_ROOT, configured);
    if (fs.existsSync(configuredPath)) return configuredPath;
    return configured;
  }

  const podKey = normalizeKey(POD_SETTINGS?.podKey);
  if (podKey) {
    const podEnvPath = path.join(PROJECT_ROOT, '.env.' + podKey);
    if (fs.existsSync(podEnvPath)) return podEnvPath;
  }

  return path.join(PROJECT_ROOT, '.env');
}

function resolveStorageStatePath(): string {
  const configured = (process.env.PW_STORAGE_STATE || '').trim();
  if (configured) {
    return path.isAbsolute(configured) ? configured : path.join(PROJECT_ROOT, configured);
  }

  const podKey = normalizeKey(process.env.POD_KEY || POD_SETTINGS?.podKey);
  const userKey = normalizeKey(process.env.PW_AUTH_USER_KEY || process.env.EPM_AUTH_USER || 'user') || 'user';
  if (podKey) {
    return path.join(PROJECT_ROOT, 'playwright', '.auth', userKey + '.' + podKey + '.json');
  }

  return path.join(PROJECT_ROOT, 'playwright', '.auth', 'user.json');
}

function readPodSettings(): { podKey?: string; podUrl?: string } | null {
  const settingsPath = path.join(PROJECT_ROOT, '.pod-settings.json');
  if (!fs.existsSync(settingsPath)) return null;

  try {
    return JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
  } catch {
    return null;
  }
}

function normalizeKey(value: unknown): string {
  if (!value) return '';
  return String(value).trim().toLowerCase().replace(/[^a-z0-9_]+/g, '_').replace(/^_+|_+$/g, '');
}


