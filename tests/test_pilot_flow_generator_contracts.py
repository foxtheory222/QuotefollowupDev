import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
GENERATOR = REPO_ROOT / "scripts" / "create-southern-alberta-pilot-flow-solution.ps1"


def read_generator() -> str:
    return GENERATOR.read_text(encoding="utf-8")


class PilotFlowGeneratorContractTests(unittest.TestCase):
    def test_quote_flow_uses_branch_scoped_header_and_line_identity(self) -> None:
        script = read_generator()
        self.assertIn("function Update-QuoteFlow", script)
        self.assertIn(
            "Set-FieldValue -Map $checkQuoteParameters -Name '$filter' -Value "
            "\"qfu_sourceid eq '@{concat(parameters('qfu_QFU_BranchCode'), '|SP830CA|', "
            "items('Apply_to_each_quote_line')?['quotenumber'])}' and (qfu_active eq true or qfu_active eq null)\"",
            script,
        )
        self.assertIn(
            "Set-FieldValue -Map $checkLineParameters -Name '$filter' -Value "
            "\"qfu_sourceid eq '@{concat(parameters('qfu_QFU_BranchCode'), '|SP830CA|', "
            "items('Apply_to_each_quote_line')?['quotenumber'], '|', items('Apply_to_each_quote_line')?['linenumber'])}'\"",
            script,
        )
        self.assertIn('Set-FieldValue -Map $updateHeader -Name "item/qfu_sourceid"', script)
        self.assertIn('Set-FieldValue -Map $updateHeader -Name "item/qfu_branchcode"', script)
        self.assertIn('Set-FieldValue -Map $updateHeader -Name "item/qfu_sourcefamily" -Value "SP830CA"', script)
        self.assertIn('Set-FieldValue -Map $createHeader -Name "item/qfu_sourceid"', script)
        self.assertIn('Set-FieldValue -Map $createHeader -Name "item/qfu_branchcode"', script)
        self.assertIn('Set-FieldValue -Map $itemMap -Name "item/qfu_sourceid" -Value $quoteLineSourceIdExpression', script)

    def test_quote_flow_defaults_cleanup_off_and_gates_missing_header_deactivation(self) -> None:
        script = read_generator()
        self.assertIn("Initialize_CurrentQuoteSnapshotKeys", script)
        self.assertIn(
            'Set-ParameterDefault -ParametersObject $params -Name "qfu_QFU_EnableQuoteCleanup" -DefaultValue $false -Type "boolean"',
            script,
        )
        self.assertIn("List_Existing_Active_Quotes", script)
        self.assertIn("Filter_Missing_Active_Quotes", script)
        self.assertIn("Deactivate_Missing_Quotes", script)
        self.assertIn(
            '"@if(equals(parameters(\'qfu_QFU_EnableQuoteCleanup\'), true), coalesce(body(\'Filter_Missing_Active_Quotes\'), json(\'[]\')), json(\'[]\'))"',
            script,
        )
        self.assertIn('"item/qfu_active" = $false', script)
        self.assertIn('"item/qfu_inactiveon" = "@variables(\'QuoteSnapshotProcessedOn\')"', script)

    def test_backorder_flow_uses_monotonic_upsert_and_inactivation(self) -> None:
        script = read_generator()
        self.assertIn("function Update-BackorderFlow", script)
        self.assertNotIn("Delete_Old_BackOrders", script)
        self.assertIn("List_Existing_Active_BackOrders", script)
        self.assertIn("Check_Existing_Active_BackOrder", script)
        self.assertIn("Filter_Missing_Active_BackOrders", script)
        self.assertIn("Deactivate_Missing_BackOrders", script)
        self.assertIn(
            "'$filter' = \"qfu_sourceid eq '@{outputs('Compose_BackOrder_SourceId')}' and (qfu_active eq true or qfu_active eq null)\"",
            script,
        )
        self.assertIn('"item/qfu_active" = $false', script)
        self.assertIn('"item/qfu_inactiveon" = "@variables(\'DeliverySnapshotProcessedOn\')"', script)

    def test_backorder_ingestion_batch_tracks_effective_live_variant_name(self) -> None:
        script = read_generator()
        self.assertIn(
            '-FlowNameExpression "@concat(parameters(\'qfu_QFU_BranchCode\'), \'-$(Get-EffectiveTargetSuffix -Template $Template)\')"',
            script,
        )


if __name__ == "__main__":
    unittest.main()
