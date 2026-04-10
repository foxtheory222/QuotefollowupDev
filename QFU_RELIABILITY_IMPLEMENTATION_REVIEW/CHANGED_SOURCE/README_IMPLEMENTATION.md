# QFU Reliability Implementation

This repository now contains a focused Southern Alberta reliability / regression-hardening pass.

Scope of this pass:

- reliability fixes only
- regression-hardening guardrails
- AI/developer conventions
- dry-run diagnostic tooling
- static verification outputs

This pass intentionally did **not**:

- deploy to Power Pages
- mutate live Dataverse data
- create a new `qfu_deliverynotpgi` base-row writer
- rename schema
- perform broad UI or architecture rewrites

The review package for this pass is produced separately as:

- `QFU_RELIABILITY_IMPLEMENTATION_REVIEW_BUNDLE_2026-04-08.zip`

Use these files first:

- `CONVENTIONS.md`
- `IMPLEMENTATION_SUMMARY.md`
- `CHANGE_MAP.md`
- `AUTHORITATIVE_FILES_USED.md`
- `KNOWN_LIMITATIONS.md`
- `NON_IMPLEMENTED.md`
