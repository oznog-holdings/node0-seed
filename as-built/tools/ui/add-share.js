// Shares > Add Share, through the page's own form: name, comment, primary storage = data pool.
const { open, go } = require('./ui');
const [name, comment] = process.argv.slice(2);
(async () => { const { browser, page } = await open(); await go(page, '/Shares/Share?name=');
  await page.type('input[name="shareName"]', name); await page.type('input[name="shareComment"]', comment);
  await page.select('select[name="shareCachePool"]', 'data');
  const state = await page.evaluate(() => ({ pool: document.querySelector('select[name="shareCachePool"]').value, use: document.querySelector('input[name="shareUseCache"]').value, btn: document.querySelector('input[name="cmdEditShare"]').disabled }));
  console.log('before submit:', JSON.stringify(state));
  await Promise.all([page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 60000 }).catch(() => null), page.click('input[name="cmdEditShare"]')]);
  await new Promise(r => setTimeout(r, 4000)); console.log('after: url', page.url()); await browser.close();
})().catch(e => { console.error(e.message); process.exit(1); });
