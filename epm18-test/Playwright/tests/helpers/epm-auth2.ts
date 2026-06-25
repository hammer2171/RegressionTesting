import { expect, Locator, Page } from '@playwright/test';

const DEFAULT_EPM_BASE_URL =
  'https://epm18-test-a706571.epm.us2.oraclecloud.com/epmcloud';

export async function ensureEpmAuthenticated(
  page: Page,
  baseUrl: string = process.env.EPM_BASE_URL ?? DEFAULT_EPM_BASE_URL
): Promise<void> {
  await page.goto(baseUrl, { waitUntil: 'domcontentloaded' });

  for (let attempt = 1; attempt <= 2; attempt++) {
    const preLoginState = await waitForHomePadOrLogin(page, { timeoutMs: 90000, loginGraceMs: 3000 });
    if (preLoginState === 'home') {
      return;
    }

    await loginWithEnvCredentials(page);

    const postLoginState = await waitForHomePadOrLogin(page, {
      timeoutMs: 120000,
      loginGraceMs: 15000,
    });
    if (postLoginState === 'home') {
      return;
    }
  }

  throw new Error('Unable to establish EPM session after retrying login.');
}

export async function gotoWithReauth(
  page: Page,
  targetUrl: string,
  baseUrl: string = process.env.EPM_BASE_URL ?? DEFAULT_EPM_BASE_URL
): Promise<void> {
  for (let attempt = 1; attempt <= 3; attempt++) {
    await page.goto(targetUrl, { waitUntil: 'domcontentloaded' });

    const state = await waitForDataExchangeOrLogin(page);
    if (state === 'ready') {
      return;
    }

    await ensureEpmAuthenticated(page, baseUrl);
  }

  throw new Error(`Navigation to ${targetUrl} still redirected to sign-in after re-authentication.`);
}

export async function openDataExchange(
  page: Page,
  targetUrl: string,
  baseUrl: string = process.env.EPM_BASE_URL ?? DEFAULT_EPM_BASE_URL
): Promise<void> {
  await ensureEpmAuthenticated(page, baseUrl);

  await page.waitForURL(/epm22-test-a706571\.epm\.us-phoenix-1\.ocs\.oraclecloud\.com/i, {
    timeout: 120000,
  });

  await gotoWithReauth(page, targetUrl, baseUrl);

  if (await page.getByRole('link', { name: 'Application' }).isVisible().catch(() => false)) {
    await page.getByRole('link', { name: 'Application' }).click();
    await page.getByRole('link', { name: 'Data Exchange' }).click();
  } else if (await page.getByRole('link', { name: /^Data$/i }).isVisible().catch(() => false)) {
    await page.getByRole('link', { name: /^Data$/i }).click();
  }
}

export async function signOutEpm(page: Page): Promise<void> {
  await page.getByRole('link', { name: /russell\.shellhamer@nov\.com:/i }).click();
  await page.getByRole('link', { name: 'Sign Out' }).click();
  await page.getByRole('button', { name: 'OK' }).click();
}

async function isLoginPromptVisible(page: Page): Promise<boolean> {
  const currentUrl = page.url().toLowerCase();
  if (currentUrl.includes('/ui/v1/signin') || currentUrl.includes('/login')) {
    return true;
  }

  const usernameVisible = await getUsernameInput(page).isVisible().catch(() => false);
  const passwordVisible = await getPasswordInput(page).isVisible().catch(() => false);
  const signInVisible = await page.getByRole('button', { name: /sign in/i }).isVisible().catch(() => false);

  return (usernameVisible && passwordVisible) || (signInVisible && (usernameVisible || passwordVisible));
}

async function loginWithEnvCredentials(page: Page): Promise<void> {
  const username = process.env.EPM_USERNAME;
  const password = process.env.EPM_PASSWORD;
  if (!username || !password) {
    throw new Error(
      'Login page detected but EPM credentials are not configured. Set EPM_USERNAME and EPM_PASSWORD in .env.'
    );
  }

  const usernameInput = await findVisibleLocator(
    [
      page.getByRole('textbox', { name: /user name|email/i }),
      page.getByPlaceholder(/user name or email/i),
      page.locator('input[name="username"]'),
      page.locator('input[id*="user" i]'),
    ],
    20000
  );
  const passwordInput = await findVisibleLocator(
    [
      page.getByLabel(/password/i),
      page.getByPlaceholder(/password/i),
      page.locator('input[type="password"]'),
      page.locator('input[name="password"]'),
    ],
    20000
  );

  if (!usernameInput || !passwordInput) {
    throw new Error(`Login prompt detected but username field was not interactable at ${page.url()}.`);
  }

  await usernameInput.fill(username);
  await passwordInput.fill(password);
  await page.getByRole('button', { name: 'Sign In' }).click();
}

async function waitForDataExchangeOrLogin(page: Page): Promise<'ready' | 'login'> {
  let state: 'ready' | 'login' | 'unknown' = 'unknown';
  await expect
    .poll(
      async () => {
        if (await isLoginPromptVisible(page)) {
          state = 'login';
          return state;
        }
        const frameReady = await page
          .frameLocator('iframe')
          .getByRole('link', { name: 'DL_0057' })
          .isVisible()
          .catch(() => false);
        const appLink = await page.getByRole('link', { name: 'Application' }).isVisible().catch(() => false);
        const dataLink = await page.getByRole('link', { name: /^Data$/i }).isVisible().catch(() => false);
        if (frameReady || appLink || dataLink) {
          state = 'ready';
          return state;
        }
        state = 'unknown';
        return state;
      },
      { timeout: 30000 }
    )
    .not.toBe('unknown');
  return state === 'unknown' ? 'login' : state;
}

async function waitForHomePadOrLogin(
  page: Page,
  options: { timeoutMs?: number; loginGraceMs?: number } = {}
): Promise<'home' | 'login'> {
  const timeoutMs = options.timeoutMs ?? 90000;
  const loginGraceMs = options.loginGraceMs ?? 10000;
  let loginFirstSeenAt: number | null = null;
  let resolvedState: 'home' | 'login' | 'loading' = 'loading';

  await expect
    .poll(
      async () => {
        if (await isHomePadVisible(page)) {
          loginFirstSeenAt = null;
          resolvedState = 'home';
          return resolvedState;
        }

        if (await isLoginPromptVisible(page)) {
          if (loginFirstSeenAt === null) {
            loginFirstSeenAt = Date.now();
          }
          if (Date.now() - loginFirstSeenAt >= loginGraceMs) {
            resolvedState = 'login';
            return resolvedState;
          }
        } else {
          loginFirstSeenAt = null;
        }

        resolvedState = 'loading';
        return resolvedState;
      },
      { timeout: timeoutMs, intervals: [500, 1000, 2000, 3000] }
    )
    .not.toBe('loading');

  return resolvedState as 'home' | 'login';
}

async function isHomePadVisible(page: Page): Promise<boolean> {
  const appLink = await page.getByRole('link', { name: 'Application' }).isVisible().catch(() => false);
  const dataLink = await page.getByRole('link', { name: /^Data$/i }).isVisible().catch(() => false);
  return appLink || dataLink;
}

function getUsernameInput(page: Page) {
  return page
    .locator(
      'input[name="username"], input[id*="user" i], input[placeholder*="user" i], input[placeholder*="email" i]'
    )
    .first();
}

function getPasswordInput(page: Page) {
  return page.locator('input[type="password"], input[name="password"], input[id*="pass" i]').first();
}

async function findVisibleLocator(
  candidates: Locator[],
  timeoutMs: number
): Promise<Locator | null> {
  for (const candidate of candidates) {
    const first = candidate.first();
    const visible = await first.isVisible().catch(() => false);
    if (visible) {
      return first;
    }
    await first.waitFor({ state: 'visible', timeout: timeoutMs }).catch(() => null);
    const nowVisible = await first.isVisible().catch(() => false);
    if (nowVisible) {
      return first;
    }
  }
  return null;
}

