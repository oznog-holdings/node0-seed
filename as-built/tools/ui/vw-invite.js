// Invite a member into the Seed organisation from the web vault's Members page.
// Env: MPW (builder's master password), OID (org id), EMAIL, COLLECTION (name), DRY=1 to stop before submit.
const { openVW } = require('./vw'); const { login, clickText } = require('./vw-login');
const dump = async (page) => page.$$eval('.cdk-overlay-container input, .cdk-overlay-container textarea, .cdk-overlay-container button, .cdk-overlay-container select, .cdk-overlay-container [role=tab]',
  es => es.filter(e => e.offsetParent !== null).map(e => `${e.tagName} type=${e.type || ''} id=${e.id} fc=${e.getAttribute('formcontrolname') || ''} txt=${(e.innerText || e.value || '').trim().slice(0, 40)}`));
(async () => {
  const { OID, EMAIL, COLLECTION, DRY } = process.env; const { browser, page } = await openVW(); await login(page);
  if (/setup-extension/.test(page.url())) await clickText(page, 'Add it later');
  await page.goto(`https://vault.seed.example.com/#/organizations/${OID}/members`, { waitUntil: 'networkidle2' });
  for (let i = 0; i < 5; i++) {
    await new Promise(r => setTimeout(r, 2000));
    await page.evaluate(() => [...document.querySelectorAll('button')].find(b => b.offsetParent !== null && b.innerText.trim() === 'Invite member').click());
    if (await page.waitForSelector('.cdk-overlay-container textarea, .cdk-overlay-container input[type=text]', { visible: true, timeout: 4000 }).catch(() => null)) { console.log('dialog open after try', i + 1); break; }
  }
  await new Promise(r => setTimeout(r, 1000));
  console.log('dialog controls:\n' + (await dump(page)).join('\n'));
  if (DRY) { await browser.close(); return; }
  const emails = await page.$('.cdk-overlay-container textarea[formcontrolname=emails], .cdk-overlay-container input[formcontrolname=emails]');
  await emails.type(EMAIL);
  // role: User (the default); collection access on the Collections tab
  await page.evaluate(() => { const t = [...document.querySelectorAll('.cdk-overlay-container [role=tab], .cdk-overlay-container button')].find(b => b.innerText.trim() === 'Collections'); t && t.click(); });
  await new Promise(r => setTimeout(r, 1000));
  console.log('collections tab:\n' + (await dump(page)).join('\n'));
  const pick = await page.$('.cdk-overlay-container input[role=combobox], .cdk-overlay-container bit-multi-select input');
  if (!pick) throw new Error('no collection picker');
  await pick.type(COLLECTION); await new Promise(r => setTimeout(r, 800)); await page.keyboard.press('Enter'); await new Promise(r => setTimeout(r, 800));
  const [resp] = await Promise.all([
    page.waitForResponse(r => /\/api\/organizations\/[^/]+\/users\/invite$/.test(r.url()) && r.request().method() === 'POST', { timeout: 30000 }),
    page.evaluate(() => [...document.querySelectorAll('.cdk-overlay-container button[type=submit]')].find(b => b.offsetParent !== null).click())]);
  const body = resp.request().postData(); const j = JSON.parse(body || '{}');
  console.log('POST invite', resp.status(), 'emails:', j.emails, 'type:', j.type, 'collections:', (j.collections || []).length, 'readOnly:', (j.collections || []).map(c => c.readOnly));
  await browser.close();
})().catch(e => { console.error(e.message); process.exit(1); });
