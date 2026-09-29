// Helpers for the Vaultwarden web vault (headless Chromium, resolving vault.seed.example.com to infra).
const puppeteer = require('puppeteer-core');
async function openVW() {
  const browser = await puppeteer.launch({ executablePath: process.env.CHROMIUM, headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage', '--host-resolver-rules=MAP vault.seed.example.com 192.168.1.10'] });
  const page = await browser.newPage(); await page.setViewport({ width: 1300, height: 1000 });
  return { browser, page };
}
async function fields(page) {
  return page.$$eval('input,button,a[href*="#"]', es => es.filter(e => e.offsetParent !== null).map(e =>
    `${e.tagName.toLowerCase()}${e.type ? '[' + e.type + ']' : ''} id=${e.id} name=${e.name || ''} fc=${e.getAttribute('formcontrolname') || ''} txt=${(e.innerText || e.value || '').trim().slice(0, 40)}`));
}
module.exports = { openVW, fields };
