const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

function getArg(name, fallback) {
  const prefix = `--${name}=`;
  const match = process.argv.find((arg) => arg.startsWith(prefix));
  if (!match) {
    return fallback;
  }
  return match.slice(prefix.length);
}

function ensureDir(targetPath) {
  fs.mkdirSync(targetPath, { recursive: true });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForFreightWorkbench(page, options = {}) {
  const allowEmptyRows = !!options.allowEmptyRows;
  await page.waitForSelector("[data-qfu-phase0]", { timeout: 60000 });
  await page.waitForFunction(() => {
    const phase = document.querySelector("[data-qfu-phase0]");
    if (!phase) {
      return false;
    }
    return phase.innerText.includes("FREIGHT WORKLIST");
  }, { timeout: 60000 });
  await page.waitForSelector(".qfu-phase0-freight-hero, .qfu-phase0-freight-toolbar", { timeout: 60000 });
  if (!allowEmptyRows) {
    await page.waitForFunction(() => {
      return document.querySelectorAll("[data-qfu-freight-row]").length > 0;
    }, { timeout: 60000 });
  }
  await sleep(1500);
}

async function snapshot(page, name) {
  const outputDir = path.resolve(getArg("outputDir", "output/playwright"));
  ensureDir(outputDir);
  const pngPath = path.join(outputDir, `${name}.png`);
  const jsonPath = path.join(outputDir, `${name}.json`);
  await page.screenshot({ path: pngPath, fullPage: true });
  const data = await page.evaluate(() => {
    return {
      url: location.href,
      title: document.title,
      flashMessages: Array.from(document.querySelectorAll(".qfu-phase0-flash, [data-qfu-flash]")).map((node) => node.innerText.trim()).filter(Boolean),
      rowCount: document.querySelectorAll("[data-qfu-freight-row]").length,
      rows: Array.from(document.querySelectorAll("[data-qfu-freight-row]")).map((row) => row.innerText.trim()),
      excerpt: document.body.innerText.slice(0, 4000)
    };
  });
  fs.writeFileSync(jsonPath, JSON.stringify(data, null, 2));
  return { pngPath, jsonPath, data };
}

async function getVisibleRows(page) {
  return page.evaluate(() => {
    return Array.from(document.querySelectorAll("[data-qfu-freight-row]")).map((row) => row.innerText.trim());
  });
}

function freightRowByMarker(page, marker) {
  return page.locator("[data-qfu-freight-row]").filter({ hasText: marker }).first();
}

async function assertRowContainsOnly(rows, expectedText) {
  if (!rows.length) {
    throw new Error(`Expected at least one row containing "${expectedText}".`);
  }
  const offenders = rows.filter((text) => !text.includes(expectedText));
  if (offenders.length) {
    throw new Error(`Expected all rows to contain "${expectedText}", but ${offenders.length} row(s) did not.`);
  }
}

async function assertNoRowsContain(rows, text) {
  const offenders = rows.filter((row) => row.includes(text));
  if (offenders.length) {
    throw new Error(`Expected no visible rows containing "${text}", but found ${offenders.length}.`);
  }
}

async function runAuthenticatedChecks() {
  const baseUrl = getArg("baseUrl", "https://operationhub.powerappsportals.com/southern-alberta/4171-calgary/detail/?view=freight-worklist");
  const portalMarker = getArg("portalMarker", "QFU-FREIGHT-PORTAL-VERIFY");
  const archiveMarker = getArg("archiveMarker", "QFU-FREIGHT-ARCHIVE-VERIFY");
  const outputDir = path.resolve(getArg("outputDir", "output/playwright"));
  const authStatePath = path.resolve(getArg("authState", ".playwright-auth/operationhub-dev-state.json"));
  ensureDir(outputDir);

  const browser = await chromium.launch({ headless: true });
  const contextOptions = fs.existsSync(authStatePath) ? { storageState: authStatePath } : {};
  const context = await browser.newContext(contextOptions);
  const page = await context.newPage();
  const checks = [];

  const gotoAndWait = async (url, options = {}) => {
    const separator = url.includes("?") ? "&" : "?";
    const bustUrl = `${url}${separator}_qfuBust=${Date.now()}`;
    await page.goto(bustUrl, { waitUntil: "domcontentloaded" });
    await waitForFreightWorkbench(page, options);
  };

  await gotoAndWait(`${baseUrl}&search=${encodeURIComponent(portalMarker)}`);
  await page.waitForFunction(() => {
    const row = document.querySelector("[data-qfu-freight-row]");
    return !!row && row.innerText.includes("Take Ownership");
  }, { timeout: 60000 });
  await snapshot(page, "freight-portal-verify-baseline");
  checks.push({ check: "portal-search-baseline", ok: (await page.locator("[data-qfu-freight-row]").count()) >= 1 });

  const userName = await page.evaluate(() => {
    const banner = document.querySelector(".private-mode-banner");
    const text = String((banner && banner.innerText) || document.body.innerText || "");
    const match = text.match(/Signed in as\s+([^\n]+)/i);
    return match ? match[1].trim() : "";
  });

  let row = freightRowByMarker(page, portalMarker);
  await row.locator("[data-qfu-take-freight]").click();
  await page.waitForFunction((name) => document.body.innerText.includes("Freight row claimed.") && document.body.innerText.includes(name), userName, { timeout: 60000 });
  checks.push({ check: "take-ownership", ok: true, userName });

  await gotoAndWait(`${baseUrl}&search=${encodeURIComponent(portalMarker)}`);
  row = freightRowByMarker(page, portalMarker);
  const noteText = `Portal verification note ${new Date().toISOString()}`;
  await row.locator("[data-qfu-freight-status-select]").selectOption("In Progress");
  await row.locator("[data-qfu-freight-comment]").fill(noteText);
  await row.locator("[data-qfu-save-freight]").click();
  await page.waitForFunction(() => document.body.innerText.includes("Freight row updated."), { timeout: 60000 });
  checks.push({ check: "save-note-status", ok: true, noteText, status: "In Progress" });

  await gotoAndWait(`${baseUrl}&search=${encodeURIComponent(portalMarker)}&status=${encodeURIComponent("In Progress")}`);
  let rows = await getVisibleRows(page);
  await assertRowContainsOnly(rows, "In Progress");
  checks.push({ check: "status-filter", ok: true, rowCount: rows.length });

  await gotoAndWait(`${baseUrl}&search=${encodeURIComponent(portalMarker)}&owner=${encodeURIComponent(userName)}`);
  rows = await getVisibleRows(page);
  await assertRowContainsOnly(rows, userName);
  checks.push({ check: "owner-filter", ok: true, rowCount: rows.length, userName });

  await gotoAndWait(`${baseUrl}&search=${encodeURIComponent(portalMarker)}`);
  row = freightRowByMarker(page, portalMarker);
  await row.locator("[data-qfu-release-freight]").click();
  await page.waitForFunction(() => document.body.innerText.includes("Freight ownership released."), { timeout: 60000 });
  checks.push({ check: "release-ownership", ok: true });

  await gotoAndWait(`${baseUrl}&carrier=${encodeURIComponent("Purolator")}`);
  rows = await getVisibleRows(page);
  await assertRowContainsOnly(rows, "Purolator");
  checks.push({ check: "carrier-filter", ok: true, rowCount: rows.length });

  await gotoAndWait(`${baseUrl}&minAmount=900`);
  const highValueRows = await page.evaluate(() => {
    return Array.from(document.querySelectorAll("[data-qfu-freight-row]")).map((row) => {
      const text = row.innerText;
      const match = text.match(/\$([0-9,]+\.[0-9]{2})/);
      return {
        text,
        amount: match ? Number(match[1].replace(/,/g, "")) : null
      };
    });
  });
  if (!highValueRows.length || highValueRows.some((rowData) => rowData.amount === null || rowData.amount < 900)) {
    throw new Error("Minimum amount filter returned rows below $900 or failed to return rows.");
  }
  checks.push({ check: "amount-filter", ok: true, rowCount: highValueRows.length });

  await gotoAndWait(`${baseUrl}&search=${encodeURIComponent(portalMarker)}`);
  const downloadPromise = page.waitForEvent("download", { timeout: 10000 }).catch(() => null);
  await page.locator("[data-qfu-export-freight-csv]").click();
  const download = await downloadPromise;
  checks.push({
    check: "csv-export-button",
    ok: !!download,
    filename: download ? download.suggestedFilename() : null
  });

  row = freightRowByMarker(page, portalMarker);
  const archivedRowId = await row.getAttribute("data-qfu-freight-row");
  await row.locator("[data-qfu-toggle-freight-archive]").click();
  await page.waitForFunction(() => document.body.innerText.includes("Freight row archived."), { timeout: 60000 });
  checks.push({ check: "archive-row", ok: true, archivedRowId });

  await gotoAndWait(`${baseUrl}&search=${encodeURIComponent(portalMarker)}`, { allowEmptyRows: true });
  rows = await getVisibleRows(page);
  const defaultVisiblePortalRows = await freightRowByMarker(page, portalMarker).count();
  const activeRowIds = await page.evaluate(() => {
    return Array.from(document.querySelectorAll("[data-qfu-freight-row]")).map((node) => node.getAttribute("data-qfu-freight-row"));
  });
  if (defaultVisiblePortalRows > 0 || (archivedRowId && activeRowIds.includes(archivedRowId))) {
    throw new Error(`Archived row ${archivedRowId} is still visible in the default active queue.`);
  }
  checks.push({ check: "archive-hidden-by-default", ok: true, activeRowIds });

  await gotoAndWait(`${baseUrl}&search=${encodeURIComponent(portalMarker)}&archived=1`);
  rows = await getVisibleRows(page);
  await assertRowContainsOnly(rows, portalMarker);
  const archivedRowIds = await page.evaluate(() => {
    return Array.from(document.querySelectorAll("[data-qfu-freight-row]")).map((node) => node.getAttribute("data-qfu-freight-row"));
  });
  if (archivedRowId && !archivedRowIds.includes(archivedRowId)) {
    throw new Error(`Archived row ${archivedRowId} did not appear when archived rows were included.`);
  }
  checks.push({ check: "archived-visible-when-enabled", ok: true, rowCount: rows.length, archivedRowIds });

  const archivedRow = freightRowByMarker(page, portalMarker);
  await archivedRow.locator("[data-qfu-toggle-freight-archive]").click();
  await page.waitForFunction(() => document.body.innerText.includes("Freight row restored to the active queue."), { timeout: 60000 });
  checks.push({ check: "unarchive-row", ok: true });

  await gotoAndWait(`${baseUrl}&search=${encodeURIComponent(portalMarker)}`);
  if (!(await freightRowByMarker(page, portalMarker).count())) {
    throw new Error("Unarchived portal verification row did not return to the active queue.");
  }

  await gotoAndWait(`${baseUrl}&search=${encodeURIComponent(archiveMarker)}`, { allowEmptyRows: true });
  rows = await getVisibleRows(page);
  if (await freightRowByMarker(page, archiveMarker).count()) {
    throw new Error("Archive candidate row is visible before the archived toggle is enabled.");
  }
  checks.push({ check: "archive-candidate-hidden-by-default", ok: true });

  await gotoAndWait(`${baseUrl}&search=${encodeURIComponent(archiveMarker)}&archived=1`);
  rows = await getVisibleRows(page);
  await assertRowContainsOnly(rows, archiveMarker);
  checks.push({ check: "archive-candidate-visible-with-archived-toggle", ok: true, rowCount: rows.length });

  await snapshot(page, "freight-portal-verify-final");
  const result = {
    mode: "authenticated",
    authStatePath: fs.existsSync(authStatePath) ? authStatePath : null,
    checks
  };
  const outputPath = path.join(outputDir, "freight-portal-verification.json");
  fs.writeFileSync(outputPath, JSON.stringify(result, null, 2));
  await browser.close();
  return result;
}

async function runAnonymousChecks() {
  const baseUrl = getArg("baseUrl", "https://operationhub.powerappsportals.com/southern-alberta/4171-calgary/detail/?view=freight-worklist");
  const outputDir = path.resolve(getArg("outputDir", "output/playwright"));
  ensureDir(outputDir);

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  const page = await context.newPage();

  const response = await page.goto(baseUrl, { waitUntil: "domcontentloaded" });
  await sleep(1500);
  const detailState = await page.evaluate(() => ({
    url: location.href,
    title: document.title,
    text: document.body.innerText.slice(0, 2000)
  }));

  const apiResponse = await context.request.get("https://operationhub.powerappsportals.com/_api/qfu_freightworkitems?$top=1", {
    failOnStatusCode: false
  });
  const apiBody = await apiResponse.text();

  const result = {
    mode: "anonymous",
    detailStatus: response ? response.status() : null,
    detailUrl: detailState.url,
    detailTitle: detailState.title,
    detailText: detailState.text,
    apiStatus: apiResponse.status(),
    apiBodyPreview: apiBody.slice(0, 1000)
  };

  await page.screenshot({ path: path.join(outputDir, "freight-portal-anonymous-check.png"), fullPage: true });
  fs.writeFileSync(path.join(outputDir, "freight-portal-anonymous-check.json"), JSON.stringify(result, null, 2));
  await browser.close();
  return result;
}

async function main() {
  const results = {
    generatedAtUtc: new Date().toISOString(),
    authenticated: await runAuthenticatedChecks(),
    anonymous: await runAnonymousChecks()
  };
  const outputDir = path.resolve(getArg("outputDir", "output/playwright"));
  ensureDir(outputDir);
  fs.writeFileSync(path.join(outputDir, "freight-portal-verification-combined.json"), JSON.stringify(results, null, 2));
  process.stdout.write(JSON.stringify(results, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
