# Role-Aware Navigation

Target behavior:
- Staff see Workbench and normal operational pages.
- Manager and GM users see Manager Panel.
- Admin users see Manager Panel and Admin Panel.
- Direct access to restricted pages should show a friendly access-denied state.

Role source:
- `qfu_staff.qfu_systemuser`
- active `qfu_branchmembership`
- roles: TSR, CSSR, Manager, GM, Admin

Phase 7 implementation status:
- Dev fallback navigation remains available.
- Current maker has a dev-only Admin membership for validation.
- Browser validation confirmed Workbench, Manager Panel, and Admin Panel are visible in the dev session.
- Production role-aware hiding is not enabled because verified production staff/systemuser and Manager/GM/Admin membership data is incomplete.

Phase 8 requirement:
Replace dev fallback with production security roles/web roles or app access rules driven by verified `qfu_branchmembership` records.
