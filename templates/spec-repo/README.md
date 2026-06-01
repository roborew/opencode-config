# Application spec repo

This repository owns **PRDs** (`docs/prd/`), **parent GitHub issues**, and cross-repo **CONTEXT** / **LANGUAGE**.

## Workflow

1. Author PRDs under `docs/prd/<slug>.md` (see `_template.md`).
2. Publish parent issues (see `.github/ISSUE_TEMPLATE/prd-parent.yml`).
3. Run `bin/fanout <slug>` to create child issues in each target repo listed in `docs/agents/repos.md`.
4. In each implementation repo, run `bin/feature-context <issue>` and then `architect-plan` / `orchestrate`.

## Labels

Canonical set: `.github/labels.yml` — kept in sync across this repo and targets via `.github/workflows/sync-labels.yml` (requires `LABEL_SYNC_PAT`).
