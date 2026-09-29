const { openVW } = require('./vw'); const { login } = require('./vw-login');
(async () => { const { browser, page } = await openVW(); await login(page);
  await page.goto('https://vault.seed.example.com/#/create-organization', { waitUntil: 'networkidle2' });
  await page.waitForSelector('input[formcontrolname=name]', { visible: true }); await page.type('input[formcontrolname=name]', 'Seed');
  const [resp] = await Promise.all([page.waitForResponse(r => /\/api\/organizations$/.test(r.url()) && r.request().method() === 'POST', { timeout: 60000 }),
    page.$$eval('button[type=submit]', bs => bs.filter(b => b.offsetParent !== null && b.innerText.trim() === 'Submit')[0].click())]);
  const j = await resp.json().catch(() => ({})); console.log('POST /api/organizations', resp.status(), 'name:', j.name, 'id:', (j.id || '').slice(0, 8) + '…');
  await new Promise(r => setTimeout(r, 3000)); await browser.close();
})().catch(e => { console.error(e.message); process.exit(1); });
