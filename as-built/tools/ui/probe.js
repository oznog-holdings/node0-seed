const { open, go } = require('./ui');
(async () => { const { browser, page } = await open(); await go(page, '/Main'); console.log('title:', await page.title(), 'url:', page.url()); await browser.close(); })().catch(e => { console.error(e.message); process.exit(1); });
