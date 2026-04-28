import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_ROOT = REPO_ROOT / "scripts"
if str(SCRIPTS_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_ROOT))

from freight_parser import parse_freight_file  # noqa: E402


def resolve_existing_path(*candidates: Path) -> Path:
    sentinel = Path("4171") / "Applied Canada 417100 Invoice Report.xlsx"
    for candidate in candidates:
        if candidate.exists() and (candidate / sentinel).exists():
            return candidate

    searched = ", ".join(str(candidate) for candidate in candidates)
    raise FileNotFoundError(f"Fixture root not found. Checked: {searched}")


ATTACHMENTS_ROOT = resolve_existing_path(
    REPO_ROOT / "output" / "freight-samples" / "attachments",
    REPO_ROOT.parent / "output" / "freight-samples" / "attachments",
)


class FreightParserTests(unittest.TestCase):
    def parse_sample(self, relative_path, source_family, branch_code, branch_slug):
        return parse_freight_file(
            input_path=ATTACHMENTS_ROOT / relative_path,
            branch_code=branch_code,
            branch_slug=branch_slug,
            region_slug="southern-alberta",
            source_family=source_family,
            source_filename=Path(relative_path).name,
            import_batch_id=f"{branch_code}|batch|{source_family}",
        )

    def test_redwood_xlsx_maps_amounts(self):
        payload = self.parse_sample(
            Path("4171") / "Applied Canada 417100 Invoice Report.xlsx",
            "FREIGHT_REDWOOD",
            "4171",
            "4171-calgary",
        )
        self.assertEqual(payload["normalized_record_count"], 3)
        first = payload["records"][0]
        self.assertEqual(first["qfu_sourcefamily"], "FREIGHT_REDWOOD")
        self.assertTrue(first["qfu_totalamount"] > 0)
        self.assertTrue(first["qfu_sourcecarrier"])

    def test_loomis_xls_parses_charge_breakdown(self):
        payload = self.parse_sample(
            Path("4171") / "Loomis Invoices Report [F15] by control# [APICAPIC1096] 42200176.xls",
            "FREIGHT_LOOMIS_F15",
            "4171",
            "4171-calgary",
        )
        self.assertEqual(payload["normalized_record_count"], 2)
        first = payload["records"][0]
        self.assertAlmostEqual(first["qfu_totalamount"], 48.26, places=2)
        self.assertAlmostEqual(first["qfu_freightamount"], 23.34, places=2)
        self.assertAlmostEqual(first["qfu_fuelamount"], 11.35, places=2)

    def test_purolator_uses_charge_text_when_total_column_missing(self):
        payload = self.parse_sample(
            Path("4172") / "Purolator Invoices Report [F07] by control# [APICAPIC5141] 8892943.xls",
            "FREIGHT_PUROLATOR_F07",
            "4172",
            "4172-lethbridge",
        )
        self.assertEqual(payload["normalized_record_count"], 27)
        first = payload["records"][0]
        self.assertTrue(first["qfu_totalamount"] > 0)
        self.assertTrue(first["qfu_chargebreakdowntext"])

    def test_ups_duplicate_tracking_rows_collapse_to_one_record(self):
        payload = self.parse_sample(
            Path("4172") / "UPS Canada Invoices previous week Report [F06] by control# [APICAPIC4955] 871382.xls",
            "FREIGHT_UPS_F06",
            "4172",
            "4172-lethbridge",
        )
        self.assertEqual(payload["input_row_count"], 2)
        self.assertEqual(payload["normalized_record_count"], 1)
        self.assertEqual(payload["collapsed_group_rows"], 1)
        first = payload["records"][0]
        self.assertAlmostEqual(first["qfu_totalamount"], 339.72, places=2)

    def test_empty_redwood_file_is_supported(self):
        payload = self.parse_sample(
            Path("4173") / "Applied Canada 417300 Invoice Report.xlsx",
            "FREIGHT_REDWOOD",
            "4173",
            "4173-medicine-hat",
        )
        self.assertEqual(payload["normalized_record_count"], 0)


if __name__ == "__main__":
    unittest.main()
