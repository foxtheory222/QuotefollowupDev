# Known Limitations

- The exact `qfu_deliverynotpgi` base-row writer remains unproven in exported/source-controlled assets.
- Live Dataverse duplicate rows were not mutated in this pass.
- Budget flow hardening was implemented in the authoritative current generator source only. It was not deployed or validated against a newly generated/imported live flow package in this pass.
- The current repo did not contain a pre-existing authoritative `normalize-live-sa1300-current-budgets.ps1`; a new dry-run helper was created instead.
- Runtime diagnostics now expose failed/truncated datasets, but the page still degrades by returning empty arrays for failed fetches after emitting diagnostics. That is intentional for stability.
- The allow-list lint reports extra allow-list fields, but those extras were not trimmed in this pass to avoid detail-page regressions.
