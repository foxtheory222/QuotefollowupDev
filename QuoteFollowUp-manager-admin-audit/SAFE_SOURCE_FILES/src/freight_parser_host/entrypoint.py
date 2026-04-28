from qfu_freight_parser.host_contract import extract_document_payload, validate_document_payload
from qfu_freight_parser.processor import process_hosted_document


def handle_hosted_parser_request(payload, client=None):
    source_id = ""
    try:
        document = extract_document_payload(payload)
        source_id = str(document.get("source_id", document.get("import_batch_id", ""))).strip()
        validate_document_payload(document)
        if client is None:
            from qfu_freight_parser.dataverse_client import DataverseClient

            client = DataverseClient.from_env()
        return 200, process_hosted_document(payload, client=client)
    except ValueError as exc:
        return 400, {"status": "error", "source_id": source_id, "error": str(exc)}
    except Exception as exc:
        return 500, {"status": "error", "source_id": source_id, "error": str(exc)}
