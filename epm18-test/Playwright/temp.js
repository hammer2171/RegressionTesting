import { test, expect } from '@playwright/test';

test.use({
  storageState: 'playwright/.auth/user.epm18_test.json'
});

test('test', async ({ page }) => {
  await page.goto('https://example.com/');
});