# Power Platform Environment Map - 2026-04-28

## Current Production

- Power Pages site: `https://operationhub.powerappsportals.com/`
- Dataverse environment: `https://regionaloperationshub.crm.dynamics.com/`
- Status: current production monitoring site. This environment will eventually be retired after the production-candidate site is fully autonomous and validated.

## Dev / Production Candidate

- Power Pages site: `https://operationscenter.powerappsportals.com/`
- Dataverse environment: `https://orga632edd5.crm3.dynamics.com/`
- Status: developer copy / production candidate. This environment must become autonomous before it can replace the current production site.

## Guardrail

Do not assume the active PAC profile or browser environment is the intended target. Before changing Power Pages, Dataverse, or Power Automate, verify the target URL and environment display name.

For Power Pages work, refresh with the Enhanced data model from the target site before editing:

```powershell
pac pages download --modelVersion Enhanced
```

For Dataverse or flow repair work, record the target environment URL in the result artifact.
