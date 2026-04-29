# Final Live Beta Acceptance Test

DO NOT EXECUTE YET.

Beta readiness is blocked until QFU test accounts and TestRecipientOnly alert validation are complete.

## Blockers First

- Create QFU Test Staff, Manager, Admin, and No Access users.
- Give test users appropriate licenses and app/environment access.
- Create verified `qfu_staff` records linked to test `systemuser` rows.
- Create branch 4171 test memberships.
- Assign QFU Staff, Manager, Admin, and no-access security behavior.
- Configure verified TestRecipientOnly mailbox.
- Run controlled TestRecipientOnly alert and digest validation.

## Checklist For Later

1. Sign in as QFU Test Staff.
2. Confirm Workbench and normal operational navigation are available.
3. Confirm Manager Panel and Admin Panel are hidden or blocked.
4. Open Workbench and verify queue filters.
5. Add a sticky note to a safe item.
6. Log a call on a safe item.
7. Sign in as QFU Test Manager.
8. Confirm Manager Panel appears and Admin Panel is hidden.
9. Open Manager Panel and confirm team stats.
10. Sign in as QFU Test Admin.
11. Confirm Workbench, Manager Panel, and Admin Panel appear.
12. Open Staff, Branch Memberships, Staff Alias Mapping, Policies, Assignment Exceptions, and Alert Logs.
13. Sign in as QFU Test No Access.
14. Confirm restricted panels are hidden or access denied.
15. Run one TestRecipientOnly targeted alert.
16. Run one TestRecipientOnly digest.
17. Confirm no production emails, Teams messages, or live digests are sent.
18. Confirm duplicate work item, assignment exception, alert, and alias keys remain 0.
