import base64
import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
HOST_ROOT = REPO_ROOT / "src" / "freight_parser_host"
if str(HOST_ROOT) not in sys.path:
    sys.path.insert(0, str(HOST_ROOT))

from entrypoint import handle_hosted_parser_request  # noqa: E402
from qfu_freight_parser.host_contract import process_parse_request  # noqa: E402


def resolve_existing_attachments_root(*candidates: Path) -> Path:
    sentinel = Path("4171") / "Applied Canada 417100 Invoice Report.xlsx"
    for candidate in candidates:
        if candidate.exists() and (candidate / sentinel).exists():
            return candidate
    searched = ", ".join(str(candidate) for candidate in candidates)
    raise FileNotFoundError(f"Hosted parser fixture root not found. Checked: {searched}")


ATTACHMENTS_ROOT = resolve_existing_attachments_root(
    REPO_ROOT / "output" / "freight-samples" / "attachments",
    REPO_ROOT.parent / "output" / "freight-samples" / "attachments",
)
FREIGHT_GENERATOR = REPO_ROOT / "scripts" / "create-southern-alberta-freight-flow-solution.ps1"
FREIGHT_QUEUE_PROCESSOR = REPO_ROOT / "scripts" / "process-freight-inbox-queue.ps1"
FREIGHT_INVOICE_SURVIVOR_RESTORE = REPO_ROOT / "scripts" / "repair-live-freight-invoice-survivors.ps1"


class FakeDataverseClient:
    def __init__(self, existing_by_source_id=None):
        self.existing_by_source_id = existing_by_source_id or {}
        self.created = []
        self.updated = []

    def _extract_source_id(self, filter_expr):
        prefix = "qfu_sourceid eq '"
        if prefix not in filter_expr:
            raise AssertionError(f"Unexpected filter expression: {filter_expr}")
        return filter_expr.split(prefix, 1)[1].rsplit("'", 1)[0].replace("''", "'")

    def list_records(self, entity_set, *, select=None, filter_expr=None, top=None, orderby=None):
        if "qfu_sourceid eq '" in filter_expr:
            source_id = self._extract_source_id(filter_expr)
            return list(self.existing_by_source_id.get(source_id, []))
        raise AssertionError(f"Unexpected filter expression: {filter_expr}")

    def create_record(self, entity_set, fields):
        self.created.append((entity_set, dict(fields)))
        return {"entity_set": entity_set}

    def update_record(self, entity_set, record_id, fields):
        self.updated.append((entity_set, record_id, dict(fields)))


class FreightHostedParserContractTests(unittest.TestCase):
    def _payload_for(self, relative_path, branch_code, branch_slug, source_family):
        file_path = ATTACHMENTS_ROOT / relative_path
        return {
            "document": {
                "source_id": f"{branch_code}|raw|{source_family}|unit-test",
                "branch_code": branch_code,
                "branch_slug": branch_slug,
                "region_slug": "southern-alberta",
                "source_family": source_family,
                "source_filename": file_path.name,
                "raw_content_base64": base64.b64encode(file_path.read_bytes()).decode("ascii"),
            }
        }

    def test_hosted_parser_creates_records_from_redwood_payload(self):
        payload = self._payload_for(
            Path("4171") / "Applied Canada 417100 Invoice Report.xlsx",
            "4171",
            "4171-calgary",
            "FREIGHT_REDWOOD",
        )
        client = FakeDataverseClient()

        status_code, body = handle_hosted_parser_request(payload, client=client)

        self.assertEqual(status_code, 200)
        self.assertEqual(body["status"], "processed")
        self.assertEqual(body["normalized_records"], 3)
        self.assertEqual(body["inserted"], 3)
        self.assertEqual(body["updated"], 0)
        self.assertEqual(len(client.created), 3)
        self.assertEqual(client.updated, [])

    def test_hosted_parser_preserves_existing_freight_status_and_owner_fields(self):
        payload = self._payload_for(
            Path("4172") / "UPS Canada Invoices previous week Report [F06] by control# [APICAPIC4955] 871382.xls",
            "4172",
            "4172-lethbridge",
            "FREIGHT_UPS_F06",
        )
        parsed = process_parse_request(payload)
        source_id = parsed["records"][0]["qfu_sourceid"]
        client = FakeDataverseClient(
            existing_by_source_id={
                source_id: [
                    {
                        "qfu_freightworkitemid": "00000000-0000-0000-0000-000000000123",
                        "qfu_status": "Closed",
                        "qfu_ownername": "Existing Owner",
                        "qfu_owneridentifier": "owner-123",
                        "qfu_claimedon": "2026-04-20T10:00:00Z",
                        "qfu_comment": "Keep this note",
                        "qfu_commentupdatedon": "2026-04-20T10:05:00Z",
                        "qfu_commentupdatedbyname": "Dispatcher",
                        "qfu_lastactivityon": "2026-04-20T10:05:00Z",
                        "qfu_isarchived": False,
                        "qfu_archivedon": None,
                        "modifiedon": "2026-04-20T10:06:00Z",
                    }
                ]
            }
        )

        status_code, body = handle_hosted_parser_request(payload, client=client)

        self.assertEqual(status_code, 200)
        self.assertEqual(body["inserted"], 0)
        self.assertEqual(body["updated"], 1)
        self.assertEqual(len(client.updated), 1)
        updated_fields = client.updated[0][2]
        self.assertEqual(updated_fields["qfu_status"], "Closed")
        self.assertEqual(updated_fields["qfu_ownername"], "Existing Owner")
        self.assertEqual(updated_fields["qfu_owneridentifier"], "owner-123")
        self.assertEqual(updated_fields["qfu_comment"], "Keep this note")

    def test_hosted_parser_keeps_same_invoice_different_tracking_rows_separate(self):
        payload = self._payload_for(
            Path("4171") / "Purolator Invoices Report [F07] by control# [APICAPIC5141] 8738328.xls",
            "4171",
            "4171-calgary",
            "FREIGHT_PUROLATOR_F07",
        )
        parsed = process_parse_request(payload)
        source_id = parsed["records"][0]["qfu_sourceid"]
        client = FakeDataverseClient(
            existing_by_source_id={
                source_id: [
                    {
                        "qfu_freightworkitemid": "00000000-0000-0000-0000-000000000456",
                        "qfu_sourceid": source_id,
                        "qfu_status": "Investigating",
                        "qfu_ownername": "Existing Owner",
                        "qfu_owneridentifier": "owner-456",
                        "qfu_claimedon": "2026-04-20T10:00:00Z",
                        "qfu_comment": "Preserve live work note",
                        "qfu_commentupdatedon": "2026-04-20T10:05:00Z",
                        "qfu_commentupdatedbyname": "Dispatcher",
                        "qfu_lastactivityon": "2026-04-20T10:05:00Z",
                        "qfu_isarchived": False,
                        "qfu_archivedon": None,
                        "modifiedon": "2026-04-20T10:06:00Z",
                    }
                ]
            }
        )

        status_code, body = handle_hosted_parser_request(payload, client=client)

        self.assertEqual(status_code, 200)
        self.assertEqual(body["normalized_records"], 49)
        self.assertEqual(body["inserted"], 48)
        self.assertEqual(body["updated"], 1)
        self.assertEqual(len(client.created), 48)
        self.assertEqual(len(client.updated), 1)
        self.assertEqual(len({fields["qfu_sourceid"] for _, fields in client.created}), 48)
        self.assertTrue(all(fields["qfu_invoicenumber"] == "550256777" for _, fields in client.created))
        self.assertFalse(any("|invoice|" in fields["qfu_sourceid"] for _, fields in client.created))
        updated_fields = client.updated[0][2]
        self.assertEqual(updated_fields["qfu_sourceid"], source_id)
        self.assertEqual(updated_fields["qfu_status"], "Investigating")
        self.assertEqual(updated_fields["qfu_ownername"], "Existing Owner")
        self.assertEqual(updated_fields["qfu_comment"], "Preserve live work note")

    def test_hosted_parser_rejects_missing_document_payload(self):
        status_code, body = handle_hosted_parser_request({"document": {}})

        self.assertEqual(status_code, 400)
        self.assertEqual(body["status"], "error")
        self.assertIn("branch_code", body["error"])

    def test_freight_generator_invokes_hosted_parser_and_updates_dataverse_status_rows(self):
        script = FREIGHT_GENERATOR.read_text(encoding="utf-8")
        self.assertIn("qfu_Freight_HostedParserUrl", script)
        self.assertIn("qfu_Freight_HostedParserKey", script)
        self.assertIn("Invoke_Hosted_Freight_Processor", script)
        self.assertIn('type = "Http"', script)
        self.assertIn('"x-functions-key" = "@parameters(\'qfu_Freight_HostedParserKey\')"', script)
        self.assertIn("Update_Raw_Document_Processed", script)
        self.assertIn("Update_Ingestion_Batch_Processed", script)
        self.assertIn("Update_Raw_Document_Error", script)
        self.assertIn("Update_Ingestion_Batch_Error", script)
        self.assertIn("Hosted freight parser call is pending.", script)

    def test_local_queue_processor_does_not_fallback_to_invoice_identity(self):
        script = FREIGHT_QUEUE_PROCESSOR.read_text(encoding="utf-8")
        self.assertIn('Get-CrmRecords -conn $Connection -EntityLogicalName "qfu_freightworkitem" -FilterAttribute "qfu_sourceid"', script)
        self.assertNotIn("qfu_invoicenumber", script.split("function Get-ExistingFreightWorkItemRows", 1)[1].split("function Upsert-FreightWorkItems", 1)[0])

    def test_invoice_survivor_restore_only_repairs_nonredwood_invoice_survivors(self):
        script = FREIGHT_INVOICE_SURVIVOR_RESTORE.read_text(encoding="utf-8")
        self.assertIn('$sourceFamily -eq "FREIGHT_REDWOOD"', script)
        self.assertIn('$sourceId -notmatch "\\|invoice\\|"', script)
        self.assertIn('$sourceId -match "\\|invoice\\|"', script)
        self.assertIn("Merge-PreservedWorkState", script)
        self.assertIn("No matching parsed shipment-level records found", script)


if __name__ == "__main__":
    unittest.main()
