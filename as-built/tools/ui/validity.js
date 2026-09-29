const { open, go } = require('./ui');
(async () => { const { browser, page } = await open();
  await go(page, `/Docker/AddContainer?xmlTemplate=${encodeURIComponent('user:/boot/config/plugins/dockerMan/templates-user/my-' + process.argv[2] + '.xml')}`);
  console.log(JSON.stringify(await page.evaluate(() => { const f = document.querySelector('form[onsubmit*=prepareConfig]');
    return { valid: f.checkValidity(), invalid: [...f.elements].filter(e => !e.checkValidity()).map(e => ({ n: e.name, id: e.id, v: e.value, msg: e.validationMessage, vis: !!(e.offsetWidth || e.offsetHeight) })) }; })));
  await browser.close(); })().catch(e => { console.error(e.message); process.exit(1); });
