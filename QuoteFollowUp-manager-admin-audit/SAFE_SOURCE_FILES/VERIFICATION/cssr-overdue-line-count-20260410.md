# CSSR Overdue Line Count Verification

- Generated: 2026-04-10
- Site: `<URL>
- Runtime source refreshed from live before edit: 2026-04-10 08:48 -06:00
- Runtime upload completed after patch: 2026-04-10

## Requested Behavior

The CSSR overdue backorder leaderboard must total by overdue backorder line count, not only by grouped/distinct order count.

## Implemented Runtime Changes

- `buildCssrLeaderboardRows(...)` now ranks CSSRs by `overdueBackorderLineCount` first, then grouped order count.
- `buildRegionalCssrLeaderboardRows(...)` now ranks region rows by `overdueBackorderLineCount` first.
- `renderCssrLeaderboardTable(...)` now:
  - uses overdue line count for severity
  - labels the visible metric as `Overdue Lines`
  - shows grouped order count as subtitle context
- Branch and regional CSSR leaderboard footnotes now state that ranking is by overdue backorder line count.

## Live Browser Verification

Regional page extraction after upload returned the first CSSR card as:

```text
1
4172 / COLBY JAMES MEYER

$4,968.40 overdue value | Oldest 261 days | 5 orders

OVERDUE LINES
43
```

This confirms:

1. The visible total is now line-based (`43`).
2. The grouped order count is preserved as supporting context (`5 orders`).
3. The label shown to users is `Overdue Lines`.

## Notes

- Direct route check against `<URL> returned `Page Not Found`, so verification for this change was completed against the live Southern Alberta regional page where the CSSR leaderboard is actively rendered.
