import { test, expect } from '@playwright/test';

test.use({
  storageState: 'playwright/.auth/user.epm18_test.json'
});

test('test', async ({ page }) => {
  await page.goto('https://epm18-test-a706571.epm.us2.oraclecloud.com/epm/');
  await expect(page.getByRole('banner', { name: 'Global Header' })).toBeVisible();

  await page.getByRole('img', { name: 'Views' }).click();
  await expect(page.getByRole('application', { name: 'Views List' })).toBeVisible();

  await page.getByRole('link', { name: 'A_Entry_Entity' }).click();
  await expect(page.getByRole('application', { name: 'Viewpoint Hierarchy' })).toBeVisible();

  await page.getByRole('button', { name: 'New Request' }).click();
  await expect(page.getByRole('grid', { name: 'List of Requests' })).toBeVisible();

  await page.getByRole('button', { name: 'Search NOV_Legal_Entity' }).click();
  await page.getByRole('textbox', { name: 'Search Nodes' }).click();
  await page.getByRole('textbox', { name: 'Search Nodes' }).fill('0002');
  await page.locator('#cf20a9a3-3cae-44eb-954a-1c72921c1139_searchNodeInput > .search > .searchPartialIcon').click();
  await expect(page.getByRole('grid', { name: 'Results' })).toBeVisible();

  await page.getByText('0002').click();
  await expect(page.getByRole('row', { name: 'Expand/Collapse Has child nodes 3010LE 3010LE NOV Inc.' })).toBeVisible();

  await page.locator('.oj-combobox-arrow').first().click();
  await expect(page.getByRole('listbox', { name: 'Valid For Omega LE?' })).toBeVisible();

  await page.getByRole('option', { name: 'True' }).click();
  await expect(page.getByRole('row', { name: 'Request 35494 Show Item' })).toBeVisible();

  await page.locator('#oj-combobox-choice-cf20a9a3-3cae-44eb-954a-1c72921c1139_031cb078-a293-473a-af0f-dea332c24127 > .oj-text-field-end > .oj-combobox-arrow').click();
  await expect(page.getByRole('listbox', { name: 'Valid For Omega IC LE?' })).toBeVisible();

  await page.getByRole('option', { name: 'True' }).click();
  await expect(page.getByRole('row', { name: '0002.3001CE 2 Action Menu' })).toBeVisible();

  await page.getByRole('button', { name: 'Submit' }).click();
  await expect(page.getByRole('tab', { name: 'Requests' })).toBeVisible();

  await page.getByRole('button', { name: 'Home' }).click();
});