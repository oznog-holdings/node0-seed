// Settings > UPS Settings through the page: apcupsd on, USB, shut down at 25% or 10 min left.
// 25% from 20260927, the owner's choice through the UI (apcupsd MBATTCHG 25); it was 50%.
const { open, go } = require('./ui');
(async () => { const { browser, page } = await open(); await go(page, '/Settings/UPSsettings');
  await page.select('select[name=SERVICE]', 'enable'); await page.select('select[name=UPSCABLE]', 'usb'); await page.select('select[name=UPSTYPE]', 'usb');
  for (const [n, v] of [['BATTERYLEVEL', '25'], ['MINUTES', '10'], ['TIMEOUT', '0']]) { const e = await page.$(`input[name=${n}]`); await page.evaluate(x => x.value = '', e); await e.type(v); await page.evaluate(x => x.dispatchEvent(new Event('change', { bubbles: true })), e); }
  await page.select('select[name=KILLUPS]', 'no');
  const b = await page.$('form[name=apcupsd_settings] input[name="#apply"]'); console.log('apply enabled:', await page.evaluate(x => !x.disabled, b));
  await Promise.all([page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 60000 }).catch(() => null), b.click()]);
  await new Promise(r => setTimeout(r, 8000)); await browser.close(); })().catch(e => { console.error(e.message); process.exit(1); });
