// Lists the Add VM (Linux) form's fields: names, types, current values (no submit).
const { open, go } = require('./ui');
(async () => { const { browser, page } = await open(); await go(page, '/VMs/AddVM?template=Linux');
  const f = await page.evaluate(() => [...document.querySelectorAll('form#vmform input, form#vmform select, form#vmform textarea, form input, form select')]
    .filter(e => e.name).map(e => `${e.name}=${e.type === 'checkbox' ? e.checked : (e.tagName === 'SELECT' ? e.value + ' [' + [...e.options].map(o => o.value).slice(0, 8).join('|') + ']' : e.value)}`));
  console.log([...new Set(f)].join('\n')); await browser.close(); })().catch(e => { console.error(e.message); process.exit(1); });
