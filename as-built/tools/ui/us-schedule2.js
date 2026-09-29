// User Scripts: set custom cron schedules on the page itself, then its Apply.
const { open, go } = require('./ui');
const want = JSON.parse(process.argv[2]);
(async () => { const { browser, page } = await open(); await go(page, '/Settings/Userscripts');
  for (const [n, cron] of Object.entries(want)) {
    await page.select(`#schedule${n}`, 'custom');
    const inp = await page.$(`#customschedule${n}`); await inp.click({ clickCount: 3 }).catch(() => {}); await page.evaluate(e => e.value = '', inp); await inp.type(cron);
    await page.evaluate(e => e.dispatchEvent(new Event('change', { bubbles: true })), inp);
  }
  console.log('apply enabled:', await page.$eval('#applyButton', b => !b.disabled));
  await page.evaluate(() => applySchedule()); await new Promise(r => setTimeout(r, 4000)); await browser.close();
})().catch(e => { console.error(e.message); process.exit(1); });
