## Freight Worklist Sort Repair â€” April 21, 2026

### Issue
- Branch users reported that the Freight Worklist looked stale:
  - only one recent row appeared for some branches
  - many visible rows showed `Last updated` around April 10, 2026
- Live Dataverse freight data was already current on April 21, 2026, so the page behavior was misleading.

### Root Cause
- The shared Power Pages runtime sorted freight rows by:
  1. actionable/status grouping
  2. total amount
  3. last activity
- That ordering let older high-value open rows stay above fresher imports.
- Live validation against `results/freight-live-386-20260421.csv` showed:
  - `4171` top rows in the runtime order were mostly April 10 rows even though newer April 21 rows existed.
  - `4172` top rows also favored April 10 / April 14 high-value rows ahead of April 21 rows.
  - `4173` mixed April 21 with April 10 / April 14 rows for the same reason.

### Live Data Proof
- Flattened freight snapshot: `results/freight-live-386-20260421.csv`
- Branch counts from live Dataverse:
  - `4171`: `123` total, `114` open, latest open `qfu_lastseenon = Apr 21, 2026, 2:51 p.m.`
  - `4172`: `148` total, `147` open, latest open `qfu_lastseenon = Apr 21, 2026, 2:51 p.m.`
  - `4173`: `115` total, `115` open, latest open `qfu_lastseenon = Apr 21, 2026, 2:51 p.m.`

### Repair
- Updated the shared `freightSort` logic in the regional runtime so the default freight order now uses:
  1. actionable/status grouping
  2. latest activity
  3. total amount
  4. ship date
  5. source id
- Updated the toolbar copy so the default behavior is explicit to users.

### Why This Is Safe
- No Dataverse data was changed.
- No freight import or archive logic was changed.
- Only the default presentation order of already-loaded freight rows changed.
- Actionable/state grouping still stays first, so claimed/disputed/archive behavior is preserved.

### Validation
- Runtime contract coverage added in `tests/test_powerpages_runtime_contracts.py`.
- Replayed the new sort against the live flattened freight snapshot and confirmed the top rows for all three branches move to the April 21 import set instead of older April 10 high-value rows.
