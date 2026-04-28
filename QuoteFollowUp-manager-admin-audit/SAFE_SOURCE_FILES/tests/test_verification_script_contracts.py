import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = {
    "runtime_readiness": REPO_ROOT / "scripts" / "check-southern-alberta-runtime-readiness.ps1",
    "flow_health": REPO_ROOT / "scripts" / "check-southern-alberta-flow-health.ps1",
    "opsdaily_freshness": REPO_ROOT / "scripts" / "check-live-sa1300-opsdaily-freshness.ps1",
    "branch_summary_refresh": REPO_ROOT / "scripts" / "refresh-live-branch-daily-summaries.ps1",
    "budget_from_workbook": REPO_ROOT / "scripts" / "repair-live-sa1300-budget-from-workbook.ps1",
    "branchopsdaily_from_budget": REPO_ROOT / "scripts" / "repair-live-branchopsdaily-from-budget.ps1",
    "replace_live_sa1300_flows": REPO_ROOT / "scripts" / "replace-live-sa1300-flows.ps1",
    "late_order_sync": REPO_ROOT / "scripts" / "repair-live-sa1300-late-order-sync.ps1",
    "late_order_replay": REPO_ROOT / "scripts" / "repair-live-late-orders-from-sa1300-runs.ps1",
    "late_order_parser": REPO_ROOT / "scripts" / "parse-sa1300-late-orders.py",
    "authenticated_portal_capture": REPO_ROOT / "scripts" / "capture-authenticated-portal-routes.cjs",
    "current_state_from_workbooks": REPO_ROOT / "scripts" / "repair-live-current-state-from-parsed-workbooks.ps1",
    "quote_line_integrity": REPO_ROOT / "scripts" / "repair-live-quote-line-integrity.ps1",
    "quote_retention_xrm": REPO_ROOT / "scripts" / "repair-live-quote-retention-xrm.ps1",
    "live_flow_defects": REPO_ROOT / "scripts" / "repair-southern-alberta-live-flow-defects.ps1",
    "quote_tsr_assignment": REPO_ROOT / "scripts" / "repair-live-quote-tsr-assignments.ps1",
    "operational_duplicates": REPO_ROOT / "scripts" / "repair-live-operational-duplicates.ps1",
    "freight_seed_verification": REPO_ROOT / "scripts" / "seed-freight-verification-rows.ps1",
    "freight_verify_portal": REPO_ROOT / "scripts" / "verify-freight-portal.cjs",
    "sa1300_replacement_cleanup": REPO_ROOT / "scripts" / "remove-disabled-sa1300-replacement-flows.ps1",
}
FINALIZE_SCRIPT = REPO_ROOT / "finalize-qfu-audit.ps1"


def read_script(name: str) -> str:
    return SCRIPTS[name].read_text(encoding="utf-8")


class VerificationScriptContractTests(unittest.TestCase):
    def test_finalize_audit_packages_current_root_outputs_without_regenerating_stale_files(self) -> None:
        script = FINALIZE_SCRIPT.read_text(encoding="utf-8")
        self.assertIn('& python ".\\build-audit-package.py" --root $root', script)
        self.assertNotIn('generate-final-audit-artifacts.py', script)

    def test_runtime_readiness_prefers_live_r2_zbo_variants(self) -> None:
        script = read_script("runtime_readiness")
        self.assertIn('DisplayNamePattern = "4171-BackOrder-Update-ZBO*"', script)
        self.assertIn('DisplayNamePattern = "4172-BackOrder-Update-ZBO*"', script)
        self.assertIn('DisplayNamePattern = "4173-BackOrder-Update-ZBO*"', script)
        self.assertIn('PreferredDisplayNameRegex = "^4171-BackOrder-Update-ZBO-Live-R\\d+$"', script)
        self.assertIn("function Get-FlowDisplayNameRank", script)

    def test_runtime_readiness_uses_snapshot_moment_for_exception_freshness(self) -> None:
        script = read_script("runtime_readiness")
        self.assertIn("function Get-DateTimeValue", script)
        self.assertIn("function Get-SnapshotMoment", script)
        self.assertIn("Sort-Object { Get-SnapshotMoment -Row $_ } -Descending", script)
        self.assertIn("Sort-Object { Get-DateTimeValue -Value $_.createdon } -Descending", script)

    def test_flow_health_prefers_live_r2_zbo_variants(self) -> None:
        script = read_script("flow_health")
        self.assertIn('DisplayNamePattern = "4171-BackOrder-Update-ZBO*"', script)
        self.assertIn('DisplayNamePattern = "4172-BackOrder-Update-ZBO*"', script)
        self.assertIn('DisplayNamePattern = "4173-BackOrder-Update-ZBO*"', script)
        self.assertIn('PreferredDisplayNameRegex = "^4173-BackOrder-Update-ZBO-Live-R\\d+$"', script)
        self.assertIn("function Get-FlowDisplayNameRank", script)

    def test_flow_health_records_variant_overlap_and_state_fallback(self) -> None:
        script = read_script("flow_health")
        self.assertIn("function Get-MatchingAdminFlows", script)
        self.assertIn("function Get-AdminFlowStateLabel", script)
        self.assertIn("function Get-ExpectedBatchTriggerLabel", script)
        self.assertIn('return $(if ([bool]$Flow.Enabled) { "Enabled" } else { "Disabled" })', script)
        self.assertIn("matching_flow_variants", script)
        self.assertIn("enabled_flow_variants", script)
        self.assertIn("enabled_variant_count", script)
        self.assertIn("overlap_detected", script)
        self.assertIn("expected_batch_trigger_label", script)
        self.assertIn("latest_batch_trigger_matches_expected_batch_trigger_label", script)
        self.assertIn("latest_batch_trigger_matches_any_variant", script)
        self.assertIn('switch ($SourceFamily.ToUpperInvariant()) {', script)
        self.assertIn('"GL060 Inbox PDF Ingress"', script)
        self.assertIn('"Freight Inbox Import"', script)

    def test_flow_health_tracks_4172_freight_ingress(self) -> None:
        script = read_script("flow_health")
        self.assertIn('DisplayNamePattern = "4172-Freight-Inbox-Ingress"', script)
        self.assertIn('SourceFamily = "FREIGHT"', script)
        self.assertIn("queued_rawdocument_count", script)

    def test_budget_active_detection_uses_formatted_label_fallback(self) -> None:
        runtime_script = read_script("runtime_readiness")
        opsdaily_script = read_script("opsdaily_freshness")
        self.assertIn("function Get-FormattedLabel", runtime_script)
        self.assertIn('Get-FormattedLabel -Row $Row -FieldName "qfu_isactive"', runtime_script)
        self.assertIn('"yes" { return $true }', runtime_script)
        self.assertIn('"false" { return $true }', runtime_script)
        self.assertIn("function Get-FormattedLabel", opsdaily_script)
        self.assertIn('Get-FormattedLabel -Row $Row -FieldName "qfu_isactive"', opsdaily_script)
        self.assertIn('"yes" { return $true }', opsdaily_script)
        self.assertIn('"false" { return $true }', opsdaily_script)

    def test_branch_summary_refresh_matches_runtime_24h_quote_age_rule(self) -> None:
        script = read_script("branch_summary_refresh")
        self.assertIn("function Days-Between", script)
        self.assertIn("Floor(($Later - $Earlier).TotalDays)", script)
        self.assertNotIn("Floor(($Later.Date - $Earlier.Date).TotalDays)", script)

    def test_budget_from_workbook_blocks_stale_overwrites_by_default(self) -> None:
        script = read_script("budget_from_workbook")
        self.assertIn("[switch]$AllowStaleOverwrite", script)
        self.assertIn("function Get-LatestBranchOpsDailyMarker", script)
        self.assertIn("function Get-LatestBudgetBatch", script)
        self.assertIn("Stale SA1300 workbook repair blocked.", script)
        self.assertIn("-AllowOlderSnapshotOverwrite:$AllowStaleOverwrite", script)

    def test_branchopsdaily_repair_blocks_older_budget_snapshots_by_default(self) -> None:
        script = read_script("branchopsdaily_from_budget")
        self.assertIn("[switch]$AllowOlderSnapshotOverwrite", script)
        self.assertIn("function Get-LatestBranchOpsDailySnapshot", script)
        self.assertIn("Older qfu_budget snapshot", script)
        self.assertIn("Use -AllowOlderSnapshotOverwrite only after documenting the newer live state.", script)

    def test_replace_live_sa1300_flows_sanitizes_dataverse_actions_and_connections(self) -> None:
        script = read_script("replace_live_sa1300_flows")
        self.assertIn("function Sync-QfuSharedConnectionReferences", script)
        self.assertIn("function Sanitize-DataverseActions", script)
        self.assertIn("sanitized_removed_fields", script)
        self.assertIn("Sync-QfuSharedConnectionReferences -Connection $connection -TemplateBindings $templateBindings", script)

    def test_late_order_sync_patches_sa1300_with_snapshot_and_batch_waits(self) -> None:
        script = read_script("late_order_sync")
        self.assertIn('Create_Late_Order_Table', script)
        self.assertIn('Create_Late_Order_Batch', script)
        self.assertIn('List_Existing_Budget_Import_Batch', script)
        self.assertIn("$expectedLateOrderTableRange = \"'On-Time_ Late Order Review '!A2:Q5000\"", script)
        self.assertIn("Material Group", script)
        self.assertIn("opsdaily_waits_for_late_order_batch", script)
        self.assertIn("budget_batch_waits_for_late_order_batch", script)

    def test_late_order_replay_recovers_sa1300_attachments_and_upserts_dataverse(self) -> None:
        script = read_script("late_order_replay")
        self.assertIn("outputsLink.uri", script)
        self.assertIn("SA1300*.xlsx", script)
        self.assertIn("parse-sa1300-late-orders.py", script)
        self.assertIn('EntityLogicalName "qfu_lateorderexception"', script)
        self.assertIn('EntityLogicalName "qfu_ingestionbatch"', script)
        self.assertIn('qfu_sourcefamily = "SA1300-LATEORDER"', script)
        self.assertIn("qfu_branchslug = [string]$Record.qfu_branchslug", script)

    def test_late_order_parser_uses_material_group_in_source_key(self) -> None:
        script = read_script("late_order_parser")
        self.assertIn("material_group = as_text(row[12])", script)
        self.assertIn("slugify(material_group or 'material')", script)
        self.assertIn("slugify(item_category or 'line')", script)

    def test_authenticated_portal_capture_uses_fresh_page_per_route(self) -> None:
        script = read_script("authenticated_portal_capture")
        self.assertIn("async function captureRoute(context, route, outputDir)", script)
        self.assertIn("const page = await context.newPage();", script)
        self.assertIn("await page.close().catch(() => {});", script)
        self.assertIn("results.push(await captureRoute(context, route, outputDir));", script)

    def test_current_state_workbook_repair_deletes_duplicate_backorders(self) -> None:
        script = read_script("current_state_from_workbooks")
        self.assertIn('Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_backorder"', script)
        self.assertIn('$Connection.Delete("qfu_backorder", [guid]$duplicateId)', script)
        self.assertIn("$deduped += 1", script)

    def test_quote_line_integrity_collapses_duplicate_quotes_before_orphans(self) -> None:
        script = read_script("quote_line_integrity")
        self.assertIn("function Get-QuoteWorkingSet", script)
        self.assertIn("Get-LatestRecord -Records @($groups[$canonicalSourceId].ToArray())", script)
        self.assertIn('$connection.Delete("qfu_quote", [guid]$removedQuoteId)', script)
        self.assertIn("removed_duplicate_quote_ids", script)
        self.assertIn("[bool]$ReactivateQuotesWithRecoveredLines = $true", script)
        self.assertIn("[switch]$AllowQuoteCleanup", script)
        self.assertIn("reactivated_quotes", script)
        self.assertIn("preserved_orphan_quotes", script)

    def test_live_flow_defects_disable_quote_cleanup_by_default(self) -> None:
        script = read_script("live_flow_defects")
        self.assertIn('$expectedCleanupForeach = "@json(\'[]\')"', script)
        self.assertIn('Quote cleanup is disabled on the live SP830 flow', script)
        self.assertIn('updated_cleanup_gate', script)

    def test_quote_retention_xrm_repair_disables_cleanup_loop_and_reactivates_workflow(self) -> None:
        script = read_script("quote_retention_xrm")
        self.assertIn('DisplayName = "4171-QuoteFollowUp-Import-Staging"', script)
        self.assertIn('function Repair-QuoteWorkflowJson', script)
        self.assertIn('$expectedCleanupForeach = "@json(\'[]\')"', script)
        self.assertIn('Set-CrmRecord -conn $connection -EntityLogicalName workflow -Id $workflowRecord.workflowid -Fields @{ clientdata = $clientData }', script)
        self.assertIn('Set-CrmRecordState -conn $connection -EntityLogicalName workflow -Id $workflowRecord.workflowid -StateCode Activated -StatusCode Activated', script)

    def test_quote_tsr_assignment_repair_backfills_header_owner_from_line_tsr_name(self) -> None:
        script = read_script("quote_tsr_assignment")
        self.assertIn('EntityLogicalName "qfu_quote"', script)
        self.assertIn('EntityLogicalName "qfu_quoteline"', script)
        self.assertIn("function Get-PreferredTsrAssignment", script)
        self.assertIn("qfu_assignedto = $assignment.tsr_name", script)
        self.assertIn("line_tsr_name_conflicts", script)

    def test_operational_duplicate_repair_deletes_current_rows_and_skips_delivery_history(self) -> None:
        script = read_script("operational_duplicates")
        self.assertIn('AllowInactiveHistoryDuplicates = $false', script)
        self.assertIn('AllowInactiveHistoryDuplicates = $true', script)
        self.assertIn('action = "delete-duplicates"', script)
        self.assertIn('action = "skip-history"', script)

    def test_freight_seed_verification_supports_branch_specific_rows(self) -> None:
        script = read_script("freight_seed_verification")
        self.assertIn("[string]$BranchCode = \"4171\"", script)
        self.assertIn('"4172" = [pscustomobject]@{ BranchSlug = "4172-lethbridge"', script)
        self.assertIn('qfu_reference = $portalReference', script)
        self.assertIn('qfu_name = "$BranchCode Freight Portal Verification Row"', script)
        self.assertIn('portal_url = ("<URL> script)

    def test_freight_verify_portal_supports_branch_specific_base_urls(self) -> None:
        script = read_script("freight_verify_portal")
        self.assertIn("function getBranchConfig(branchCode)", script)
        self.assertIn('const branchCode = getArg("branchCode", "4171");', script)
        self.assertIn('const portalMarker = getArg("portalMarker", `QFU-FREIGHT-PORTAL-VERIFY-${branchCode}`);', script)
        self.assertIn('const archiveMarker = getArg("archiveMarker", `QFU-FREIGHT-ARCHIVE-VERIFY-${branchCode}`);', script)
        self.assertIn('branchCode,\n    branchSlug:', script)

    def test_sa1300_replacement_cleanup_keeps_latest_variant_and_uses_remove_admin_flow(self) -> None:
        script = read_script("sa1300_replacement_cleanup")
        self.assertIn('[string]$BranchCode = "4172"', script)
        self.assertIn('"{0}-Budget-Update-SA1300-R*" -f $BranchCode', script)
        self.assertIn('"{0}-Budget-Update-SA1300-R7" -f $BranchCode', script)
        self.assertIn("Remove-AdminFlow -EnvironmentName $TargetEnvironmentName -FlowName $flow.FlowName", script)
        self.assertIn('$action = if ($Apply) { "remove" } else { "would-remove" }', script)
        self.assertIn('$action = "keep"', script)


if __name__ == "__main__":
    unittest.main()
