import { Page } from '@playwright/test';

export class GlobalHeader {

    constructor(
        protected readonly page: Page
    ) {}

    async goHome(): Promise<void> {

    }

    async openViews(): Promise<void> {

    }

    async openRequests(): Promise<void> {

    }

    async openApplications(): Promise<void> {

    }

}