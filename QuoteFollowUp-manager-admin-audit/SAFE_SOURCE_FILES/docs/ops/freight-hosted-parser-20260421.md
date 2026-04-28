## Freight Hosted Parser Implementation - 2026-04-21

### Scope

This change replaces the missing workstation freight queue consumer with a hosted-parser design that keeps Power Automate as the ingress/orchestration layer and preserves the existing freight parsing rules for legacy `.xls` and Redwood `.xlsx` files.

### What Changed

Hosted freight parser scaffold added:

- `.azure/plan.md`
- `src/freight_parser_host/function_app.py`
- `src/freight_parser_host/entrypoint.py`
- `src/freight_parser_host/qfu_freight_parser/core.py`
- `src/freight_parser_host/qfu_freight_parser/host_contract.py`
- `src/freight_parser_host/qfu_freight_parser/processor.py`
- `src/freight_parser_host/qfu_freight_parser/dataverse_client.py`
- `src/freight_parser_host/host.json`
- `src/freight_parser_host/requirements.txt`
- `src/freight_parser_host/local.settings.sample.json`
- `src/freight_parser_host/README.md`

Compatibility path preserved:

- `scripts/freight_parser.py` is now a shim into the hosted parser package so existing local repair scripts and parser tests keep using the same code.

Flow generator updated:

- `scripts/create-southern-alberta-freight-flow-solution.ps1`

New freight ingress contract:

1. create `qfu_rawdocument`
2. create `qfu_ingestionbatch`
3. call hosted function `processfreightdocument`
4. on success, update rawdocument/batch to `processed` with inserted/updated counts
5. on hosted-call failure, update rawdocument/batch to `error`

### Why

The current freight warning recurrences were not parser defects. They happened because the mailbox flows only wrote queued rows and the old local consumer was missing. The hosted parser removes that workstation dependency while preserving the same carrier parsing logic already proven against live samples.

### Local Validation

Executed:

```powershell
python -m unittest tests.test_freight_parser tests.test_freight_hosted_parser_contracts -v
```

Result:

- existing freight parser regression suite still passes
- hosted parser contract tests pass
- freight generator contract now asserts hosted parser invocation and Dataverse status stamping

### Deployment Prerequisites

Still required before live rollout:

- confirm Azure subscription and region
- install/validate Azure deployment tooling for this workspace (`azd` is not currently installed locally)
- deploy the Azure Function app
- assign Dataverse access for the hosted identity or app registration
- populate the hosted parser URL and function key in the freight ingress flow definition
- import/update the Southern Alberta freight ingress flows with that hosted configuration
- verify live Dataverse rows and next unattended freight email

### Assumptions

- Freight source report formats and mailbox patterns remain stable.
- The hosted parser can authenticate to Dataverse through managed identity or service principal without changing the freight table schema.
- It is acceptable for the hosted parser to perform the `qfu_freightworkitem` upsert directly, while Power Automate remains responsible for ingress audit rows and final batch/raw status stamping.

### Risks / Watch Items

- The generated flow now expects a hosted parser URL/key to be supplied before live import.
- Azure Function deployment and Dataverse app-user wiring are not validated in this workspace yet.
- If a future freight change requires fields beyond `qfu_freightworkitem`, the hosted processor and flow response contract must be updated together.
