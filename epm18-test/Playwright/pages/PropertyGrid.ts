import { expect, Page } from '@playwright/test';

export class PropertyGrid {

    constructor(
        protected readonly page: Page
    ) {}

    //-------------------------------------------------------------------------
    // Text Box
    //-------------------------------------------------------------------------

    async setTextBox(
        property: string,
        value: string
    ): Promise<void> {

        const control = this.page
            .locator('#viewDetail')
            .getByRole('textbox', {
                name: property,
                exact: true
            });

        await expect(control).toBeVisible();

        await control.fill(value);

    }

    //-------------------------------------------------------------------------
    // Combo Box
    //-------------------------------------------------------------------------

    async setComboBox(
        property: string,
        value: string
    ): Promise<void> {

        const control = this.page
            .locator('#viewDetail')
            .getByRole('combobox', {
                name: property,
                exact: true
            });

        await expect(control).toBeVisible();

        await control.click();

        await this.page
            .getByRole('option', {
                name: value,
                exact: true
            })
            .click();

    }

    //-------------------------------------------------------------------------
    // Spin Button
    //-------------------------------------------------------------------------

    async setSpinButton(
        property: string,
        value: string
    ): Promise<void> {

        const control = this.page
            .locator('#viewDetail')
            .getByRole('spinbutton', {
                name: property,
                exact: true
            });

        await expect(control).toBeVisible();

        await control.fill(value);

    }

    //-------------------------------------------------------------------------
    // Read Value
    //-------------------------------------------------------------------------

    async getTextBoxValue(
        property: string
    ): Promise<string> {

        return await this.page
            .locator('#viewDetail')
            .getByRole('textbox', {
                name: property,
                exact: true
            })
            .inputValue();

    }

}