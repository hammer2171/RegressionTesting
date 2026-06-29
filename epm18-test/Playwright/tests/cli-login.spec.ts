import { test, expect } from '@playwright/test';

test.use({
  storageState: 'playwright/.auth/user.epm18_test.json',
});

test.describe('cli login', () => {
  test('opens the EPM pod with the repo auth state', async ({ page, baseURL }) => {
    test.skip(!baseURL, 'EPM_BASE_URL is not configured.');

    await page.goto(baseURL!);
    await page.waitForLoadState('networkidle').catch(() => null);

    await expect(page).not.toHaveURL(/\/ui\/v1\/signin/i);
    await expect(page).toHaveTitle(/Fusion Cloud Enterprise Data Management/i);
  });
});