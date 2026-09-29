const { openVW, fields } = require('./vw');
(async () => { const { browser, page } = await openVW();
  await page.goto('https://vault.seed.example.com/#/login', { waitUntil: 'networkidle2' }); await new Promise(r => setTimeout(r, 2500));
  console.log((await fields(page)).join('\n'));
  console.log('all submit buttons:', JSON.stringify(await page.$$eval('button', bs => bs.map(b => ({ t: b.type, txt: b.innerText.trim().slice(0, 30), vis: b.offsetParent !== null })))));
  await browser.close(); })().catch(e => { console.error(e.message); process.exit(1); });
