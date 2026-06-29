import { Page } from '@playwright/test';
import { expect } from '@playwright/test';

export class GlobalHeader {

    constructor(
        protected readonly page: Page
    ) {}

    async goHome(): Promise<void> {
        const homeButton = this.page.getByRole('button', {
            name: 'Home',
            exact: true
        });

        await expect(homeButton).toBeVisible();

        await homeButton.click();
    }

    async openViews(): Promise<void> {
        const viewsLink = this.page.getByRole('link', {
            name: 'Views',
            exact: true
        });

        await expect(viewsLink).toBeVisible();

        await viewsLink.click();
    }

    async openRequests(): Promise<void> {
        const requestsLink = this.page.getByRole('link', {
            name: 'Requests',
            exact: true
        });

        await expect(requestsLink).toBeVisible();

        await requestsLink.click();
    }

    async openApplications(): Promise<void> {
        const applicationsLink = this.page.getByRole('link', {
            name: 'Applications',
            exact: true
        });

        await expect(applicationsLink).toBeVisible();

        await applicationsLink.click();
    }

}