// Settings > Tailscale: the plugin's own subnet-route field and its Add button (Config.php add-route).
const { open, go } = require('./ui');
(async () => { const { browser, page } = await open(); await go(page, '/Settings/Tailscale');
  await page.waitForSelector('#tailscaleRoute', { timeout: 60000 });
  await page.evaluate(() => { const i = document.querySelector('#tailscaleRoute'); i.value = ''; });
  await page.type('#tailscaleRoute', process.argv[2]);
  await page.evaluate(() => { const i = document.querySelector('#tailscaleRoute'); i.dispatchEvent(new Event('input', { bubbles: true })); i.dispatchEvent(new Event('keyup', { bubbles: true })); i.dispatchEvent(new Event('change', { bubbles: true })); });
  const dis = await page.$eval('#addTailscaleRoute', b => b.disabled); console.log('add button disabled:', dis);
  await page.evaluate(() => document.querySelector('#addTailscaleRoute').click());
  await new Promise(r => setTimeout(r, 8000)); await browser.close();
})().catch(e => { console.error(e.message); process.exit(1); });
