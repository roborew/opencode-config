# Application spec repo

This repository owns **PRDs** (`docs/prd/`), **parent GitHub issues**, and cross-repo **CONTEXT** / **LANGUAGE**.

## First-time setup

If this repo was just created by shell `setup-project`, finish in OpenCode **here only** (do not repeat in `*-web`, `*-api`, etc.):

1. `cd` into this spec repo and run `opencode` (no `.opencode/` folder here — config loads from `OPENCODE_CONFIG_DIR`, default `~/.config/opencode`)
2. **architect** → **7. Setup / bootstrap stack** — interview, complete `docs/agents/repos.md`, delegate **stack-bootstrap** to each implementation sibling

Full walkthrough (new projects, existing repos, validation): **`~/.config/opencode/README.md`** — sections *New multi-repo project* and *Existing repositories*.

Shell bootstrap (from project parent, once): `setup-project` with `GH_ORG` set.

## Workflow

1. Author PRDs under `docs/prd/<slug>.md` (see `_template.md`).
2. Publish parent issues (see `.github/ISSUE_TEMPLATE/prd-parent.yml`).
3. Run `opencode-run spec fanout <slug>` to create child issues in each target repo listed in `docs/agents/repos.md`.
4. In each implementation repo, run **architect option 1** (issue-expand) then **orchestrate**.

## Labels

Canonical set: `.github/labels.yml` — kept in sync across this repo and targets via `.github/workflows/sync-labels.yml` (requires `LABEL_SYNC_PAT`).
