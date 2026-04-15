const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

function getArg(name, fallback) {
  const prefix = `--${name}=`;
  const match = process.argv.find((arg) => arg.startsWith(prefix));
  return match ? match.slice(prefix.length) : fallback;
}

function ensureDir(targetPath) {
  fs.mkdirSync(targetPath, { recursive: true });
}

function parseRoutes(value) {
  return String(value || "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

async function main() {
  const baseUrl = getArg("baseUrl", "https://quoteoperations.powerappsportals.com");
  const routes = parseRoutes(getArg("routes", "/,/southern-alberta/,/southern-alberta/4171-calgary/"));
  const outputDir = path.resolve(getArg("outputDir", "output/playwright"));
  const authState = getArg("authState", "");
  const headed = process.argv.includes("--headed");
  ensureDir(outputDir);

  const browser = await chromium.launch({ headless: !headed });
  const context = await browser.newContext(authState && fs.existsSync(authState) ? { storageState: authState } : {});
  const page = await context.newPage();
  const results = [];

  for (const route of routes) {
    const url = new URL(route, baseUrl).toString();
    const response = await page.goto(url, { waitUntil: "domcontentloaded", timeout: 90000 });
    await page.waitForTimeout(1500);
    const bodyText = await page.evaluate(() => document.body.innerText || "");
    const hasPageNotFound = /Page Not Found/i.test(bodyText);
    const hasSignIn = /Sign in to your account/i.test(bodyText) || /login\.microsoftonline\.com/i.test(location.href);
    const fileStem = route.replace(/[^a-z0-9]+/gi, "_").replace(/^_+|_+$/g, "") || "root";
    const screenshotPath = path.join(outputDir, `${fileStem}.png`);
    await page.screenshot({ path: screenshotPath, fullPage: true });
    results.push({
      route,
      url: page.url(),
      status: response ? response.status() : null,
      hasPageNotFound,
      hasSignIn,
      title: await page.title(),
      screenshotPath
    });
  }

  const jsonPath = path.join(outputDir, "portal-route-smoke.json");
  fs.writeFileSync(jsonPath, JSON.stringify({
    generatedOn: new Date().toISOString(),
    baseUrl,
    authState: authState && fs.existsSync(authState) ? authState : null,
    results
  }, null, 2));

  await browser.close();

  const failed = results.filter((item) => item.hasPageNotFound);
  if (failed.length) {
    console.error(JSON.stringify({ failed }, null, 2));
    process.exit(1);
  }
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
});
