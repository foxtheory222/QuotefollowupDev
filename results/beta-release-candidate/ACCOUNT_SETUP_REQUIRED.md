# Account Setup Required

Status: Required unless real test accounts already exist outside the current Dataverse discovery.

No complete set of separate QFU beta test personas was verified in Dataverse.

Required accounts:

| Persona | Required user | Required access |
| --- | --- | --- |
| QFU Test Staff | qfu-test-staff | Power Apps/Dataverse access, QFU Staff role, branch 4171 TSR or CSSR membership |
| QFU Test Manager | qfu-test-manager | Power Apps/Dataverse access, QFU Manager role, branch 4171 Manager membership |
| QFU Test Admin | qfu-test-admin | Power Apps/Dataverse access, QFU Admin role, Admin membership |
| QFU Test No Access | qfu-test-noaccess | No QFU app role or no QFU branch membership |
| QFU Test GM | qfu-test-gm | Optional; QFU GM role and branch 4171 GM membership |

Rules:

- Do not use name-only matches for production identity.
- Use verified tenant email/domainname and active Dataverse systemuser rows.
- Do not share or store passwords in this repository or audit.
- Do not enable Live alert mode for beta validation.
- Configure TestRecipientOnly only after a verified test mailbox exists.
