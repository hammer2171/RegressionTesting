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
}