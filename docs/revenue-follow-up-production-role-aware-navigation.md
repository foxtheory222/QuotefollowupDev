# Production Role-Aware Navigation

Status: Partial.

The desired production navigation is:

Regular staff:
- Dashboard
- Workbench
- Quotes
- Back Orders
- Ready to Ship
- Freight Recovery
- Analytics

Manager / GM:
- Dashboard
- Workbench
- Manager Panel
- Quotes
- Back Orders
- Ready to Ship
- Freight Recovery
- Analytics

Admin:
- Dashboard
- Workbench
- Manager Panel
- Admin Panel
- Quotes
- Back Orders
- Ready to Ship
- Freight Recovery
- Analytics

## Current Implementation

- Workbench is available in dev.
- Manager Panel and Admin Panel remain available in dev fallback.
- Browser validation confirmed the expected panels are visible in the authenticated dev context.
- The role context source remains `qfu_staff` linked to Dataverse `systemuser`, then active `qfu_branchmembership` role rows.
- No production user role is guessed.

## Access-Denied UX

Target message:

`You do not have access to this panel. Contact your QFU admin if this looks wrong.`

The friendly access-denied logic is documented and ready to wire into final production gating. Real unauthorized-user validation is still blocked because no separate unauthorized QFU test user was available.

## Production Blockers

- Staff-to-systemuser mapping is incomplete.
- Manager/GM/Admin production memberships are missing.
- Final security role privileges are not approved.
- Role-specific users are needed to validate hidden Manager/Admin navigation and direct-link denial.
