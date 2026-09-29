// Settings > Docker, through the page itself: enabled, directory (not docker.img), overlay2, appdata on the pool.
const { open, go } = require('./ui');
(async () => { const { browser, page } = await open(); await go(page, '/Settings/DockerSettings');
  await page.select('#DOCKER_ENABLED', 'yes');
  await page.select('#DOCKER_IMAGE_TYPE', 'folder');              // fires updateLocation()
  const f2 = await page.$('#DOCKER_IMAGE_FILE2'); await page.evaluate(e => { e.disabled = false; e.value = ''; }, f2);
  await f2.type('/mnt/data/system/docker/'); await page.evaluate(e => e.dispatchEvent(new Event('change', { bubbles: true })), f2);
  await page.select('#DOCKER_BACKINGFS', 'overlay2');
  const ap = await page.$('#DOCKER_APP_CONFIG_PATH'); await page.evaluate(e => e.value = '', ap); await ap.type('/mnt/data/appdata/');
  await page.evaluate(e => e.dispatchEvent(new Event('change', { bubbles: true })), ap);
  const st = await page.evaluate(() => Object.fromEntries(['DOCKER_ENABLED','DOCKER_IMAGE_TYPE','DOCKER_IMAGE_FILE2','DOCKER_BACKINGFS','DOCKER_APP_CONFIG_PATH'].map(i => [i, document.getElementById(i).value]).concat([['applyDisabled', document.getElementById('applyBtn').disabled]])));
  console.log('form:', JSON.stringify(st));
  const onclick = await page.$eval('#applyBtn', b => b.getAttribute('onclick') || '(handler bound in js)'); console.log('apply:', onclick.slice(0, 120));
  await page.click('#applyBtn');
  await new Promise(r => setTimeout(r, 25000)); await browser.close();
})().catch(e => { console.error(e.message); process.exit(1); });
