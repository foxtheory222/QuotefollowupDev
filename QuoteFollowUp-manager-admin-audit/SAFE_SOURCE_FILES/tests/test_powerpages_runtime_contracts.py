import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
RUNTIME_TEMPLATE = (
    REPO_ROOT
    / "site"
    / "web-templates"
    / "qfu-regional-runtime"
    / "QFU-Regional-Runtime.webtemplate.source.html"
)
SITE_SETTINGS = REPO_ROOT / "site" / "sitesetting.yml"
PHASE0_CSS = REPO_ROOT / "site" / "web-files" / "qfu-phase0.css"


class PowerPagesRuntimeContractTests(unittest.TestCase):
    def test_delivery_not_pgi_uses_inactiveon_as_only_hard_inactive_signal(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn("function deliveryNotPgiRowIsActive(record)", template)
        self.assertIn("Treat inactiveon as the only hard", template)
        self.assertNotIn("return active === false;", template)

    def test_quotes_ledger_exposes_sort_and_page_size_controls(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn("function renderQuotesLedgerFilterToolbar", template)
        self.assertIn("qfu-phase0-quotes-toolbar__grid", template)
        self.assertIn("qfu-phase0-quotes-toolbar__rail", template)
        self.assertIn("Status, sort, and paging", template)
        self.assertIn("qfu-phase0-detail-filterbar__fields--quotes-ledger-rail", template)
        self.assertIn("Branch quote archive", template)
        self.assertIn("Filtered Quotes", template)
        self.assertIn('name="sort"', template)
        self.assertIn('name="pageSize"', template)
        self.assertIn("Created From", template)
        self.assertIn("Apply Filters", template)
        self.assertIn("All Quotes Ledger", template)
        self.assertIn("The follow-up queue stays separate as the action workbench", template)
        self.assertIn("[25, 50, 100, 250].map", template)

    def test_quotes_ledger_uses_clickable_quote_links_and_removes_redundant_action_columns(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        section = template.split("function renderQuoteWorkbenchTable(rows, options) {", 1)[1].split(
            "function renderQuotesSummaryPanel", 1
        )[0]
        self.assertIn("function renderQuoteWorkbenchColgroup(showCreatedOn)", template)
        self.assertIn("qfu-phase0-quotes-row__quote-link", section)
        self.assertIn("Open current quote detail", section)
        self.assertIn("Open archived quote detail", section)
        self.assertIn("qfu-phase0-quotes-row__state", section)
        self.assertIn("qfu-phase0-quotes-row__badges", section)
        self.assertIn("qfu-phase0-summary-table--quotes-workbench ' + (showCreatedOn ? 'is-with-created' : 'is-no-created')", section)
        self.assertIn("renderQuoteWorkbenchColgroup(showCreatedOn)", section)
        self.assertIn("<th>Next Follow-up</th><th>Last Touched</th><th>CSSR</th><th>TSR</th><th>Age</th><th class=\"qfu-phase0-table__numeric\">Value</th>", section)
        self.assertNotIn("<th>Open</th>", section)
        self.assertNotIn("<th>Queue</th>", section)
        self.assertNotIn('">Queue</a>', section)

    def test_home_unfollowed_quotes_panel_uses_full_row_quote_links(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        section = template.split("function renderQuoteQueueCompactTable(rows) {", 1)[1].split(
            "function renderHomeBackorderList", 1
        )[0]
        self.assertIn('var href = row.openHref || row.queueHref || "#";', section)
        self.assertIn('class="qfu-phase0-home-feed__row qfu-phase0-home-feed__row--quote"', section)
        self.assertIn('href="\' + escapeHtml(href) + \'" aria-label="\' + escapeHtml(label) + \'"', section)
        self.assertNotIn('qfu-phase0-home-feed__actions', section)
        self.assertNotIn('">Queue</a>', section)
        self.assertNotIn('">Open</a>', section)
        self.assertIn(".qfu-phase0-home-feed__row--quote:hover,", template)

    def test_home_abnormal_margins_panel_uses_full_row_filtered_analytics_links(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        section = template.split("function renderHomeMarginPreviewList(rows, detailHref) {", 1)[1].split(
            "function renderHomeFreightReviewList", 1
        )[0]
        self.assertIn('var href = detailHref || "#";', section)
        self.assertIn('class="qfu-phase0-home-feed__row qfu-phase0-home-feed__row--margin"', section)
        self.assertIn('aria-label="\' + escapeHtml(label) + \'"', section)
        self.assertIn('detailHrefWithParams(branch, "analytics", { exception: "margin", window: "month" })', template)
        self.assertIn("renderHomeMarginPreviewList(rows, marginDetailHref)", template)
        self.assertIn("renderHomeMarginPreviewList(pageInfo.items, marginDetailHref)", template)
        self.assertIn(".qfu-phase0-home-feed__row--margin:hover,", template)

    def test_home_freight_review_panel_uses_full_row_ledger_links(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        section = template.split("function renderHomeFreightReviewList(rows, detailFallbackHref) {", 1)[1].split(
            "function renderBackorderTable", 1
        )[0]
        self.assertIn('var href = detailFallbackHref || row.ledgerHref || row.detailHref || "#";', section)
        self.assertIn('var rowLabel = "Open freight ledger for " + label;', section)
        self.assertIn('class="qfu-phase0-home-feed__row qfu-phase0-home-feed__row--freight"', section)
        self.assertIn('href="\' + escapeHtml(href) + \'" aria-label="\' + escapeHtml(rowLabel) + \'"', section)
        self.assertNotIn("<strong><a href=", section)
        self.assertIn(".qfu-phase0-home-feed__row--freight:hover,", template)

    def test_freight_review_rows_use_dashboard_row_links(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        section = template.split("function renderFreightReviewTable(rows, options) {", 1)[1].split(
            "function renderBranchFreightReviewPanel", 1
        )[0]
        self.assertIn('ledgerHref: branch ? detailHref(branch, "freight-worklist") : "",', template)
        self.assertIn('var rowHref = row.ledgerHref || row.detailHref || "#";', section)
        self.assertIn('class="qfu-phase0-freight-review__row"', section)
        self.assertIn('data-qfu-dashboard-href="\' + escapeHtml(rowHref) + \'"', section)
        self.assertIn('tabindex="0" role="link"', section)
        self.assertNotIn('"><a href="\' + escapeHtml(row.detailHref || "#") + \'">', section)
        self.assertIn('var rowLink = target && target.closest ? target.closest("[data-qfu-dashboard-href]") : null;', template)
        self.assertIn('window.location.assign(href);', template)
        self.assertIn('event.key !== "Enter" && event.key !== " "', template)
        self.assertIn(".qfu-phase0-summary-table--freight-review .qfu-phase0-freight-review__row:hover td,", PHASE0_CSS.read_text(encoding="utf-8"))

    def test_branch_freight_watchlist_rows_use_branch_ledger_links(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        section = template.split("function renderBranchHomeFreightRows(branch, workspace) {", 1)[1].split(
            "function renderBranchHomeFreightPanel", 1
        )[0]
        self.assertIn('var href = row.ledgerHref || detailHref(branch, "freight-worklist");', section)
        self.assertIn('class="qfu-phase0-branch-watchlist-row is-freight"', section)

    def test_quotes_archive_search_and_detail_use_all_stored_quote_headers(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn("quoteArchiveRows: quoteArchiveRows", template)
        self.assertIn("rows = (workspace.quoteArchiveRows || workspace.quoteRows || []).slice();", template)
        self.assertIn('nameLabel: "Quote # / TSR / CSSR"', template)
        self.assertIn('namePlaceholder: "Search quote or rep"', template)
        self.assertIn("includesFilterText(row.quote, filterText)", template)
        self.assertIn("var quoteRow = (workspace.quoteArchiveRows || []).find(", template)
        self.assertIn('buildFilterChip("State", quoteRow.stateLabel', template)

    def test_cssr_leaderboard_and_quote_fetch_normalize_blank_owner_and_tsr(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn("function normalizeCssrDisplayName(value, fallback)", template)
        self.assertIn("qfu_tsrname", template)
        self.assertIn("if (!isMissingDisplayName(primary))", template)
        self.assertIn("var tsr = resolveTsrDisplay(record.qfu_assignedto, record.qfu_tsrname, cssr);", template)
        self.assertIn("buildQuoteFallbackRecordsFromLineRecords", template)
        self.assertIn("mergeQuoteHeaderTsrFromLineRecords", template)
        self.assertIn('"/_api/qfu_quotelines?$select=qfu_quotelineid,qfu_quotenumber,qfu_amount,qfu_status,qfu_cssrname,qfu_tsr,qfu_tsrname,qfu_soldtopartyname,qfu_sourcedate,qfu_lastimportdate,qfu_branchcode,qfu_branchslug,qfu_regionslug,createdon,modifiedon&$top=2500"', template)

    def test_quote_created_moment_prefers_source_date_over_dataverse_createdon(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn(
            "return parseBusinessDate(record && record.qfu_sourcedate) || parseDate(record && record.createdon);",
            template,
        )
        self.assertIn(
            "var createdOn = parseBusinessDate(record.qfu_sourcedate) || parseDate(record.createdon);",
            template,
        )
        self.assertNotIn(
            "return parseDate(record && record.createdon) || parseBusinessDate(record && record.qfu_sourcedate);",
            template,
        )
        self.assertNotIn(
            "var createdOn = parseDate(record.createdon) || parseBusinessDate(record.qfu_sourcedate);",
            template,
        )

    def test_overdue_backorders_normalize_blank_cssr_for_links_and_detail_filters(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn("function normalizeCssrDisplayName(value, fallback)", template)
        self.assertIn('cssr: normalizeCssrDisplayName(record.qfu_cssrname, "Unassigned")', template)
        self.assertIn('var key = normalizeCssrDisplayName(record.qfu_cssrname, "Unassigned");', template)
        self.assertIn('detailHrefWithParams(branch, "overdue-backorders", { cssr: cssrName })', template)
        self.assertIn('cssr: normalizeCssrDisplayName(params.get("cssr"), "")', template)
        self.assertIn('return normalizeCssrDisplayName(row.cssr, "Unassigned") === normalizeCssrDisplayName(filters.cssr, "Unassigned");', template)

    def test_quote_webapi_fields_allow_qfu_tsr(self) -> None:
        settings = SITE_SETTINGS.read_text(encoding="utf-8")
        self.assertIn("Webapi/qfu_quote/fields", settings)
        self.assertIn("qfu_assignedto,qfu_tsr,qfu_cssrname", settings)

    def test_runtime_fetch_bundle_skips_unneeded_operational_datasets_on_detail_views(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn(
            'var detailViewKey = isDetailPage ? normalizeDetailViewKey(context.viewKey || "follow-up-queue") : "";',
            template,
        )
        self.assertIn(
            'var needsQuoteData = !isDetailPage || ["follow-up-queue", "quotes", "overdue-quotes", "team-progress"].indexOf(detailViewKey) !== -1;',
            template,
        )
        self.assertIn(
            'var needsBackorderData = !isDetailPage || ["overdue-backorders", "team-progress", "ready-to-ship-not-pgid", "analytics"].indexOf(detailViewKey) !== -1;',
            template,
        )
        self.assertIn('var needsBudgetData = !isDetailPage || detailViewKey === "analytics";', template)
        self.assertIn('var needsBranchSummaries = !isDetailPage || detailViewKey === "analytics";', template)
        self.assertIn('needsQuoteData ? safeGetAll(withFilter("/_api/qfu_quotes?', template)
        self.assertIn('needsBackorderData ? safeGetAll(withFilter("/_api/qfu_backorders?', template)
        self.assertIn('needsBudgetData ? safeGetAll(withFilter("/_api/qfu_budgets?', template)
        self.assertIn('needsBranchSummaries ? safeGetAll(withFilter("/_api/qfu_branchdailysummaries?', template)

    def test_analytics_page_renders_ranked_focus_first_plan(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn("function buildAnalyticsAttentionFocus", template)
        self.assertIn("function renderAnalyticsFocusPlanBar", template)
        self.assertIn("function renderAnalyticsPriorityStack", template)
        self.assertIn("function renderAnalyticsPerformanceDeck", template)
        self.assertIn("function renderAnalyticsActionTables", template)
        self.assertIn("function renderAnalyticsSourceContractPanel", template)
        self.assertIn("Focus Plan", template)
        self.assertIn("Top Ranked Action", template)
        self.assertIn("Performance Visualizations", template)
        self.assertIn("Highest impact quote follow-ups", template)
        self.assertIn("Source Contract", template)
        self.assertIn('title: "Sales are below plan - work the live quote book first"', template)
        self.assertIn('href: detailHref(branch, "follow-up-queue")', template)
        self.assertIn('label: "Backlog escalation"', template)
        self.assertIn('label: "Ready to ship"', template)
        self.assertIn('label: "Freight worklist"', template)
        self.assertIn('label: "Data freshness"', template)
        self.assertIn('var deliveryStatus = analyticsSourceStatus("Ready To Ship (Delivery)"', template)
        self.assertIn('var freightQueueStatus = analyticsSourceStatus("Freight Worklist"', template)
        self.assertIn("deliveryStatus: deliveryStatus", template)
        self.assertIn("freightQueueStatus: freightQueueStatus", template)
        self.assertIn(".qfu-phase0-analytics-command-grid", template)
        detail_section = template.split("async function renderAnalyticsDetail(branch, filters) {", 1)[1].split(
            "async function renderQuoteDetailLive", 1
        )[0]
        self.assertIn("var attentionItems = buildAnalyticsAttentionFocus(branch, payload, revenueMotion, readyToShip, freightRecovery, financeSnapshot, latestOpsTrend, workspace);", detail_section)
        self.assertIn("var focusKpis = buildAnalyticsFocusKpis(workspace, payload, quoteFocus, revenueMotion, readyToShip, financeSnapshot);", detail_section)
        self.assertLess(
            detail_section.index("renderAnalyticsFocusPlanBar(branch, attentionItems, focusKpis)"),
            detail_section.index("renderAnalyticsPriorityStack(branch, attentionItems)"),
        )
        self.assertLess(
            detail_section.index("renderAnalyticsPerformanceDeck(workspace, payload, quoteFocus, readyToShip, freightRecovery, financeSnapshot)"),
            detail_section.index("renderAnalyticsActionTables(branch, quoteFocus, payload, readyToShip, workspace)"),
        )
        self.assertNotIn("renderAnalyticsRevenueMotion(revenueMotion, watchItems)", detail_section)

    def test_analytics_page_keeps_stitch_visual_refresh_contract(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn("Stitch analytics visual refresh: Steel Grid Systems", template)
        self.assertIn("Compact Stitch analytics decision layout", template)
        self.assertIn(".qfu-phase0-analytics-stage{background:#f7f9fb;", template)
        self.assertIn(".qfu-phase0-analytics-stage::before,.qfu-phase0-analytics-revenue::after{display:none;}", template)
        self.assertIn(".qfu-phase0-analytics-command{background:#ffffff;", template)
        self.assertIn("border-radius:8px;box-shadow:0 8px 24px rgba(25,28,30,0.06);", template)
        self.assertIn("font-variant-numeric:tabular-nums;", template)

    def test_detail_routes_skip_budget_warnings_when_budget_inputs_were_not_loaded(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn(
            "function buildBranchWorkspaceLive(branch, quotes, quoteArchiveRecords, quoteLineFallbackRecords, backorders, budgets, budgetArchives, financeSnapshots, financeVariances, marginExceptions, lateOrderExceptions, summary, latestImport, branchImports, options) {",
            template,
        )
        self.assertIn("var budgetDataLoaded = options.budgetDataLoaded !== false;", template)
        self.assertIn("var summaryDataLoaded = options.summaryDataLoaded !== false;", template)
        self.assertIn("var canDiagnoseBudgetLineage = budgetDataLoaded && summaryDataLoaded;", template)
        self.assertIn(
            "var budgetDiagnostics = canDiagnoseBudgetLineage",
            template,
        )
        self.assertIn(
            "var annualTargetWarning = budgetDataLoaded && !annualBudgetTargetComplete ? {",
            template,
        )
        self.assertIn(
            "var budgetConsistencyDiagnostics = canDiagnoseBudgetLineage",
            template,
        )
        self.assertIn("budgetDiagnostics.dataLoaded = canDiagnoseBudgetLineage;", template)
        self.assertIn("budgetDataLoaded: needsBudgetData,", template)
        self.assertIn("summaryDataLoaded: needsBranchSummaries", template)

    def test_runtime_scopes_branch_region_and_sourcefeed_config_reads_to_current_route(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn("function inferredRegionSlug(context)", template)
        self.assertIn("function regionDisplayNameForSlug(slug)", template)
        self.assertIn('var RUNTIME_CACHE_VERSION = "20260423a";', template)
        self.assertIn("function readSessionRowsCache(cacheKey, ttlMs)", template)
        self.assertIn("function writeSessionRowsCache(cacheKey, rows, allowEmptyCache)", template)
        self.assertIn("function isLegacyRuntimeCacheKey(key)", template)
        self.assertIn("function purgeLegacyRuntimeCacheKeys()", template)
        self.assertIn("async function safeGetAllCached(path, datasetName, diagnostics, options)", template)
        self.assertIn("var CONFIG_CACHE_TTL_MS = 5 * 60 * 1000;", template)
        self.assertIn('var RUNTIME_CACHE_KEY = "qfu-runtime-" + RUNTIME_CACHE_VERSION + ":" + (context.pageType || "") + ":" + (context.branchSlug || "") + ":" + (context.regionSlug || "") + ":" + (context.viewKey || "");', template)
        self.assertIn('return !!(key && key.indexOf("qfu-runtime-") === 0 && key.indexOf("qfu-runtime-" + RUNTIME_CACHE_VERSION + ":") !== 0);', template)
        self.assertIn("purgeLegacyRuntimeCacheKeys();", template)
        self.assertIn('if (!allowEmptyCache && (!Array.isArray(rows) || !rows.length)) {', template)
        self.assertIn("var routeRegionSlug = inferredRegionSlug(context);", template)
        self.assertIn("return route && route.routeRegionSlug ? route.routeRegionSlug : \"\";", template)
        self.assertIn('var needsRegionConfig = context.pageType === "hub" || context.pageType === "region" || needsOpsData;', template)
        self.assertIn('var branchConfigFilter = context.branchSlug', template)
        self.assertIn('var regionConfigFilter = routeRegionSlug', template)
        self.assertIn('var branchConfigCacheKey = context.branchSlug ? ("qfu-config-v2-branch:" + context.branchSlug) : "";', template)
        self.assertIn('var regionConfigCacheKey = routeRegionSlug ? ("qfu-config-v2-region:" + routeRegionSlug) : "";', template)
        self.assertIn('var sourceFeedCacheKey = context.branchSlug ? ("qfu-config-v2-sourcefeeds:" + context.branchSlug) : "";', template)
        self.assertIn('var ingestionCacheKey = "qfu-freshness-v2:" + (context.branchSlug || context.regionSlug || routeRegionSlug || "all");', template)
        self.assertIn('safeGetAllCached(withFilter("/_api/qfu_branchs?', template)
        self.assertIn('needsRegionConfig ? safeGetAllCached(withFilter("/_api/qfu_regions?', template)
        self.assertIn('needsSourceFeeds ? safeGetAllCached(withFilter("/_api/qfu_sourcefeeds?', template)
        self.assertIn('safeGetAllCached(withFilter("/_api/qfu_ingestionbatchs?', template)
        self.assertIn("cacheTtlMs: INGESTION_CACHE_TTL_MS", template)
        self.assertIn("allowEmptyCache: true", template)
        self.assertIn('regionDisplayNameForSlug(branchRow.qfu_regionslug || slug)', template)

    def test_summary_pages_use_lightweight_delivery_and_freight_selects(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn("var DELIVERY_NOT_PGI_DETAIL_FIELDS =", template)
        self.assertIn("var DELIVERY_NOT_PGI_SUMMARY_FIELDS =", template)
        self.assertIn("var DELIVERY_NOT_PGI_ANALYTICS_FIELDS =", template)
        self.assertIn("var FREIGHT_DETAIL_FIELDS =", template)
        self.assertIn("var FREIGHT_SUMMARY_FIELDS =", template)
        self.assertIn('var deliveryNotPgiFields = (isDetailPage && detailViewKey === "ready-to-ship-not-pgid") || needsOpsData', template)
        self.assertIn('? DELIVERY_NOT_PGI_DETAIL_FIELDS', template)
        self.assertIn('? DELIVERY_NOT_PGI_ANALYTICS_FIELDS', template)
        self.assertIn(": DELIVERY_NOT_PGI_SUMMARY_FIELDS", template)
        self.assertIn('var freightFields = (isDetailPage && detailViewKey === "freight-worklist") || needsOpsData', template)
        self.assertIn('? FREIGHT_DETAIL_FIELDS', template)
        self.assertIn(": FREIGHT_SUMMARY_FIELDS", template)
        self.assertIn('"/_api/qfu_deliverynotpgis?$select=" + deliveryNotPgiFields', template)
        self.assertIn('"/_api/qfu_freightworkitems?$select=" + freightFields', template)
        summary_section = template.split("var DELIVERY_NOT_PGI_SUMMARY_FIELDS =", 1)[1].split("var DELIVERY_NOT_PGI_ANALYTICS_FIELDS =", 1)[0]
        self.assertIn('"qfu_comment"', summary_section)
        self.assertNotIn('"qfu_material"', summary_section)
        self.assertNotIn('"qfu_description"', summary_section)
        analytics_section = template.split("var DELIVERY_NOT_PGI_ANALYTICS_FIELDS =", 1)[1].split("var FREIGHT_DETAIL_FIELDS =", 1)[0]
        self.assertNotIn('"qfu_comment"', analytics_section)
        freight_summary_section = template.split("var FREIGHT_SUMMARY_FIELDS =", 1)[1].split("var REGION_ROUTE_MAP =", 1)[0]
        self.assertIn('"qfu_totalamount"', freight_summary_section)
        self.assertNotIn('"qfu_chargebreakdowntext"', freight_summary_section)
        self.assertNotIn('"qfu_comment"', freight_summary_section)

    def test_quotes_ledger_css_has_dedicated_responsive_grid(self) -> None:
        css = PHASE0_CSS.read_text(encoding="utf-8")
        self.assertIn(".qfu-phase0-detail-filterbar--quotes-ledger", css)
        self.assertIn(".qfu-phase0-detail-filterbar__fields--quotes-ledger", css)
        self.assertIn("grid-template-columns: repeat(4, minmax(0, 1fr));", css)
        self.assertIn(".qfu-phase0-detail-filterbar__buttons--quotes-ledger", css)

    def test_quotes_ledger_uses_desktop_dense_layout(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn(".qfu-phase0-quotes-toolbar__grid{display:grid;gap:0.6rem;grid-template-columns:repeat(18,minmax(0,1fr));}", template)
        self.assertIn(".qfu-phase0-quotes-toolbar__rail{align-items:end;", template)
        self.assertIn(".qfu-phase0-quotes-toolbar__rail-copy{align-content:start;display:grid;gap:0.24rem;}", template)
        self.assertIn(".qfu-phase0-quotes-stage .qfu-phase0-detail-filterbar__fields--quotes-ledger-rail{grid-template-columns:repeat(3,minmax(180px,1fr));}", template)
        self.assertIn(".qfu-phase0-quotes-stage .qfu-phase0-detail-filterbar__fields--quotes-ledger-date{grid-template-columns:repeat(3,minmax(0,1fr));}", template)
        self.assertIn(".qfu-phase0-quotes-stage .qfu-phase0-detail-filterbar__buttons{align-items:center", template)
        self.assertIn("grid-column:1 / -1;justify-content:flex-end;min-width:0;", template)
        self.assertIn(".qfu-phase0-quotes-toolbar__group--search{grid-column:span 10;}", template)
        self.assertIn(".qfu-phase0-quotes-toolbar__group--dates{grid-column:span 8;min-width:0;}", template)
        self.assertIn(".qfu-phase0-summary-table--quotes-workbench{table-layout:fixed;width:100%;}", template)
        self.assertIn(".qfu-phase0-summary-table--quotes-workbench.is-with-created .qfu-phase0-quotes-col--customer{width:22%;}", template)
        self.assertIn(".qfu-phase0-summary-table--quotes-workbench.is-with-created .qfu-phase0-quotes-col--tsr{width:11%;}", template)
        self.assertIn(".qfu-phase0-summary-table--quotes-workbench.is-no-created .qfu-phase0-quotes-col--customer{width:27%;}", template)
        self.assertIn(".qfu-phase0-quotes-row__customer strong{color:#17212b;display:-webkit-box;", template)
        self.assertIn("text-overflow:ellipsis;", template)

    def test_quote_detail_fetches_header_directly_and_matches_lines_by_branch_slug_or_code(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn("function branchIdentityOdataFilter(branch, codeFieldName, slugFieldName)", template)
        self.assertIn('var headerBranchFilter = branchIdentityOdataFilter(branch, "qfu_branchcode", "qfu_branchslug");', template)
        self.assertIn('var directQuoteHeaders = await safeGetAll(withFilter(headerPath, headerFilterClauses.join(" and ")), "qfu_quotes");', template)
        self.assertIn('var lineBranchFilter = branchIdentityOdataFilter(branch, "qfu_branchcode", "qfu_branchslug");', template)
        self.assertIn('var quoteLines = await safeGetAll(withFilter(linePath, lineFilterClauses.join(" and ")), "qfu_quotelines");', template)
        self.assertIn("Archived line history unavailable", template)
        self.assertIn("Archived qfu_quoteline history is not retained in the current model.", template)
        self.assertIn("This archived quote header has no current qfu_quoteline rows for the selected quote.", template)

    def test_late_order_fetch_uses_stable_ordered_path_to_bypass_stale_cached_response(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn('"/_api/qfu_lateorderexceptions?$select=qfu_lateorderexceptionid,qfu_name,qfu_sourceid,qfu_branchcode,qfu_branchslug,qfu_regionslug,qfu_sourcefamily,qfu_sourcefile,qfu_snapshotdate,qfu_billingdate,qfu_cssr,qfu_cssrname,qfu_soldtocustomername,qfu_shiptocustomername,qfu_billingdocumentnumber,qfu_materialgroup,qfu_itemcategory,qfu_itemcategorydescription,qfu_sales,createdon,modifiedon&$orderby=createdon desc,modifiedon desc&$top=1000"', template)
        self.assertIn('config.cache = "no-store";', template)
        self.assertIn("fetch(path, config)", template)

    def test_late_order_dedupe_uses_canonical_fields_not_legacy_sourceid(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn("function operationalIdentityValue(record, identityFields, options)", template)
        self.assertIn("(!options || options.preferSourceId !== false)", template)
        self.assertIn("preferSourceId: false,", template)
        self.assertIn('identityFields: ["qfu_branchcode", "qfu_snapshotdate", "qfu_billingdocumentnumber", "qfu_materialgroup", "qfu_itemcategory"]', template)

    def test_ready_to_ship_staleness_prefers_snapshot_refresh_over_base_createdon(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn("deliveryNotPgiLatestFreshnessOn = latestDate(", template)
        self.assertIn("branch.workspace.deliveryNotPgiLatestSnapshotOn,", template)
        self.assertIn("hoursBetween(new Date(), branch.workspace.deliveryNotPgiLatestFreshnessOn)", template)
        self.assertIn("Latest dispatch snapshot captured", template)
        self.assertNotIn("hoursBetween(new Date(), branch.workspace.deliveryNotPgiLatestBaseCreatedOn)", template)

    def test_freight_warning_uses_latest_import_time_not_latest_successful_time(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn("var latestImportMomentValue = importMoment(latestImportRow);", template)
        self.assertIn("var latestSuccessfulImportMomentValue = importMoment(latestSuccessfulImport || latestImportRow);", template)
        self.assertIn("latestSuccessfulImportLabel: latestSuccessfulImportLabel,", template)
        self.assertIn("Latest successful freight batch completed ", template)
        self.assertNotIn("var latestImportMomentValue = importMoment(latestSuccessfulImport || latestImportRow);", template)

    def test_freight_ledger_defaults_to_highest_value_with_explicit_sort_controls(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn(
            'sort: normalizeFreightLedgerSort(params.get("sort"))',
            template,
        )
        self.assertIn(
            'dateField: normalizeFreightDateField(params.get("dateField"))',
            template,
        )
        self.assertIn(
            'return ["value-desc", "value-asc", "newest", "oldest"].indexOf(normalized) >= 0 ? normalized : "value-desc";',
            template,
        )
        self.assertIn(
            '{ value: "value-desc", label: "Highest Value" }',
            template,
        )
        self.assertIn(
            '{ value: "value-asc", label: "Lowest Value" }',
            template,
        )
        self.assertIn(
            '{ value: "newest", label: "Newest Selected Date" }',
            template,
        )
        self.assertIn(
            '{ value: "oldest", label: "Oldest Selected Date" }',
            template,
        )
        self.assertIn(
            "Default sort is highest value first. Switch to newest or oldest using invoice date, ship date, or last activity.",
            template,
        )

    def test_freight_ledger_uses_investigation_labels_and_statuses(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn('"freight-worklist": { title: "Freight Ledger" }', template)
        self.assertIn('items.push({ key: "freight-worklist", label: "Freight Ledger"', template)
        self.assertIn('renderBranchViewHeader(branch, "Freight Ledger"', template)
        self.assertIn('var options = ["Unreviewed", "Investigating", "Reviewed", "No Action", "Closed"];', template)
        self.assertIn('return "Unreviewed";', template)
        self.assertIn('return "Investigating";', template)
        self.assertIn('return statusKey === "unreviewed" || statusKey === "investigating";', template)
        self.assertIn(
            "Only unresolved freight bills stay on this board, so reviewed and closed investigations fall out automatically.",
            template,
        )

    def test_freight_ledger_date_filters_use_selected_date_field(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn('{ value: "invoice", label: "Invoice Date" }', template)
        self.assertIn('{ value: "ship", label: "Ship Date" }', template)
        self.assertIn('{ value: "activity", label: "Last Activity" }', template)
        self.assertIn(
            'var dateFrom = filters.dateFrom ? dateInputStart(filters.dateFrom) : null;',
            template,
        )
        self.assertIn(
            'var dateTo = filters.dateTo ? dateInputEnd(filters.dateTo) : null;',
            template,
        )
        self.assertIn(
            'var rowDateValue = freightDateValue(row, dateField, 0);',
            template,
        )
        self.assertIn(
            '<label class="qfu-phase0-delivery-toolbar__field"><span>Date Field</span><select class="qfu-phase0-admin-input" name="dateField">',
            template,
        )
        self.assertIn(
            '<label class="qfu-phase0-delivery-toolbar__field"><span>Date From</span><input class="qfu-phase0-admin-input" type="date" name="dateFrom"',
            template,
        )
        self.assertIn(
            '<label class="qfu-phase0-delivery-toolbar__field"><span>Date To</span><input class="qfu-phase0-admin-input" type="date" name="dateTo"',
            template,
        )

    def test_ready_to_ship_oldest_preview_uses_on_time_aging_and_professional_copy(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        start = template.index("function deliveryNotPgiOrderOldestSort(left, right) {")
        end = template.index("function buildDeliveryNotPgiOrderRows(rows, branch) {")
        snippet = template[start:end]
        self.assertIn("if (right.daysLateNumber !== left.daysLateNumber) {", snippet)
        self.assertIn("return right.daysLateNumber - left.daysLateNumber;", snippet)
        self.assertIn("if (!!left.onTimeDateValue !== !!right.onTimeDateValue) {", snippet)
        self.assertIn("if (left.onTimeDateValue !== right.onTimeDateValue) {", snippet)
        self.assertIn("if (right.totalValueNumber !== left.totalValueNumber) {", snippet)
        self.assertIn("return right.totalValueNumber - left.totalValueNumber;", snippet)
        self.assertNotIn("daysOnListNumber", snippet)
        self.assertNotIn("left.createdOnValue", snippet)
        self.assertIn('var eyebrow = "Top 5 by value + Top 5 longest aging";', template)
        self.assertIn('title: "Top 5 longest aging"', template)
        self.assertIn('metaLabel: "Ranked by overdue aging from on-time date"', template)
        self.assertIn('metricLabel: "Days Past Due"', template)
        self.assertIn('Two views: highest unshipped dollars and the longest aging orders from the on-time date.', template)
        self.assertNotIn('title: "Top 5 oldest on list"', template)
        self.assertNotIn('metricLabel: "Days on List"', template)

    def test_regional_exceptions_table_includes_billing_date(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn("<th>Billing Date</th>", template)
        self.assertIn("qfu-phase0-region-exception__billing-date", template)
        self.assertIn("billingDate: row.billingDate,", template)

    def test_region_page_pairs_quotes_with_cssr_and_uses_clickable_quote_links(self) -> None:
        template = RUNTIME_TEMPLATE.read_text(encoding="utf-8")
        self.assertIn("Top 10 Highest Open Quotes", template)
        self.assertIn("qfu-phase0-region-support-stack", template)
        self.assertIn("qfu-phase0-region-support-grid qfu-phase0-region-support-grid--primary", template)
        self.assertIn("qfu-phase0-region-support-grid qfu-phase0-region-support-grid--paired", template)
        self.assertIn("qfu-phase0-region-quote-link", template)
        self.assertIn("<th>Branch</th><th>Quote #</th><th>Customer</th><th>Created</th><th>CSSR / TSR</th><th>Follow-up</th><th class=\"qfu-phase0-table__numeric\">Value</th>", template)
        self.assertIn("qfu-phase0-region-support-panel--quotes::before", template)
        self.assertIn("qfu-phase0-region-support-panel--exceptions::before", template)
        self.assertIn("qfu-phase0-region-support-panel--freight::before", template)


if __name__ == "__main__":
    unittest.main()
