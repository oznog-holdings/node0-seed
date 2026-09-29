const { openVW, fields } = require('./vw');
(async () => { const { browser, page } = await openVW();
  await page.goto('https://vault.seed.example.com/#/signup', { waitUntil: 'networkidle2' }); await new Promise(r => setTimeout(r, 3000));
  console.log('url', page.url()); console.log((await fields(page)).join('\n')); await page.screenshot({ path: '/tmp/vw-signup.png' }); await browser.close();
})().catch(e => { console.error(e.message); process.exit(1); });
