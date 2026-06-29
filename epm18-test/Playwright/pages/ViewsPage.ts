import { expect } from '@playwright/test';
import { BasePage } from './BasePage';

export class ViewsPage extends BasePage {

async open(): Promise<void> {

    await this.page.getByRole('link', { name: 'Views' }).click();

    await expect(
        this.page.getByRole('application', {
            name: 'Views List'
        })
    ).toBeVisible();

}

async openViewHierarchy(viewName: string, viewpointName: string): Promise<void> {

    await this.open();

    await this.openView(viewName);
  
}

   async openView(viewName: string): Promise<void> {

    const view = this.page.getByRole('link', {
        name: viewName,
        exact: true
    });

    await expect(view).toBeVisible();

    await view.click();

    await expect(
        this.page.getByText(viewName)).toBeVisible();

}

async openViewpoint(viewpointName: string): Promise<void> {

    const viewpoint = this.page.getByRole('tab', {
        name: viewpointName,
        exact: true
    });

    await viewpoint.click();

    await expect(
        this.page.getByRole('application', {
            name: 'Viewpoint Grid'
        })
    ).toBeVisible();

}

}