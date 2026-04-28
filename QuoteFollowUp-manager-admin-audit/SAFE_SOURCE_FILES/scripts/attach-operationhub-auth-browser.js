const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

async function main() {
  const projectRoot = path.resolve(__dirname, '..');
  const statePath = path.join(projectRoot, 'results', 'playwright-auth-browser.json');

  if (!fs.existsSync(statePath)) {
    throw new Error(`Auth browser state file not found at ${statePath}. Start the browser first.`);
  }

  const state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
  const port = Number(state.port || process.env.QFU_AUTH_BROWSER_PORT || 9333);
  const endpoint = `<URL>
  const url = process.argv[2] || '';

  const browser = await chromium.connectOverCDP(endpoint);
  const context = browser.contexts()[0] || await browser.newContext();
  const page = context.pages()[0] || await context.newPage();

  if (url) {
    await page.goto(url, { waitUntil: 'domcontentloaded' });
  }

  console.log(JSON.stringify({
    endpoint,
    pageTitle: await page.title(),
    pageUrl: page.url()
  }, null, 2));

  await browser.close();
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
