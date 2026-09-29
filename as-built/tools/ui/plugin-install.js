// Plugins > Install Plugin: the URL into the page's own form, then its Install button.
const { open, go } = require('./ui');
(async () => { const { browser, page } = await open(); await go(page, '/Plugins/PluginInstall');
  await page.type('form[name=plugin_install] input[name=file]', process.argv[2]);
  const btns = await page.$$eval('form[name=plugin_install] input[type=button], form[name=plugin_install] input[type=submit], form[name=plugin_install] button', bs => bs.map(b => (b.value || b.innerText).trim())); console.log('buttons:', btns.join(','));
  await page.evaluate(() => { const f = document.forms['plugin_install']; const b = [...f.querySelectorAll('input[type=button],input[type=submit],button')].find(x => /install/i.test(x.value || x.innerText)); b.click(); });
  await new Promise(r => setTimeout(r, 60000)); await browser.close();
})().catch(e => { console.error(e.message); process.exit(1); });
