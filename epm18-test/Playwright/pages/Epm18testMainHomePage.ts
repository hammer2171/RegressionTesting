import { expect, type Page } from '@playwright/test';

export class Epm18testMainHomePage {
  constructor(private readonly page: Page) {}

    async open(): Promise<void> {
        await this.page.goto('/epm');
    }
  
    async epm18testtilesopen(tilename: string): Promise<void> {
    const tile = this.page.getByRole('link', { name: tilename, exact: true });
    await expect(tile).toBeVisible();
    await tile.click();
	
	}	

async epm18testhomeicon(): Promise<void> {
    const homeButton = this.page.getByRole('button', {
        name: 'Home',
        exact: true
    });

    await expect(homeButton).toBeVisible();
    await homeButton.click();
}
}