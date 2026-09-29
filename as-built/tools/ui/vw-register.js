// Register the invited builder account on the site's Vaultwarden. MPW comes from the environment (the vault item).
const { openVW } = require('./vw');
(async () => { const { browser, page } = await openVW(); const mpw = process.env.MPW; delete process.env.MPW;
  if (!mpw || mpw.length < 40) throw new Error('no master password in env');
  await page.goto('https://vault.seed.example.com/#/signup', { waitUntil: 'networkidle2' }); await new Promise(r => setTimeout(r, 2000));
  await page.type('#register-start_form_input_email', 'builder@seed.example.com'); await page.type('#register-start_form_input_name', 'seed builder');
  await page.click('button[type=submit]'); await page.waitForSelector('#input-password-form_new-password', { timeout: 20000 });
  await page.type('#input-password-form_new-password', mpw); await page.type('#input-password-form_new-password-confirm', mpw);
  const cb = await page.$('#input-password-form_check-for-breaches'); if (await cb.evaluate(e => e.checked)) await cb.click();
  console.log('breach check:', await cb.evaluate(e => e.checked));
  const [resp] = await Promise.all([page.waitForResponse(r => /identity\/accounts\/register/.test(r.url()) && r.request().method() === 'POST', { timeout: 60000 }),
    (await page.$$('button[type=submit]')).slice(-1)[0].click()]);
  console.log('register POST:', resp.status(), resp.url().replace(/^https:\/\/[^/]+/, ''));
  await new Promise(r => setTimeout(r, 4000)); console.log('now at:', page.url().split('?')[0]); await browser.close();
})().catch(e => { console.error(e.message); process.exit(1); });
