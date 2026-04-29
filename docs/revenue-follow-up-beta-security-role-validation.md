# Beta Security Role Validation

Status: Partial / blocked.

QFU roles found:

- QFU Staff
- QFU Manager
- QFU GM
- QFU Admin
- QFU Service Account

Each QFU role has privilege rows in Dataverse. This proves the roles are not empty shells, but it is not enough to accept beta security because least-privilege behavior has not been tested with separate role-specific accounts.

Blocked tests:

- Staff-only access.
- Manager Panel access without Admin Panel access.
- Admin access to setup pages.
- No-access user denial.
- Branch team enforcement.

No maker/admin lockout occurred.
