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
        source_id = self._extract_source_id(filter_expr)
        return list(self.existing_by_source_id.get(source_id, []))

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
                        "qfu_freightworkitemid": "<GUID>",
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


if __name__ == "__main__":
    unittest.main()
