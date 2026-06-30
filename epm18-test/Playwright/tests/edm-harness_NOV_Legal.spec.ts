import { test, expect } from '@playwright/test';
import { EdmHarness } from '../pages/edmHarness';
import { Epm18testMainHomePage } from '../pages/Epm18testMainHomePage';

test.use({
  storageState: 'playwright/.auth/user.epm18_test.json'
});

test('EDM Harness - Entity Request Flow', async ({ page }) => {

  const home = new Epm18testMainHomePage(page);
  const harness = new EdmHarness(page);

  //
  // Login
  //
  await page.goto(process.env.EPM_BASE_URL!);
  await page.waitForLoadState('networkidle');

  await harness.snapshotGlobalHeader();

  //
  // Open Views
  //
  await home.epm18testtilesopen('Views');

  await harness.snapshotViewsList();

  //
  // Open Entity View
  //
  await page.getByRole('link', {
    name: 'A_Entry_Entity'
  }).click();

  //
  // Open Viewpoint
  //
  await page.getByRole('tab', {
    name: 'NOV_Legal_Entity'
  }).click();

  await harness.snapshotViewpointGrid();

  //
  // New Request
  //
  await page.getByRole('button', {
    name: 'New Request'
  }).click();

  await expect(
    page.getByRole('grid', {
      name: 'List of Requests'
    })
  ).toBeVisible();

  await harness.snapshotRequestsRegion();

  //
  // Add Node
  //
  await page.getByRole('button', {
    name: 'Add Node'
  }).click();

  await page.getByRole('menuitem', {
    name: 'Add New'
  }).click();

 

  //
  // Ledger
  //
await page.getByRole('textbox', {
    name: 'Ledger Number'
}).click();


 await harness.snapshotLedgerSelectionDialog();
 
 const dialog = page.getByRole('dialog');
 
  await expect(
    dialog.getByRole('row', {
      name: '3010LE (NOV Inc.)'
    })
  ).toBeVisible();

  //
  // Search Node
  //
  await dialog.getByRole('textbox', {
    name: 'Search for a node'
  }).fill('0536');

  await dialog.getByRole('textbox', {
    name: 'Search for a node'
  }).press('Enter');

  await expect(
    dialog.getByText('0536 (NOV Products Middle East FZE)')
  ).toBeVisible();

  await dialog.getByText(
    '0536 (NOV Products Middle East FZE)'
  ).click();

  await dialog.getByRole('button', {
    name: 'OK'
  }).click();

  //
  // Business Unit
  // (Leave this until we replace the brittle CSS locator.)
  //

  //
  // Submit
  //
  await page.getByRole('button', {
    name: 'Submit'
  }).click();

  //
  // Done
  //
  await page.getByRole('button', {
    name: 'Done'
  }).click();

  await home.epm18testhomeicon();
});