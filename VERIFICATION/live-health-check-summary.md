# Live QFU Health Check

- Generated: 2026-04-09 15:49:26
- Environment: https://regionaloperationshub.crm.dynamics.com

## Included Checks

- operational current-state audit: `VERIFICATION\\operational-current-state-audit.md`
- overdue backorder consistency audit: `VERIFICATION\\overdue-backorder-consistency.md`
- backorder overdue day repair plan: `VERIFICATION\\backorder-overdue-day-repair.md`
- operational duplicate repair plan: `results\\live-operational-duplicate-repair.json`
- operational lifecycle backfill plan: `results\\live-operational-lifecycle-backfill.json`
- budget lineage check: `VERIFICATION\\budget-lineage-checks.md`
- flow health check: `results\\southern-alberta-flow-health-*.json`
- margin snapshot integrity audit: `VERIFICATION\\margin-snapshot-integrity.md`
- CSSR overdue order-count audit: `VERIFICATION\\cssr-overdue-order-counts.md`

Run command: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\\run-live-qfu-health-check.ps1`