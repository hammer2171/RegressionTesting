import { test } from './fixtures/authFixture';

import { Epm18testMainHomePage } from '../pages/Epm18testMainHomePage';
import { ViewsPage } from '../pages/ViewsPage';
import { RequestPage } from '../pages/RequestPage';
import { PropertyGrid } from '../pages/PropertyGrid';

test.use({
    viewport: {
        width: 1366,
        height: 900
    }
});



const request = {

    view: 'A_Entry_Entity',

    viewpoint: 'Input_EPM_Entity_Base',

    ledgerNumber: '0940',

    businessUnit: 'EE - Renewables'

};

test('Request New Base Member Entity', async ({ page }) => {

    await page.goto(
        'https://epm18-test-a706571.epm.us2.oraclecloud.com/epm'
    );

    const home = new Epm18testMainHomePage(page);

    const views = new ViewsPage(page);

    const requestPage = new RequestPage(page);

    const propertyGrid = new PropertyGrid(page);

    //---------------------------------------------------------------------
    // Navigation
    //---------------------------------------------------------------------

    await home.open();

    await views.open();

    await views.openView(request.view);

    await views.openViewpoint(request.viewpoint);

    //---------------------------------------------------------------------
    // Request
    //---------------------------------------------------------------------

    await requestPage.newRequest();

    await requestPage.addNode();

    //---------------------------------------------------------------------
    // Ledger Selection
    //---------------------------------------------------------------------

    await page
        .getByRole('textbox', {
            name: 'Search for a node'
        })
        .fill(request.ledgerNumber);

    await page
        .getByRole('textbox', {
            name: 'Search for a node'
        })
        .press('Enter');

    //---------------------------------------------------------------------
    // Business Unit
    //---------------------------------------------------------------------

    await propertyGrid.setComboBox(
        'Business Unit',
        request.businessUnit
    );

    //---------------------------------------------------------------------
    // Submit
    //---------------------------------------------------------------------

    await requestPage.submit();

    await requestPage.returnHome();

});