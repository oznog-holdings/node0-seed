const { openVW } = require('./vw');
(async () => { const { browser, page } = await openVW(); const hits = [];
  page.on('response', r => { if (/identity\/accounts\/register/.test(r.url())) hits.push(r.status() + ' ' + r.url().replace(/^https:\/\/[^/]+/, '')); });
  await page.goto('https://vault.seed.example.com/#/signup', { waitUntil: 'networkidle2' }); await new Promise(r => setTimeout(r, 1500));
  await page.type('#register-start_form_input_email', 'not-invited@example.com'); await page.type('#register-start_form_input_name', 'x');
  await page.click('button[type=submit]'); await new Promise(r => setTimeout(r, 5000));
  console.log('responses:', hits.join(' | ')); console.log('url:', page.url().split('?')[0]);
  const t = await page.evaluate(() => document.body.innerText); console.log('page says:', (t.match(/[^\n]*(not allowed|disabled|invit|error)[^\n]*/i) || ['(no message)'])[0]);
  await browser.close(); })().catch(e => { console.error(e.message); process.exit(1); });
