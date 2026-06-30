import { Page, expect } from '@playwright/test';

/**
 * Oracle EDM ARIA Harness
 *
 * Snapshot Regions
 * ----------------
 * 1. Global Header             -> banner
 * 2. Views List                -> application "Views List"
 * 3. Viewpoint Grid            -> application "Viewpoint Grid"
 * 4. Requests                  -> grid "List of Requests"
 * 5. Ledger Selection Dialog   -> dialog
 *
 * Purpose:
 * Capture stable Oracle JET accessibility regions for
 * regression comparison after Oracle monthly updates.
 */

export class EdmHarness {
  constructor(private readonly page: Page) {}

  async snapshotGlobalHeader() {
    await expect(
      this.page.getByRole('banner')
    ).toMatchAriaSnapshot();
  }

  async snapshotViewsList() {
    await expect(
      this.page.getByRole('application', {
        name: 'Views List'
      })
    ).toMatchAriaSnapshot();
  }

  async snapshotViewpointGrid() {
    await expect(
      this.page.getByRole('application', {
        name: 'Viewpoint Grid'
      })
    ).toMatchAriaSnapshot();
  }

  async snapshotRequestsRegion() {
    await expect(
      this.page.getByRole('grid', {
        name: 'List of Requests'
      })
    ).toMatchAriaSnapshot();
  }

  async snapshotLedgerSelectionDialog() {
    await expect(
      this.page.getByRole('dialog')
    ).toMatchAriaSnapshot();
    }
      async snapshotNOVLESelect() {
    await expect(
      this.page.getByRole('button') {}
    ).toMatchAriaSnapshot();
  }


      async snapshotNOVLEseacrchNodes() {
    await expect(
      this.page.getByRole('button') {}
    ).toMatchAriaSnapshot();
  }


      async snapshotNOVLEseacrchNodes() {
    await expect(
      this.page.getByRole('textbox') {}
    ).toMatchAriaSnapshot();
  }

    async snapshotNOVLEgrid() {
    await expect(
      this.page.getByRole('grid') {}
    ).toMatchAriaSnapshot();
  }






}

 await this.page.getByRole('button', { name: 'Search NOV_Legal_Entity' }).click();
  await page.getByRole('textbox', { name: 'Search Nodes' }).click();
  await page.getByRole('textbox', { name: 'Search Nodes' }).fill('0002');
  await page.locator('#cf20a9a3-3cae-44eb-954a-1c72921c1139_searchNodeInput > .search > .searchPartialIcon').click();
  await expect(page.getByRole('grid', { name: 'Results' })).toBeVisible();