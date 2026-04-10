const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

async function main() {
  const projectRoot = path.resolve(__dirname, '..');
  const profileDir = path.join(projectRoot, '.auth', 'playwright-chromium-operationhub');
  const resultsDir = path.join(projectRoot, 'results');
  const statePath = path.join(resultsDir, 'playwright-auth-browser.json');
  const url = process.argv[2] || 'https://operationhub.powerappsportals.com/southern-alberta';
  const port = Number(process.env.QFU_AUTH_BROWSER_PORT || 9333);

  fs.mkdirSync(profileDir, { recursive: true });
  fs.mkdirSync(resultsDir, { recursive: true });

  const context = await chromium.launchPersistentContext(profileDir, {
    headless: false,
    viewport: null,
    args: [
      '--start-maximized',
      `--remote-debugging-port=${port}`
    ]
  });

  const page = context.pages()[0] || await context.newPage();
  await page.goto(url, { waitUntil: 'domcontentloaded' });

  fs.writeFileSync(statePath, JSON.stringify({
    pid: process.pid,
    profileDir,
    url,
    port,
    startedAt: new Date().toISOString(),
    browser: 'playwright-chromium',
    note: 'Leave this Chromium window open after signing in so later Playwright launches can reuse the same profile and cookies while they remain valid.'
  }, null, 2));

  console.log(`OperationHub auth browser ready.`);
  console.log(`Profile: ${profileDir}`);
  console.log(`State: ${statePath}`);
  console.log(`CDP Port: ${port}`);
  console.log(`URL: ${url}`);

  await new Promise((resolve) => {
    const browser = context.browser();
    if (browser) {
      browser.on('disconnected', resolve);
    }
    context.on('close', resolve);
  });
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
