# Freight Parser Host

This Azure Functions app replaces the missing local freight queue consumer with a hosted parser path.

## Route

- `POST /api/processfreightdocument`

## Request Contract

```json
{
  "document": {
    "source_id": "4171|raw|FREIGHT_REDWOOD|<guid>",
    "branch_code": "4171",
    "branch_slug": "4171-calgary",
    "region_slug": "southern-alberta",
    "source_family": "FREIGHT_REDWOOD",
    "source_filename": "Applied Canada 417100 Invoice Report.xlsx",
    "raw_content_base64": "<base64 attachment bytes>"
  }
}
```

## Environment

- `QFU_DATAVERSE_URL`
- Standard `DefaultAzureCredential` variables for local development or hosted managed identity

## Notes

- The hosted parser reuses the same Python freight parsing rules consumed by local repair tooling.
- The ingress Power Automate flow should create `qfu_rawdocument` and `qfu_ingestionbatch` first, then call this function, then stamp those rows from the returned status/counts.
