// Log the builder into the web vault. MPW from env.
async function clickText(page, text) {
  await page.waitForFunction(t => [...document.querySelectorAll("button")].some(b => b.offsetParent !== null && b.innerText.trim() === t), { timeout: 15000 }, text).catch(() => {});
  const h = await page.evaluateHandle(t => [...document.querySelectorAll("button")].find(b => b.offsetParent !== null && b.innerText.trim() === t), text);
  if (!h.asElement()) throw new Error('no visible button: ' + text); await h.asElement().click();
}
async function login(page) { const mpw = process.env.MPW; delete process.env.MPW;
  await page.goto('https://vault.seed.example.com/#/login', { waitUntil: 'networkidle2' });
  await page.waitForSelector('input#email'); await page.type('input#email', 'builder@seed.example.com'); await clickText(page, 'Continue');
  await page.waitForSelector('input[type=password]', { visible: true, timeout: 20000 }); await page.type('input[type=password]', mpw);
  await Promise.all([page.waitForFunction(() => /#\/(vault|setup)/.test(location.hash), { timeout: 60000 }), clickText(page, 'Log in')]);
}
module.exports = { login, clickText };
