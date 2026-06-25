import { expect, type Page } from '@playwright/test';

export class Epm18testMainHomePage {
  constructor(private readonly page: Page) {}

  async epm18testhomeicon(): Promise<void> {
    const homeLink = this.page.getByRole('link', { name: 'Home', exact: true });
    await expect(homeLink).toBeVisible();
    await homeLink.click();
  }
}