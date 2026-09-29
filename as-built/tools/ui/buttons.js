const { open, go } = require('./ui');
(async () => { const { browser, page } = await open(); await go(page, process.argv[2]);
  console.log(JSON.stringify(await page.$$eval('input[type=submit],input[type=button],button', bs => bs.map(b => ({ t: b.type, v: b.value || b.textContent.trim(), n: b.name, form: b.form && (b.form.name || b.form.id), dis: b.disabled, oc: (b.getAttribute('onclick')||'').slice(0,80) })))));
  await browser.close(); })().catch(e => { console.error(e.message); process.exit(1); });
