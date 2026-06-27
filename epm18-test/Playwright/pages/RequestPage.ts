import { expect } from '@playwright/test';
import { BasePage } from './BasePage';

  export class RequestPage extends BasePage {
async newRequest(): Promise<void> {

    const button = this.page.getByRole('button', {
        name: 'New Request'
    });

    await expect(button).toBeVisible();

    await button.click();

    await this.verifyOpen();

}

async addNode(): Promise<void> {

    await this.page
        .getByRole('button', {
            name: 'Add Node'
        })
        .click();

    await this.page
        .getByRole('menuitem', {
            name: 'Add New'
        })
        .click();

}
}




