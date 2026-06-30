import { test } from '@playwright/test';

import { Epm18testMainHomePage } from '../pages/Epm18testMainHomePage';
import { ViewsPage } from '../pages/ViewsPage';
import { RequestPage } from '../pages/RequestPage';

test.use({
  storageState: 'playwright/.auth/user.epm18_test.json'
});

test.use({ viewport: { width: 1366, height: 900 } });

const linkName: { tilename: string } = { tilename: 'Views' };

const request = {
  viewName: 'A_Entry_Entity',
  viewpointName: 'Input_EPM_Entity_Base',
  ledgerNumberRow: '3010LE (NOV Inc.)',
  searchTerm: '0940',
  searchResultRowText: '0940 (National Oilwell Varco, L.P. (EE-Branch))',
  businessUnit: 'EP - WellSite Services'
};

test('test', async ({ page }) => {
  const home = new Epm18testMainHomePage(page);
  const views = new ViewsPage(page);
  const requestPage = new RequestPage(page);

  await home.open();

  await home.epm18testtilesopen(linkName.tilename);
  
  await views.openView(request.viewName);

  await views.openViewpoint(request.viewpointName);

  await requestPage.newRequest();

  await requestPage.addNode();

  await requestPage.completeRequestEntry(request);

  await requestPage.submit();

  await requestPage.returnHome();

  
});