import { test, expect } from '@playwright/test';

test.describe('epm18-test smoke', () => {
  test('opens the EPM landing page with configured storage state', async ({ page, baseURL }) => {
    test.skip(!baseURL, 'EPM_BASE_URL is not configured.');

    await page.goto(baseURL!);
    await page.waitForLoadState('domcontentloaded');

    await expect(page).toHaveURL(/oraclecloud\.com|ocs\.oraclecloud\.com/);
  });
});
