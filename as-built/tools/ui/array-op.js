// array-op.js stop|reboot: Unraid's Main page, the Unraid way: "stop" clicks Array Operation › Stop (stopArray:
// containers, VMs, then the array) and confirms Unraid's prompt; "reboot" submits the Reboot form as shutdown_now
// does (a clean system reset). It only clicks; the caller checks the outcome
// (mdState in /var/local/emhttp/var.ini, or infra answering again).
const { open, go } = require('./ui');
const op = process.argv[2];
const sel = { stop: 'form[name=arrayOps] input[type=button][value=Stop], form[name=arrayOps] button[value=Stop]',
              reboot: 'form[name=shutdownOps] input[name=reboot], form[name=shutdownOps] button[name=reboot]' }[op];
if (!sel) { console.error('array-op.js stop|reboot'); process.exit(64); }
(async () => { const { browser, page } = await open(); await go(page, '/Main');
  const b = await page.$(sel); if (!b) throw new Error(`no ${op} button on Main`);
  if (await page.evaluate(e => e.disabled, b)) throw new Error(`the ${op} button is disabled`);
  if (op === 'stop') {
    await b.click();
    // Unraid 7's confirmation: a SweetAlert box (its confirm button), when there is one
    const c = await page.waitForSelector('.sweet-alert.visible button.confirm, .swal2-confirm', { visible: true, timeout: 5000 }).catch(() => null);
    if (c) { await c.click(); console.log('stop: confirmed'); } else console.log('stop: clicked (no confirm box)');
    await new Promise(r => setTimeout(r, 5000));
  } else {
    // reboot: what shutdown_now(form,'reboot') does once confirmed: cmd=reboot added to shutdownOps and the form
    // submitted to Boot.php, kept open while its page runs the reboot (20261024: clicking the button did nothing,
    // twice; this did, at once)
    await Promise.all([page.waitForNavigation({ timeout: 30000 }).catch(e => console.log('nav:', e.message)),
      page.evaluate(() => { const f = document.forms.shutdownOps, i = document.createElement('input');
        i.type = 'hidden'; i.name = 'cmd'; i.value = 'reboot'; f.appendChild(i); f.submit(); })]);
    console.log('reboot: posted to', page.url());
    await new Promise(r => setTimeout(r, 90000));
  }
  await browser.close().catch(() => {}); })()
  .catch(e => { console.error(e.message); process.exit(1); });
