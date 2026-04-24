import datetime as dt

from .host_contract import process_parse_request


ENTITY_SET = "qfu_freightworkitems"
PRESERVED_TEXT_FIELDS = (
    "qfu_status",
    "qfu_ownername",
    "qfu_owneridentifier",
    "qfu_comment",
    "qfu_commentupdatedbyname",
)
PRESERVED_DATE_FIELDS = (
    "qfu_claimedon",
    "qfu_commentupdatedon",
    "qfu_archivedon",
)


def _utc_now_iso():
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _parse_datetime(value):
    if value is None:
        return None
    if isinstance(value, dt.datetime):
        if value.tzinfo is None:
            return value.replace(tzinfo=dt.timezone.utc)
        return value.astimezone(dt.timezone.utc)

    text = str(value).strip()
    if not text:
        return None
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = dt.datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def _coerce_record_fields(record):
    fields = {}
    for key, value in record.items():
        if not str(key).startswith("qfu_"):
            continue
        if value is None:
            continue
        if isinstance(value, str) and not value.strip():
            continue
        fields[key] = value
    return fields


def _escape_odata_string(value):
    return str(value).replace("'", "''")


def _latest_activity_value(existing, observed_on):
    candidates = [_parse_datetime(existing.get("qfu_lastactivityon")), _parse_datetime(existing.get("qfu_commentupdatedon")), _parse_datetime(existing.get("qfu_claimedon")), _parse_datetime(observed_on)]
    candidates = [candidate for candidate in candidates if candidate is not None]
    if not candidates:
        return observed_on
    return max(candidates).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _query_freight_rows(client, filter_expr):
    return client.list_records(
        ENTITY_SET,
        select=[
            "qfu_freightworkitemid",
            "qfu_sourceid",
            "qfu_status",
            "qfu_ownername",
            "qfu_owneridentifier",
            "qfu_claimedon",
            "qfu_comment",
            "qfu_commentupdatedon",
            "qfu_commentupdatedbyname",
            "qfu_lastactivityon",
            "qfu_isarchived",
            "qfu_archivedon",
            "modifiedon",
        ],
        filter_expr=filter_expr,
        top=5,
        orderby="modifiedon desc",
    )


def _query_existing_record(client, record):
    source_id = str(record.get("qfu_sourceid", "")).strip()
    return _query_freight_rows(client, f"qfu_sourceid eq '{_escape_odata_string(source_id)}'")


def upsert_freight_workitems(client, records):
    inserted = 0
    updated = 0
    warnings = []
    observed_on = _utc_now_iso()

    for record in records:
        source_id = str(record.get("qfu_sourceid", "")).strip()
        if not source_id:
            raise ValueError("Parsed freight record is missing qfu_sourceid.")

        existing_rows = _query_existing_record(client, record)
        existing = existing_rows[0] if existing_rows else None
        if len(existing_rows) > 1:
            warnings.append(f"Duplicate freight rows already existed for freight identity {source_id}; updated latest row only.")

        fields = _coerce_record_fields(record)
        fields["qfu_lastseenon"] = observed_on
        fields["qfu_lastactivityon"] = observed_on
        fields["qfu_isarchived"] = False

        if existing is not None:
            for field_name in PRESERVED_TEXT_FIELDS:
                existing_value = existing.get(field_name)
                if existing_value is not None and str(existing_value).strip():
                    fields[field_name] = existing_value
            for field_name in PRESERVED_DATE_FIELDS:
                existing_value = existing.get(field_name)
                if existing_value:
                    fields[field_name] = existing_value
            fields["qfu_lastactivityon"] = _latest_activity_value(existing, observed_on)
            client.update_record(ENTITY_SET, existing["qfu_freightworkitemid"], fields)
            updated += 1
            continue

        client.create_record(ENTITY_SET, fields)
        inserted += 1

    return {
        "inserted": inserted,
        "updated": updated,
        "warnings": warnings,
        "observed_on": observed_on,
    }


def process_hosted_document(payload, client):
    parsed = process_parse_request(payload)
    upsert_result = upsert_freight_workitems(client, parsed["records"])
    warnings = list(upsert_result["warnings"])
    warning_summary = f" Warnings: {' | '.join(warnings)}" if warnings else ""
    batch_note = (
        f"Normalized {parsed['input_rows']} source row(s) into "
        f"{parsed['normalized_records']} freight work item(s).{warning_summary}"
    )

    return {
        "status": "processed",
        "source_id": parsed["source_id"],
        "branch_code": parsed["branch_code"],
        "source_family": parsed["source_family"],
        "source_filename": parsed["source_filename"],
        "input_rows": parsed["input_rows"],
        "normalized_records": parsed["normalized_records"],
        "collapsed_group_rows": parsed["collapsed_group_rows"],
        "inserted": upsert_result["inserted"],
        "updated": upsert_result["updated"],
        "warnings": warnings,
        "batch_note": batch_note,
        "processed_on": upsert_result["observed_on"],
    }

