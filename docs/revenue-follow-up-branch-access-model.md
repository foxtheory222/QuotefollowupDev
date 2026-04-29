# Revenue Follow-Up Branch Access Model

Status: Partial.

`qfu_branchmembership` remains the business source for branch role membership. Dataverse branch teams or access teams should enforce production record access after the roster and privilege matrix are approved.

## Phase 8 Work

Created/found branch team shells for current branches with data:

- QFU Branch 4171
- QFU Branch 4172
- QFU Branch 4173

These teams are environment setup artifacts. They were not treated as proof that production branch security is complete.

## Target Model

- One branch team/access team per active branch.
- `qfu_branchmembership` drives branch membership.
- Work items and related records are owned by a service account or branch team and shared/scoped according to branch membership.
- Manager/GM/Admin panels use branch membership for UX scope.
- Final Dataverse privileges enforce access after role-specific testing.

## Production Blockers

- Verified Manager/GM/Admin roster is missing.
- Final privilege matrix is not approved.
- Role-specific test users are unavailable.
- Branch team membership assignment must be tested before broad rollout.
