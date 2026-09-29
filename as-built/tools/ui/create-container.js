// Docker > Add Container with a template already in templates-user, then the page's own Apply,
// so Unraid's CreateDocker.php builds and runs the command from its own model.
const { open, go, mask } = require('./ui');
const name = process.argv[2];
(async () => { const { browser, page } = await open();
  await go(page, `/Docker/AddContainer?xmlTemplate=${encodeURIComponent('user:/boot/config/plugins/dockerMan/templates-user/my-' + name + '.xml')}`);
  const f = await page.evaluate(() => ({ name: document.querySelector('input[name=contName]').value, repo: document.querySelector('input[name=contRepository]').value,
    net: document.querySelector('select[name=contNetwork]').value, extra: document.querySelector('input[name=contExtraParams]').value, post: document.querySelector('input[name=contPostArgs]').value }));
  console.log('form:', JSON.stringify(f));
  const btns = await page.$$eval('input[type=submit],input[type=button]', bs => bs.map(b => b.value)); console.log('buttons:', btns.join(','));
  await Promise.all([page.waitForNavigation({ waitUntil: "networkidle2", timeout: 300000 }).catch(e => console.log("nav:", e.message)),
    page.evaluate(() => { const f = document.querySelector("form[onsubmit*=prepareConfig]"); const b = [...f.querySelectorAll("input[type=submit]")].find(x => x.value.trim() === "Apply"); f.requestSubmit(b); })]);
  await new Promise(r => setTimeout(r, 3000));
  const out = await page.evaluate(() => document.body.innerText); console.log(mask(out).split('\n').filter(l => /docker (run|create)|The command|finished|error|Error|success/i.test(l)).slice(0, 12).join('\n'));
  await browser.close(); })().catch(e => { console.error(e.message); process.exit(1); });
