const { openVW, fields } = require('./vw'); const { login } = require('./vw-login');
(async () => { const { browser, page } = await openVW(); await login(page); console.log('logged in at', page.url());
  await page.goto('https://vault.seed.example.com/#/create-organization', { waitUntil: 'networkidle2' }); await new Promise(r => setTimeout(r, 3000));
  console.log('url', page.url()); console.log((await fields(page)).join('\n')); console.log((await page.evaluate(() => document.body.innerText)).slice(0, 700)); await browser.close();
})().catch(e => { console.error(e.message); process.exit(1); });
