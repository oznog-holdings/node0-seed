// Settings > Disk Settings: "Enable auto start" = Yes; nothing else changed. The page's own Apply.
const { open, go } = require('./ui');
(async () => { const { browser, page } = await open(); await go(page, '/Settings/DiskSettings');
  const before = await page.$$eval('form[action="/update.htm"] select, form[action="/update.htm"] input', es => es.filter(e => e.name && e.type !== 'submit').map(e => `${e.name}=${e.value}`).join('&'));
  await page.select('select[name=startArray]', 'yes');
  const btn = await page.$('input[name=changeDisk]'); console.log('apply enabled:', await page.evaluate(b => !b.disabled, btn));
  await Promise.all([page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 60000 }).catch(() => null), btn.click()]);
  await new Promise(r => setTimeout(r, 3000)); await go(page, '/Settings/DiskSettings');
  const after = await page.$$eval('form[action="/update.htm"] select, form[action="/update.htm"] input', es => es.filter(e => e.name && e.type !== 'submit').map(e => `${e.name}=${e.value}`).join('&'));
  const b = new Map(before.split('&').map(x => x.split('='))), a = new Map(after.split('&').map(x => x.split('=')));
  console.log('changed fields:', [...a].filter(([k, v]) => b.get(k) !== v).map(([k, v]) => `${k}: ${b.get(k)} -> ${v}`).join('; ') || 'none');
  await browser.close(); })().catch(e => { console.error(e.message); process.exit(1); });
