async page => {
  await page.waitForLoadState('networkidle');
  await page.getByRole('link', { name: 'Views' }).waitFor({ state: 'visible' });
  return await page.locator('body').innerText();
}
