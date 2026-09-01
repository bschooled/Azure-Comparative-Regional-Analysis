const { test, expect } = require('@playwright/test');

const pricingItem = {
  sourceAvailable: true,
  targetAvailable: true,
  sourceRetailPrice: 10.25,
  targetRetailPrice: 11.75,
  sourceCurrencyCode: 'USD',
  targetCurrencyCode: 'USD',
  sourceUnitOfMeasure: '1 Hour',
  targetUnitOfMeasure: '1 Hour',
  sourcePriceType: 'Consumption',
  targetPriceType: 'Consumption',
  meterName: 'Dsv5 Series Linux',
  skuName: 'Standard_D128ds_v5',
};

const details = {
  layout: 'family-breakdown',
  families: [{
    family: 'Dsv5',
    sourceCount: 1,
    targetCount: 1,
    sourceDeployableCount: 1,
    targetDeployableCount: 1,
    pricing: pricingItem,
    pricingDetails: {
      kind: 'vm',
      rowCount: 1,
      models: [{ key: 'payg', title: 'Pay as you go' }],
      rows: [{
        key: 'standard-d128ds-v5',
        sku: 'Standard_D128ds_v5_Extended_Readability_Example',
        offers: { payg: pricingItem },
      }],
    },
  }],
};

test.beforeEach(async ({ page }) => {
  await page.route('**/api/**', async (route) => {
    const path = new URL(route.request().url()).pathname;
    const payload = path === '/api/session'
      ? { user: { name: 'Pricing Tester' }, defaults: { comparisonMode: 'provider', sourceRegion: 'eastus', targetRegion: 'westus2' } }
      : path === '/api/health'
        ? { status: 'Healthy', latestRunStatus: 'Completed' }
        : path === '/api/runs'
          ? { items: [] }
          : {
              metadata: { latestRunId: 'pricing-responsive-test' },
              items: [{
                row_key: 'pricing-responsive-test',
                service: 'Virtual Machines',
                provider: 'Microsoft.Compute',
                service_family: 'Compute',
                availability: 'FULL_MATCH',
                source_region: 'eastus',
                target_region: 'westus2',
                details_json: JSON.stringify(details),
              }],
            };

    await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(payload) });
  });
});

test('pricing dialog fits a mobile viewport and closes with Escape', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/');
  await page.getByRole('tab', { name: 'Results' }).click();
  await page.getByText('Virtual Machines', { exact: true }).click();
  await page.getByRole('button', { name: 'View pricing' }).click();

  const dialog = page.getByRole('dialog');
  await expect(dialog).toBeVisible();
  await expect(dialog.getByText('Standard_D128ds_v5_Extended_Readability_Example')).toBeVisible();

  const bounds = await dialog.boundingBox();
  expect(bounds.width).toBeLessThanOrEqual(390);
  expect(bounds.height).toBeLessThanOrEqual(844);
  expect(await dialog.evaluate((element) => element.scrollWidth <= element.clientWidth)).toBe(true);

  await page.keyboard.press('Escape');
  await expect(dialog).toBeHidden();
  await expect(page.getByRole('button', { name: 'View pricing' })).toBeFocused();
});
