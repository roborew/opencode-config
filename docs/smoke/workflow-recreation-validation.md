# Workflow recreation — validation harness

Run after merging `feature/workflow-recreation` (or from that branch). Requires `gh` authenticated and `GH_ORG` set.

## Config integrity (local)

```bash
cd ~/.config/opencode
bash scripts/check-crlf.sh
bash scripts/validate-opencode-config.sh
python3 bin/lib/test_migrate_repos_registry.py
bash bin/lib/test_read_spec_repo.sh
bash -n bin/setup-project
bash -n bin/stack/*.sh
```

## blocshed — regression (`--check-only`)

Existing stack should report wired impl repos. Registry may show `NEXT:` / TBD until OpenCode `setup-project` skill completes interview — that is expected.

```bash
export GH_ORG=roborew
~/.config/opencode/bin/setup-project --check-only /Users/robo/05_Repos/01_PROJECTS/apps/blocshed
```

**Pass criteria:**
- Spec repo detected (`blocshed-spec`)
- Impl wiring: `OK: blocshed-api`, `OK: blocshed-web` (or lists specific gaps)
- Exit 0 or exit 3 with `INCOMPLETE` for registry TBD only (not missing tooling)

## fidget — completion (link + check)

```bash
export GH_ORG=roborew
cd /Users/robo/05_Repos/01_PROJECTS/apps/fidget
~/.config/opencode/bin/setup-project --keep-branch
```

Then in OpenCode (`fidget-spec`):

1. Architect → **Setup project** — fill `docs/agents/repos.md` (`application_role`, `capabilities`, remove TBD)
2. Re-check:

```bash
~/.config/opencode/bin/setup-project --check-only /Users/robo/05_Repos/01_PROJECTS/apps/fidget
```

**Pass criteria:** `--check-only` exit 0; `fidget-web` and `fidget-ingest` have `docs/agents/issue-tracker.md` with `SPEC_REPO:` and `bin/feature-context`.

## New project — onboarding smoke

```bash
export GH_ORG=your-org
mkdir -p ~/code/smoke-app && cd ~/code/smoke-app
# clone or create APP-spec, APP-web siblings first
~/.config/opencode/bin/setup-project
cd APP-spec && opencode
# architect → setup-project skill
```

**Pass criteria:** `setup-project --check-only .` from parent passes after registry interview.

## End-to-end feature smoke (optional)

**Spec feature:** spec repo → grill-me → to-prd → approve → architect runs fanout → impl architect issue-expand → orchestrate GitHub backlog `feature:<slug>`.

**Targeted change:** impl repo → architect targeted change → to-issues → optional issue-expand → orchestrate.
