import { Page } from '@playwright/test';

const DEFAULT_EPM_BASE_URL =
  'https://epm18-test-a706571.epm.us2.oraclecloud.com/epmcloud';

type AuthState = 'home' | 'login' | 'unknown';

const AUTH_SIGNAL_TIMEOUT_MS = Math.min(parseMsEnv('PW_AUTH_STATE_TIMEOUT_MS', 60000), 60000);
 
export async function ensureEpmAuthenticated(
  page: Page,
  baseUrl: string = process.env.EPM_URL ?? process.env.EPM_BASE_URL ?? DEFAULT_EPM_BASE_URL
): Promise<void> {
  ensurePageOpen(page, 'before authentication');
  const targetUrl = (baseUrl || '').trim();
  if (!targetUrl) {
    throw new Error('EPM base URL is not configured.');
  }

  await page.goto(targetUrl, { waitUntil: 'domcontentloaded' });

  const state = await waitForAuthState(page);

  if (state === 'home') {
    return;
  }

  if (state === 'login') {
    throw new Error(
      'Authentication session is not valid and UI credential entry is disabled. Refresh PW_STORAGE_STATE (playwright/.auth/*.json) and rerun.'
    );
  }

  throw new Error(
    'Authentication state is indeterminate after navigation. Refresh PW_STORAGE_STATE and retry.'
  );
}

async function waitForAuthState(page: Page): Promise<AuthState> {
  if (page.isClosed()) {
    return 'unknown';
  }

  const immediateState = await detectAuthState(page);
  if (immediateState !== 'unknown') {
    return immediateState;
  }

  return await Promise.any(authStateSignals(page)).catch(() => detectAuthState(page));
}



async function detectAuthState(page: Page): Promise<AuthState> {
  if (await isHomePadVisible(page)) {
    return 'home';
  }

  if (await isLoginPromptVisible(page)) {
    return 'login';
  }

  return 'unknown';
}

async function isHomePadVisible(page: Page): Promise<boolean> {
  const cardsNavVisible = await page
    .getByRole('navigation', { name: 'Clusters and Cards' })
    .isVisible()
    .catch(() => false);
  if (cardsNavVisible) return true;

  const journalsTileVisible = await page
    .getByRole('link', { name: 'Consolidation Journals' })
    .first()
    .isVisible()
    .catch(() => false);
  if (journalsTileVisible) return true;

  return await page
    .getByRole('banner', { name: 'EPM Global Header' })
    .isVisible()
    .catch(() => false);
}

function authStateSignals(page: Page): Promise<AuthState>[] {
  const homeSignals = [
    page.getByRole('navigation', { name: 'Clusters and Cards' }),
    page.getByRole('link', { name: 'Tasks', exact: true }).first(),
    page.getByRole('link', { name: 'Data', exact: true }).first(),
    page.getByRole('link', { name: 'Application', exact: true }).first(),
    page.getByRole('banner', { name: 'EPM Global Header' }),
  ];

  const loginSignals = [
    page.locator(
      'input[name="username"], input[id*="user" i], input[placeholder*="user" i], input[placeholder*="email" i]'
    ).first(),
    page.locator('input[type="password"], input[name="password"], input[id*="pass" i]').first(),
    page.getByRole('button', { name: /sign in/i }),
  ];

  return [
    ...homeSignals.map((locator) =>
      locator.waitFor({ state: 'visible', timeout: AUTH_SIGNAL_TIMEOUT_MS }).then(() => 'home' as const)
    ),
    ...loginSignals.map((locator) =>
      locator.waitFor({ state: 'visible', timeout: AUTH_SIGNAL_TIMEOUT_MS }).then(() => 'login' as const)
    ),
  ];
}

function parseMsEnv(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw === null || raw === '') {
    return fallback;
  }

  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

async function isLoginPromptVisible(page: Page): Promise<boolean> {
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

function ensurePageOpen(page: Page, phase: string): void {
  if (page.isClosed()) {
    throw new Error(`Browser page was closed ${phase}. Re-open a fresh Playwright session and retry.`);
  }
}

