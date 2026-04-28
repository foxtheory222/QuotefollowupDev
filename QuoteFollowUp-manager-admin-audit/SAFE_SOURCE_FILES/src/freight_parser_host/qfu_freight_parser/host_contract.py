import base64
import binascii
import tempfile
from pathlib import Path

from .core import parse_freight_file


REQUIRED_FIELDS = (
    "branch_code",
    "branch_slug",
    "region_slug",
    "source_filename",
    "raw_content_base64",
)


def extract_document_payload(payload):
    if not isinstance(payload, dict):
        raise ValueError("Hosted freight parser payload must be a JSON object.")
    document = payload.get("document", payload)
    if not isinstance(document, dict):
        raise ValueError("Hosted freight parser payload must contain a document object.")
    return document


def _require_text(payload, field_name):
    value = payload.get(field_name)
    if value is None:
        raise ValueError(f"Hosted freight parser payload is missing {field_name}.")
    text = str(value).strip()
    if not text:
        raise ValueError(f"Hosted freight parser payload has an empty {field_name}.")
    return text


def validate_document_payload(document):
    for field_name in REQUIRED_FIELDS:
        _require_text(document, field_name)
    return document


def _decode_attachment(raw_content_base64):
    try:
        return base64.b64decode(str(raw_content_base64), validate=True)
    except (ValueError, binascii.Error) as exc:
        raise ValueError("Hosted freight parser payload has invalid raw_content_base64.") from exc


def process_parse_request(payload):
    document = extract_document_payload(payload)
    validate_document_payload(document)

    source_filename = _require_text(document, "source_filename")
    suffix = Path(source_filename).suffix or ".bin"
    attachment_bytes = _decode_attachment(document["raw_content_base64"])

    with tempfile.TemporaryDirectory(prefix="qfu-freight-") as temp_root:
        input_path = Path(temp_root) / f"freight-input{suffix.lower()}"
        input_path.write_bytes(attachment_bytes)
        parsed = parse_freight_file(
            input_path=input_path,
            branch_code=_require_text(document, "branch_code"),
            branch_slug=_require_text(document, "branch_slug"),
            region_slug=_require_text(document, "region_slug"),
            source_family=str(document.get("source_family", "")).strip(),
            source_filename=source_filename,
            import_batch_id=str(document.get("source_id", document.get("import_batch_id", ""))).strip(),
        )

    return {
        "source_id": str(document.get("source_id", document.get("import_batch_id", ""))).strip(),
        "branch_code": parsed["branch_code"],
        "branch_slug": parsed["branch_slug"],
        "region_slug": parsed["region_slug"],
        "source_family": parsed["source_family"],
        "source_filename": parsed["source_filename"],
        "input_rows": parsed["input_row_count"],
        "normalized_records": parsed["normalized_record_count"],
        "collapsed_group_rows": parsed["collapsed_group_rows"],
        "records": parsed["records"],
    }
