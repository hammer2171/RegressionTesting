import { Page } from '@playwright/test';
import { GlobalHeader } from '../components/GlobalHeader';

export class HomePage {

    readonly header: GlobalHeader;

    constructor(
        protected readonly page: Page
    ) {
        this.header = new GlobalHeader(page);
    }

    async open(): Promise<void> {
        await this.page.goto('/epm');
    }

}