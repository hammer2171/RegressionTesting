import { test as base, expect, type Page } from '@playwright/test';
import { ensureEpmAuthenticated } from '../helpers/epm-auth';

type AuthFixtures = {
  authenticatedPage: Page;
};

export const test = base.extend<AuthFixtures>({
  page: async ({ page }, use) => {
    const allowInteractive = (process.env.PW_ALLOW_INTERACTIVE_LOGIN || '').toLowerCase() === 'true';
    const skipAuthCheck = /^(1|true|yes)$/i.test(process.env.PW_SKIP_AUTH_CHECK ?? '');
    if (!allowInteractive && !skipAuthCheck) {
      await ensureEpmAuthenticated(page);
    } else {
      if (allowInteractive) {
        const baseUrl =
          process.env.EPM_URL ??
          process.env.EPM_BASE_URL ??
          'https://epm11-test-a706571.epm.us2.oraclecloud.com/epmcloud';
        await page.goto(baseUrl, { waitUntil: 'domcontentloaded' });
      }
    }
    await use(page);
  },
  authenticatedPage: async ({ page }, use) => {
    await use(page);
  },
});

export { expect };
