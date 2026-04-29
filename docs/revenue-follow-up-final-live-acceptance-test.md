# Final Live Acceptance Test

DO NOT EXECUTE YET.

Phase 8 is partial, so this checklist is not ready for user execution. Run it only after the production roster, Manager/GM/Admin memberships, final privilege matrix, and role-specific test users are complete.

## Blockers First

- Fill verified staff primary emails.
- Link staff to Dataverse systemuser.
- Add verified Manager, GM, and Admin memberships.
- Approve and apply final QFU security role privileges.
- Assign branch teams/access teams.
- Validate with separate staff, manager, and admin users.
- Complete TestRecipientOnly alert validation before Live mode.

## Final Checklist

1. Open `https://operationscenter.powerappsportals.com/`.
2. Confirm branch navigation shows Dashboard, Workbench, Quotes, Back Orders, Ready to Ship, Freight Recovery, and Analytics.
3. Confirm Follow-Up Queue, Overdue Quotes, Team Progress, Backorder Lines, and Freight Ledger are absent.
4. Sign in as regular staff and confirm Manager Panel and Admin Panel are hidden.
5. Open Workbench as staff.
6. Confirm My Queue loads.
7. Use All, TSR, CSSR, and Unassigned queue filters.
8. Add a sticky note to a safe item.
9. Log a call on a safe item.
10. Route a safe item to CSSR.
11. Escalate a safe item to TSR.
12. Sign in as Manager/GM and confirm Manager Panel appears.
13. Confirm Manager Panel shows team stats and staff workload.
14. Sign in as Admin and confirm Admin Panel appears.
15. Open Staff, Branch Memberships, Staff Alias Mapping, Policies, Assignment Exceptions, Work Items, Work Item Actions, and Alert Logs.
16. Confirm Identity Setup and Role Setup views open.
17. Run alert dry-run and confirm logs only.
18. Run TestRecipientOnly alert to the verified test recipient.
19. Confirm no production emails, Teams messages, or live digests are sent.
20. Confirm duplicate work item, assignment exception, and alert dedupe keys remain 0.
