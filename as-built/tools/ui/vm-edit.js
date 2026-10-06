// VMs › <vm> › Edit: sets the fields in a JSON spec and submits with the page's own Update button.
// Spec: {uuid, pin:[threads], mem (KiB, also the max), disk (path), driver}; other fields untouched.
const { open, go, mask } = require('./ui');
const s = JSON.parse(process.argv[2]);
(async () => { const { browser, page } = await open(); await go(page, `/VMs/UpdateVM?uuid=${s.uuid}`);
  const miss = await page.evaluate(s => {
    const set = (n, v) => { const e = document.querySelector(`[name="${n}"]`); if (e.tagName === 'SELECT' && ![...e.options].some(o => o.value == v)) return n;
      e.value = v; e.dispatchEvent(new Event('change', { bubbles: true })); };
    const bad = [];
    document.querySelectorAll('input[name="domain[vcpu][]"]').forEach(c => { c.checked = s.pin.includes(+c.value); c.dispatchEvent(new Event('change', { bubbles: true })); });
    [set('domain[mem]', s.mem), set('domain[maxmem]', s.mem), set('disk[0][new]', s.disk), set('disk[0][driver]', s.driver)].forEach(x => x && bad.push(x));
    return bad;
  }, s);
  if (miss.length) { console.log('no such option for:', miss.join(',')); await browser.close(); process.exit(1); }
  const got = await page.evaluate(() => Object.fromEntries(['domain[vcpus]', 'domain[mem]', 'domain[maxmem]', 'disk[0][new]', 'disk[0][driver]', 'domain[autostart]', 'domain[cpumode]']
    .map(n => [n, document.querySelector(`[name="${n}"]`)?.value])));
  got.pinned = await page.$$eval('input[name="domain[vcpu][]"]:checked', cs => cs.map(c => c.value)); console.log('form:', JSON.stringify(got));
  await Promise.all([page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 120000 }).catch(e => console.log('nav:', e.message)),
    page.evaluate(() => { const b = [...document.querySelectorAll('input[type=button],input[type=submit],button')].find(x => /^update$/i.test((x.value || x.innerText || '').trim())); b.click(); })]);
  await new Promise(r => setTimeout(r, 3000));
  console.log('after:', page.url(), mask((await page.evaluate(() => document.body.innerText)).split('\n').filter(l => /error|fail/i.test(l)).slice(0, 6).join(' | ')));
  await browser.close(); })().catch(e => { console.error(e.message); process.exit(1); });
