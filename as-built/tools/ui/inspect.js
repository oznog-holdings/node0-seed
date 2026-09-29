const { open, go } = require('./ui');
(async () => { const { browser, page } = await open(); await go(page, process.argv[2]);
  const info = await page.evaluate((sel) => [...document.querySelectorAll(sel || 'form')].map(f => ({ action: f.getAttribute('action'), name: f.name||f.id,
    fields: [...f.elements].filter(e => e.name && !/csrf/.test(e.name)).map(e => `${e.name}${e.disabled?'(dis)':''}${e.type==='hidden'?'(h)':''}=${e.tagName==='SELECT' ? e.value+' ['+[...e.options].map(o=>o.value).slice(0,8).join('|')+']' : (e.type==='password'?'<pw>':String(e.value).slice(0,60))}`) })), process.argv[3]);
  console.log(JSON.stringify(info, null, 1)); await browser.close(); })().catch(e => { console.error(e.message); process.exit(1); });
