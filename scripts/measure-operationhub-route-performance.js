const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function sanitizeName(value) {
  return String(value || "")
    .trim()
    .replace(/[^a-z0-9]+/gi, "-")
    .replace(/^-+|-+$/g, "")
    .toLowerCase() || "route";
}

function defaultRoutes(baseUrl) {
  return [
    { name: "branch-home", url: `${baseUrl}/southern-alberta/4171-calgary` },
    { name: "quotes-ledger", url: `${baseUrl}/southern-alberta/4171-calgary/detail/?view=quotes` },
    { name: "follow-up-queue", url: `${baseUrl}/southern-alberta/4171-calgary/detail/?view=follow-up-queue` },
    { name: "quote-detail", url: `${baseUrl}/southern-alberta/4171-calgary/detail/?view=quote-detail&quote=0515438274` },
    { name: "analytics", url: `${baseUrl}/southern-alberta/4171-calgary/detail/?view=analytics` }
  ];
}

async function clearPageCache(page) {
  try {
    const session = await page.context().newCDPSession(page);
    await session.send("Network.enable");
    await session.send("Network.clearBrowserCache");
    await session.detach();
  } catch (error) {
    // Best-effort only. Auth cookies must remain intact.
  }
}

function trackableRequest(url) {
  return /^https:\/\/operationhub\.powerappsportals\.com\//i.test(url) ||
    /^https:\/\/login\.microsoftonline\.com\//i.test(url) ||
    url.indexOf("/_api/") !== -1 ||
    url.indexOf("/_layout/tokenhtml") !== -1;
}

function summarizeRequests(records) {
  const sorted = records
    .slice()
    .sort((left, right) => (right.durationMs || 0) - (left.durationMs || 0));
  return {
    total: records.length,
    apiCount: records.filter((record) => record.url.indexOf("/_api/") !== -1).length,
    failedCount: records.filter((record) => record.failed).length,
    slowest: sorted.slice(0, 12)
  };
}

async function captureRoute(page, route, outputDir) {
  await clearPageCache(page);
  await page.goto("about:blank", { waitUntil: "load" });

  const requestStarts = new Map();
  const requestRecords = [];
  const startedAt = new Date().toISOString();

  const onRequest = (request) => {
    if (!trackableRequest(request.url())) {
      return;
    }
    requestStarts.set(request, Date.now());
  };

  const onRequestFinished = async (request) => {
    if (!requestStarts.has(request)) {
      return;
    }
    const started = requestStarts.get(request);
    requestStarts.delete(request);
    let status = null;
    let ok = null;
    try {
      const response = await request.response();
      status = response ? response.status() : null;
      ok = response ? response.ok() : null;
    } catch (error) {
      status = null;
      ok = null;
    }
    requestRecords.push({
      url: request.url(),
      method: request.method(),
      resourceType: request.resourceType(),
      durationMs: Date.now() - started,
      status,
      ok,
      failed: false
    });
  };

  const onRequestFailed = (request) => {
    if (!requestStarts.has(request)) {
      return;
    }
    const started = requestStarts.get(request);
    requestStarts.delete(request);
    requestRecords.push({
      url: request.url(),
      method: request.method(),
      resourceType: request.resourceType(),
      durationMs: Date.now() - started,
      status: null,
      ok: false,
      failed: true,
      failureText: request.failure() ? request.failure().errorText : "failed"
    });
  };

  page.on("request", onRequest);
  page.on("requestfinished", onRequestFinished);
  page.on("requestfailed", onRequestFailed);

  try {
    await page.goto(route.url, { waitUntil: "load", timeout: 60000 });
    try {
      await page.waitForSelector("[data-qfu-runtime-signature]", { timeout: 20000 });
    } catch (error) {
      // Some pages may still be on auth or render slower; keep collecting timings.
    }
    try {
      await page.waitForLoadState("networkidle", { timeout: 10000 });
    } catch (error) {
      // Runtime pages can keep background calls alive. Continue after a short settle.
    }
    await sleep(1500);
  } finally {
    page.off("request", onRequest);
    page.off("requestfinished", onRequestFinished);
    page.off("requestfailed", onRequestFailed);
  }

  const navigationTiming = await page.evaluate(() => {
    const entry = performance.getEntriesByType("navigation")[0];
    if (!entry) {
      return null;
    }
    return {
      type: entry.type || "",
      redirectCount: entry.redirectCount || 0,
      startTime: Math.round(entry.startTime || 0),
      responseStartMs: Math.round(entry.responseStart || 0),
      responseEndMs: Math.round(entry.responseEnd || 0),
      domInteractiveMs: Math.round(entry.domInteractive || 0),
      domContentLoadedMs: Math.round(entry.domContentLoadedEventEnd || 0),
      loadEventEndMs: Math.round(entry.loadEventEnd || 0),
      durationMs: Math.round(entry.duration || 0),
      transferSize: entry.transferSize || 0,
      encodedBodySize: entry.encodedBodySize || 0,
      decodedBodySize: entry.decodedBodySize || 0
    };
  });

  async function readPageState() {
    return page.evaluate(() => {
      const root = document.querySelector("[data-qfu-phase0]");
      return {
        title: document.title,
        url: window.location.href,
        pageType: root ? String(root.getAttribute("data-page") || "") : "",
        branchSlug: root ? String(root.getAttribute("data-branch") || "") : "",
        regionSlug: root ? String(root.getAttribute("data-region") || "") : "",
        runtimeReady: !!document.querySelector("[data-qfu-runtime-signature]"),
        diagnosticsCount: document.querySelectorAll(".qfu-phase0-runtime-diagnostics li").length
      };
    });
  }

  let pageState;
  try {
    pageState = await readPageState();
  } catch (error) {
    await page.waitForLoadState("domcontentloaded", { timeout: 15000 }).catch(() => {});
    await sleep(1000);
    pageState = await readPageState();
  }

  const screenshotPath = path.join(outputDir, `${sanitizeName(route.name)}.png`);
  let screenshotError = null;
  try {
    await page.screenshot({ path: screenshotPath, fullPage: true });
  } catch (error) {
    screenshotError = error && error.message ? error.message : String(error || "screenshot failed");
  }

  return {
    name: route.name,
    url: route.url,
    startedAt,
    finishedAt: new Date().toISOString(),
    pageState,
    navigationTiming,
    requests: summarizeRequests(requestRecords),
    screenshotPath: screenshotError ? null : screenshotPath,
    screenshotError
  };
}

async function main() {
  const projectRoot = path.resolve(__dirname, "..");
  const statePath = path.join(projectRoot, "results", "playwright-auth-browser.json");
  if (!fs.existsSync(statePath)) {
    throw new Error(`Auth browser state file not found at ${statePath}. Start the auth browser first.`);
  }

  const state = JSON.parse(fs.readFileSync(statePath, "utf8"));
  const port = Number(state.port || process.env.QFU_AUTH_BROWSER_PORT || 9333);
  const endpoint = `http://127.0.0.1:${port}`;
  const outputRoot = path.join(projectRoot, "output", "playwright");
  const runStamp = new Date().toISOString().replace(/[:.]/g, "-");
  const outputDir = path.join(outputRoot, `operationhub-perf-${runStamp}`);
  const baseUrl = "https://operationhub.powerappsportals.com";
  const routes = defaultRoutes(baseUrl);

  fs.mkdirSync(outputDir, { recursive: true });

  const browser = await chromium.connectOverCDP(endpoint);
  try {
    const context = browser.contexts()[0] || await browser.newContext();
    const page = context.pages()[0] || await context.newPage();
    const measurements = [];

    for (const route of routes) {
      measurements.push(await captureRoute(page, route, outputDir));
    }

    const summary = measurements
      .map((measurement) => ({
        name: measurement.name,
        url: measurement.url,
        pageType: measurement.pageState.pageType,
        runtimeReady: measurement.pageState.runtimeReady,
        diagnosticsCount: measurement.pageState.diagnosticsCount,
        loadEventEndMs: measurement.navigationTiming ? measurement.navigationTiming.loadEventEndMs : null,
        domContentLoadedMs: measurement.navigationTiming ? measurement.navigationTiming.domContentLoadedMs : null,
        apiCount: measurement.requests.apiCount,
        failedCount: measurement.requests.failedCount
      }))
      .sort((left, right) => (right.loadEventEndMs || 0) - (left.loadEventEndMs || 0));

    const payload = {
      capturedAt: new Date().toISOString(),
      endpoint,
      outputDir,
      routes: measurements,
      summary
    };

    const outputPath = path.join(outputDir, "operationhub-performance.json");
    fs.writeFileSync(outputPath, JSON.stringify(payload, null, 2));
    console.log(JSON.stringify({ outputPath, summary }, null, 2));
  } finally {
    await browser.close();
  }
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
