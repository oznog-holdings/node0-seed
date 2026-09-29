// VMs › Add VM › Linux, filled from a JSON spec and submitted with the page's own Create button.
// Spec: {name, desc, storage, vcpus, pin:[threads], mem (KiB), disk (path), driver, network}
const { open, go, mask } = require('./ui');
const s = JSON.parse(process.argv[2]);
(async () => { const { browser, page } = await open(); await go(page, '/VMs/AddVM?template=Linux');
  await page.evaluate(s => {
    const set = (n, v) => { const e = document.querySelector(`[name="${n}"]`); e.value = v; e.dispatchEvent(new Event('change', { bubbles: true })); };
    set('domain[name]', s.name); set('domain[desc]', s.desc); set('template[storage]', s.storage);
    document.querySelectorAll('input[name="domain[vcpu][]"]').forEach(c => { c.checked = s.pin.includes(+c.value); c.dispatchEvent(new Event('change', { bubbles: true })); });
    set('domain[mem]', s.mem); set('domain[maxmem]', s.mem);
    set('disk[0][select]', 'manual'); set('disk[0][new]', s.disk); set('disk[0][driver]', s.driver); set('disk[0][bus]', 'virtio');
    set('nic[0][network]', s.network);
    const sn = document.querySelector('[name="domain[startnow]"]'); if (sn) { sn.checked = false; sn.value = 0; }
    const au = document.querySelector('[name="domain[autostart]"]'); if (au) au.value = 'false';
  }, s);
  const got = await page.evaluate(() => Object.fromEntries(['domain[name]', 'template[storage]', 'domain[vcpus]', 'domain[mem]', 'disk[0][select]', 'disk[0][new]', 'disk[0][driver]', 'nic[0][network]', 'domain[autostart]']
    .map(n => [n, document.querySelector(`[name="${n}"]`)?.value])));
  got.pinned = await page.$$eval('input[name="domain[vcpu][]"]:checked', cs => cs.map(c => c.value)); console.log('form:', JSON.stringify(got));
  const btn = (await page.$$('input[type=button],input[type=submit],button')).length; 
  const labels = await page.$$eval('input[type=button],input[type=submit],button', bs => bs.map(b => (b.value || b.innerText || '').trim()).filter(Boolean)); console.log('buttons:', labels.join(','));
  await Promise.all([page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 120000 }).catch(e => console.log('nav:', e.message)),
    page.evaluate(() => { const b = [...document.querySelectorAll('input[type=button],input[type=submit],button')].find(x => /^create$/i.test((x.value || x.innerText || '').trim())); b.click(); })]);
  await new Promise(r => setTimeout(r, 3000));
  console.log('after:', page.url(), mask((await page.evaluate(() => document.body.innerText)).split('\n').filter(l => /error|success|sandbox/i.test(l)).slice(0, 6).join(' | ')));
  await browser.close(); })().catch(e => { console.error(e.message); process.exit(1); });
