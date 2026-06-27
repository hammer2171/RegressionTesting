import { Page } from '@playwright/test';
import { GlobalHeader } from '../components/GlobalHeader';

export abstract class BasePage {

    protected readonly page: Page;
    readonly header: GlobalHeader;

    constructor(page: Page) {
        this.page = page;
        this.header = new GlobalHeader(page);
    }

}