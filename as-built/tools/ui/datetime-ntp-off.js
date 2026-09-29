// Settings > Date and Time: "Use NTP" off, so chrony (container, host network) can hold UDP 123
// and keep infra's clock. Time zone and everything else unchanged.
const { open, go } = require('./ui');
(async () => { const { browser, page } = await open(); await go(page, '/Settings/DateTime');
  const opts = await page.$$eval('select[name="USE_NTP"] option', os => os.map(o => `${o.value}=${o.textContent.trim()}`)); console.log('USE_NTP options:', opts.join(' | '));
  await page.select('select[name="USE_NTP"]', 'no');
  const btn = await page.$('form[name="datetime_settings"] input[type="button"][value="Apply"]');
  console.log('apply enabled:', await page.evaluate(b => b && !b.disabled, btn));
  await Promise.all([page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 60000 }).catch(() => null), btn.click()]);
  await new Promise(r => setTimeout(r, 4000)); await go(page, '/Settings/DateTime');
  console.log('read back USE_NTP:', await page.$eval('select[name="USE_NTP"]', s => s.value)); await browser.close();
})().catch(e => { console.error(e.message); process.exit(1); });
