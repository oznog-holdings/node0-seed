const { openVW } = require('./vw'); const { login, clickText } = require('./vw-login');
(async () => { const { browser, page } = await openVW(); await login(page);
  if (/setup-extension/.test(page.url())) await clickText(page, 'Add it later');
  await page.goto(`https://vault.seed.example.com/#/organizations/${process.env.OID}/members`, { waitUntil: 'networkidle2' });
  await clickText(page, 'Invite member'); await new Promise(r => setTimeout(r, 5000));
  await page.screenshot({ path: '/tmp/vw-invite.png' });
  console.log(await page.evaluate(() => [...document.querySelectorAll('dialog, [role=dialog], .cdk-overlay-pane, bit-dialog')].map(d => d.tagName + ' ' + d.className.toString().slice(0, 60)).join(' | ') || 'no dialog elements'));
  await browser.close(); })().catch(e => { console.error(e.message); process.exit(1); });
