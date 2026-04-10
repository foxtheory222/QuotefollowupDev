# QuoteFollowUpV2

This repository now holds the exported Quote Follow Up Power Pages site ("Quote Operations"). The `site/` folder mirrors the PAC CLI layout that you get from `pac pages download`: it contains `web-files`, `web-pages`, `web-templates`, `content-snippets`, forms, lists, and server logic that the portal uses.

## Working with the site
1. Install the Power Platform CLI and authenticate to your Dataverse environment (`pac auth create -u <org-url>`).
2. Use `pac pages download --path ./site --webSiteId <guid> --modelVersion 2` to refresh this directory before making edits, and `pac pages upload --path ./site --modelVersion 2` to deploy local changes.
3. Edit the files under `site/web-pages/*/*.customjs.js`, `site/web-files/*`, `site/server-logics`, etc. before uploading so the scripts stay readable in source control.
4. Follow the workflow in `AGENTS.md` (Fix -> test -> fix, modules only in shared files, explicit `$select`, smoke and manual tests) before pushing work to the repo.

## Next steps
- Keep the portal JavaScript structured into `scripts/qfu-api.js`, `scripts/qfu-core.js`, and `scripts/pages` entry points so future module work matches the playbook.
- After pushing changes, rerun the smoke tests listed in `AGENTS.md`, then continue with any manual tests that touched the same routes.
- Document any PAC CLI parameters (site ID, environment) in this repo once they are known so future contributors don't have to guess.
