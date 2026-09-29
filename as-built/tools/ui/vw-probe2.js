const { openVW, fields } = require('./vw');
(async () => { const { browser, page } = await openVW();
  await page.goto('https://vault.seed.example.com/#/signup', { waitUntil: 'networkidle2' }); await new Promise(r => setTimeout(r, 2000));
  await page.type('#register-start_form_input_email', 'builder@seed.example.com'); await page.type('#register-start_form_input_name', 'seed builder');
  await page.click('button[type=submit]'); await new Promise(r => setTimeout(r, 5000));
  console.log('url', page.url().replace(/token=[^&]+/, 'token=<x>')); console.log((await fields(page)).join('\n'));
  console.log((await page.evaluate(() => document.body.innerText)).slice(0, 600)); await browser.close();
})().catch(e => { console.error(e.message); process.exit(1); });
