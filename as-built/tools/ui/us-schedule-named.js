// User Scripts: set a named schedule (start, stop, boot, hourly, daily, ...) on the page, then Apply.
const { open, go } = require('./ui');
const want = JSON.parse(process.argv[2]);
(async () => { const { browser, page } = await open(); await go(page, '/Settings/Userscripts');
  for (const [n, v] of Object.entries(want)) { await page.select(`#schedule${n}`, v); await page.evaluate(n => { try { changeApply(n); } catch (e) {} }, n); }
  console.log('apply enabled:', await page.$eval('#applyButton', b => !b.disabled));
  await page.evaluate(() => applySchedule()); await new Promise(r => setTimeout(r, 4000)); await browser.close();
})().catch(e => { console.error(e.message); process.exit(1); });
