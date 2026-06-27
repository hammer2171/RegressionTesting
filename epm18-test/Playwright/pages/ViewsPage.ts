import { expect } from '@playwright/test';
import { BasePage } from './BasePage';

export class RequestPage extends BasePage {

   async openView(viewName: string): Promise<void> {

    const view = this.page.getByRole('link', {
        name: viewName,
        exact: true
    });

    await expect(view).toBeVisible();

    await view.click();

    await expect(
        this.page.getByRole('application', {
            name: 'Viewpoint Hierarchy'
        })
    ).toBeVisible();

}

async openViewpoint(viewpointName: string): Promise<void> {

    const viewpoint = this.page.getByRole('tab', {
        name: viewpointName,
        exact: true
    });

    await expect(viewpoint).toBeVisible();

    await viewpoint.click();

    await expect(
        this.page.getByRole('application', {
            name: 'Viewpoint Grid'
        })
    ).toBeVisible();

}

}