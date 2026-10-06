// Lists an existing VM's Edit form fields (VMs › <vm> › Edit): names, types, current values (no submit).
const { open, go } = require('./ui');
(async () => { const { browser, page } = await open(); await go(page, `/VMs/UpdateVM?uuid=${process.argv[2]}`);
  const f = await page.evaluate(() => [...document.querySelectorAll('form input, form select, form textarea')]
    .filter(e => e.name && e.type !== 'hidden' || /^(domain|disk|nic)\[/.test(e.name)).map(e => `${e.name}=${e.type === 'checkbox' ? e.checked : (e.tagName === 'SELECT' ? e.value + ' [' + [...e.options].map(o => o.value).slice(0, 10).join('|') + ']' : e.value)}`));
  console.log([...new Set(f)].join('\n'));
  console.log('buttons:', (await page.$$eval('input[type=button],input[type=submit],button', bs => bs.map(b => (b.value || b.innerText || '').trim()).filter(Boolean))).join(','));
  await browser.close(); })().catch(e => { console.error(e.message); process.exit(1); });
