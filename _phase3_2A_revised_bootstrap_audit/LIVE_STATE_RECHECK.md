# Live State Recheck

- Environment URL: https://orga632edd5.crm3.dynamics.com/
- Solution found: True
- App found: True
- Required tables found: yes
- Phase 3 alternate/replacement keys active: yes

## Final Active Counts After Cleanup

| Metric | Count |
| --- | ---: |
| Active staff records | 19 |
| Active staff alias records | 39 |
| Active AM Number aliases | 16 |
| Active CSSR Number aliases | 23 |
| Active branch memberships | 39 |
| Duplicate alias groups | 0 |
| Duplicate staff-number groups | 0 |
| Staff missing email | 19 |
| Staff missing Dataverse user | 19 |
| Active work items | 0 |
| Active assignment exceptions | 0 |
| Active alert logs | 0 |

## Key Recheck

| Table | Key | Found | Index Status | Attributes |
| --- | --- | --- | --- | --- |
| qfu_staffalias | qfu_key_staffalias_source_type_alias_scope | True | Active | qfu_aliastype, qfu_normalizedalias, qfu_scopekey, qfu_sourcesystem |
| qfu_branchmembership | qfu_key_branchmembership_branch_staff_role | True | Active | qfu_branch, qfu_role, qfu_staff |
| qfu_policy | qfu_key_policy_scope_worktype_activekey | True | Active | qfu_policykey |
| qfu_workitem | qfu_key_workitem_type_sourcekey | True | Active | qfu_sourceexternalkey, qfu_worktype |
| qfu_alertlog | qfu_key_alertlog_dedupekey | True | Active | qfu_dedupekey |
| qfu_assignmentexception | qfu_key_assignmentexception_sourcekey_type_field_value | True | Active | qfu_exceptionkey |
