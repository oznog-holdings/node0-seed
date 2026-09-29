// Headless Chromium on the Unraid UI, reusing the curl login's session cookie
// (~/.local/state/seed/unraid/cookies), so no password ever reaches this process.
const fs = require('fs'), path = require('path'), puppeteer = require('puppeteer-core');
const BASE = 'http://192.168.1.10';
const JAR = path.join(process.env.HOME, '.local/state/seed/unraid/cookies');
async function open() {
  const browser = await puppeteer.launch({ executablePath: process.env.CHROMIUM, headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'], userDataDir: path.join(__dirname, 'profile') });
  const page = await browser.newPage();
  await page.setViewport({ width: 1400, height: 1000 });
  const cookies = fs.readFileSync(JAR, 'utf8').split('\n').filter(l => l && (!l.startsWith('#') || l.startsWith('#HttpOnly_')))
    .map(l => l.replace(/^#HttpOnly_/, '').split('\t')).filter(f => f.length >= 7)
    .map(f => ({ name: f[5], value: f[6], domain: f[0], path: f[2], httpOnly: true }));
  await browser.setCookie(...cookies);
  page.on('dialog', async d => { console.log('dialog:', d.type(), d.message().slice(0, 200)); await d.accept(); });
  return { browser, page };
}
async function go(page, p) {
  await page.goto(BASE + p, { waitUntil: 'networkidle2', timeout: 60000 });
  if (page.url().includes('/login')) throw new Error('session expired: run tools/unraid-login.sh');
}
const mask = s => String(s).replace(/csrf_token=[0-9A-Fa-f]+/g, 'csrf_token=<x>');
module.exports = { open, go, mask, BASE };
