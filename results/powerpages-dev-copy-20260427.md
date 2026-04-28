# Power Pages Dev Copy - 2026-04-27

## Scope

Copied the production Power Pages site from:

- Source portal: `https://operationhub.powerappsportals.com/`
- Source Dataverse: `https://regionaloperationshub.crm.dynamics.com/`
- Source website id: `2b4aca76-9dc1-4628-af07-20f7617d4115`

Into the dev portal target:

- Target portal: `https://operationscenter.powerappsportals.com/`
- Target Dataverse: `https://orga632edd5.crm3.dynamics.com/`
- Target website id: `80909c52-339a-4765-b797-ed913fe73123`

## Source Refresh

Fresh Enhanced Power Pages downloads were taken on 2026-04-27 before upload:

- Source export: `powerpages-copy-20260427-074044/source-operationhub/operations-hub---operationhub`
- Target backup before changes: `powerpages-copy-20260427-074044/target-operationscenter-backup/operations-hub---operationscenter`

The target environment also contained a separate `Operations Hub - OperationHub` site with the production website id. The source export was not uploaded directly; it was remapped first so PAC targeted `operations hub - operationscenter`.

## Changes Applied

- Prepared a remapped site folder:
  - `powerpages-copy-20260427-074044/prepared-operationscenter-v2/operations-hub---operationscenter`
- Uploaded the remapped Power Pages source to target with `pac pages upload --modelVersion Enhanced --forceUploadAll`.
- Downloaded the target after upload for verification:
  - `powerpages-copy-20260427-074044/postupload-v2-operationscenter/operations-hub---operationscenter`
- Added/updated the repeatable remap script:
  - `scripts/prepare-powerpages-dev-copy.py`
- Patched the security repair helper so source webrole ids can be mapped to target webrole ids:
  - `scripts/repair-quoteoperations-dev-powerpages-security.ps1`

## Validation

- Target website id remains `80909c52-339a-4765-b797-ed913fe73123`.
- Target site name remains `operations hub - operationscenter`.
- QFU runtime template is present in the target export:
  - `web-templates/qfu-regional-runtime/QFU-Regional-Runtime.webtemplate.source.html`
- Source and target post-upload both have 30 web template files.
- QFU Web API site settings are present, including:
  - `Webapi/qfu_region/enabled`
  - `Webapi/qfu_backorder/fields`
  - `Webapi/qfu_deliverynotpgi/enabled`
  - `Webapi/qfu_freightworkitem/enabled`
- 17 QFU table permission records are present in the target post-upload export.
- Website access admin role now points to the original target Administrators role:
  - `07a9ddec-0ba7-4061-b875-34f13a444da0`

## Caveats

- PAC logged warnings while processing table permission relationships. The table permission records exist after repair, but the post-upload Enhanced export does not show `adx_entitypermission_webrole` lists on those permission files.
- Browser validation reached Microsoft Entra consent for `operationscenter.powerappsportals.com`; I did not accept consent on the user's behalf.
- The first upload created duplicate `Authenticated Users` and `Administrators` webrole rows. The active website access link was repaired to the original target Administrators role, but the duplicate role rows still exist and can be cleaned later if desired.
- This copied Power Pages site artifacts and site settings. It did not copy production business data, Power Automate flows, or Dataverse solution schema/data.

## Key Artifacts

- Remap report: `results/powerpages-dev-copy-20260427-remap-report-v2.json`
- Upload log: `results/powerpages-dev-copy-20260427-upload-v2.log`
- Security repair report: `results/powerpages-dev-copy-20260427-security-repair-v3.json`
- Browser check artifact: `results/powerpages-dev-copy-20260427-browser-check/operationscenter-home-check-after-account.json`
