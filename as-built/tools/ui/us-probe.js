const { open, go } = require('./ui');
(async () => { const { browser, page } = await open(); await go(page, '/Settings/Userscripts');
  console.log(JSON.stringify(await page.$$eval('select.schedule', ss => ss.map(s => ({ id: s.id, script: s.getAttribute('data-script') || s.name, val: s.value, opts: [...s.options].map(o => o.value) }))), null, 0));
  console.log(await page.$$eval('input[id^=customschedule], input[id^=customschedule] ~ input, input[id^=custom]', is => is.map(i => i.id).slice(0, 12).join(',')));
  await browser.close(); })().catch(e => { console.error(e.message); process.exit(1); });
