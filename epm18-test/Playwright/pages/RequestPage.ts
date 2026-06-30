import { expect } from '@playwright/test';
import { BasePage } from './BasePage';
import { Epm18testMainHomePage } from './Epm18testMainHomePage';

export interface RequestEntryDetails {
    ledgerNumberRow: string;
    searchTerm: string;
    searchResultRowText: string;
    businessUnit: string;

}

export class RequestPage extends BasePage {
async newRequest(): Promise<void> {

    const button = this.page.getByRole('button', {
        name: 'New Request'
    });

    await expect(button).toBeVisible();

    await button.click();

    await expect(
        this.page.getByRole('grid', {
            name: 'List of Requests'
        })
    ).toBeVisible();

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

async selectLedgerNumber(ledgerNumber: string): Promise<void> {

    const ledgerField = this.page.getByRole('textbox', {
        name: 'Ledger Number',
        exact: true
    });

    await expect(ledgerField).toBeVisible();

    await ledgerField.click();

    const ledgerResult = this.page.getByRole('row', {
        name: ledgerNumber,
        exact: false
    }).first();

    await expect(ledgerResult).toBeVisible();

}

async searchForNode(searchTerm: string): Promise<void> {

    const dialog = this.page.getByRole('dialog').first();

    const searchField = dialog.getByRole('textbox', {
        name: 'Search for a node',
        exact: false
    });
    const searchButton = dialog.getByRole('button').first();

    await expect(searchField).toBeVisible();

    await expect(searchButton).toBeVisible();

    

    await searchField.fill(searchTerm);
   
  
   await searchButton.click();
   
}

async selectSearchResult(searchResultRowText: string): Promise<void> {
   const searchResultText = this.page.getByText(searchResultRowText, {
       exact: true
   });

    await searchResultText.click();
   await expect(searchResultText).toBeVisible();

  

   await this.confirmSelection();

   await this.dismissConcurrentDataUpdate();


}

async selectBusinessUnit(businessUnit: string): Promise<void> {

    const control = this.page.getByRole('combobox', {
        name: 'Business Unit',
        exact: true
    });

    await expect(control).toBeVisible();

    await control.click();

    await this.page
        .getByRole('option', {
            name: businessUnit,
            exact: true
        })
        .click();

}


async selectValOmegaLE(omegaLE: string): Promise<void> {

    const control = this.page.getByRole('combobox', {
        name: 'Valid for Omega LE',
        exact: true
    });

    await expect(control).toBeVisible();

    await control.click();

    await this.page
        .getByRole('option', {
            name: omegaLE,
            exact: true
        })
        .click();

}


async selectValOmegaICLE(omegaICLE: string): Promise<void> {

    const control = this.page.getByRole('combobox', {
        name: 'Valid for Omega IC LE?',
        exact: true
    });

    await expect(control).toBeVisible();

    await control.click();

    await this.page
        .getByRole('option', {
            name: omegaICLE,
            exact: true
        })
        .click();

}


async completeRequestEntry(request: RequestEntryDetails): Promise<void> {

    await this.selectLedgerNumber(request.ledgerNumberRow);

    await this.searchForNode(request.searchTerm);

    await this.selectSearchResult(request.searchResultRowText);

    await this.selectBusinessUnit(request.businessUnit);
}

async completeRequestOmegaICLE_LE(request: RequestEntryDetails): Promise<void> {

    await this.selectLedgerNumber(request.ledgerNumberRow);

    await this.searchForNode(request.searchTerm);

    await this.selectSearchResult(request.searchResultRowText);

    await this.selectBusinessUnit(request.businessUnit);
}


async dismissConcurrentDataUpdate(): Promise<void> {

    const dialog = this.page.getByRole('dialog', {
        name: 'Concurrent Data Update'
    });

    if (await dialog.count()) {
        await expect(dialog).toBeVisible();

        await dialog.getByRole('button', {
            name: 'OK'
        }).click();

        await expect(dialog).toBeHidden();
    }

}

async confirmSelection(): Promise<void> {

    await this.page.getByRole('button', {
        name: 'OK'
    }).click();

}

async submit(): Promise<void> {
    const submitButton = this.page.getByRole('button', {
        name: 'Submit'
    });
    await submitButton.click();

    await expect(
        submitButton
    ).toBeHidden();
}

async returnHome() {
    await this.page
        .getByRole('button', { name: 'Home' })
        .click();
}

//async done(): Promise<void> {

  //  const home = new Epm18testMainHomePage(this.page);
    //await home.epm18testhomeicon();
    
//}
}




