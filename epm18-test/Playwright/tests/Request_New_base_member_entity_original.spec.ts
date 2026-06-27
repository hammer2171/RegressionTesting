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

  await page.getByRole('tab', { name: 'Input_EPM_Entity_Base' }).click();
  await expect(page.getByRole('application', { name: 'Viewpoint Grid' })).toBeVisible();

  await page.getByRole('button', { name: 'New Request' }).click();
  await expect(page.getByRole('grid', { name: 'List of Requests' })).toBeVisible();

  await page.getByRole('button', { name: 'Add Node' }).click();
  await page.getByRole('menuitem', { name: 'Add New' }).click();
  await expect(page.getByRole('row', { name: 'Request 35251 Show Item' })).toBeVisible();

  await page.getByRole('textbox', { name: 'Ledger Number' }).click();
  await expect(page.getByRole('row', { name: '3010LE (NOV Inc.)' })).toBeVisible();

  await page.getByRole('textbox', { name: 'Search for a node' }).click();
  await page.getByRole('textbox', { name: 'Search for a node' }).fill('0536');
  await page.getByRole('textbox', { name: 'Search for a node' }).press('Enter');
  await expect(page.getByRole('row', { name: '0536 (NOV Products Middle' })).toBeVisible();

  await page.getByText('(NOV Products Middle East FZE)').click();
  await page.getByRole('button', { name: 'OK' }).click();
  await expect(page.getByRole('row', { name: 'Request 35251 Show Item' })).toBeVisible();

  await page.locator('#oj-combobox-choice-50b08f12-f44f-4241-9e68-328f3b2a1622_e882c03c-72cc-4a88-be22-9c4d58207f07 > .oj-text-field-end > .oj-combobox-arrow').click();
  await expect(page.getByRole('listbox', { name: 'Business Unit' })).toBeVisible();

  await page.getByRole('option', { name: 'EE - Energy Equipment Admin' }).click();
  await expect(page.getByRole('row', { name: 'Request 35251 Show Item' })).toBeVisible();

  await page.getByRole('button', { name: 'Submit' }).click();
  await expect(page.getByRole('tab', { name: 'Requests' })).toBeVisible();

  await page.getByRole('button', { name: 'Close' }).click();
  await expect(page.getByRole('application', { name: 'Views List' })).toBeVisible();

  await page.getByRole('button', { name: 'Home' }).click();
});