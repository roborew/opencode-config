# 2026-06-01 — `setup-project` Shell Bootstrap: Fixes, UX, and Re-run Behavior

**Session completed:** 2026-06-01 (this chat — README/`GH_ORG` docs, `gh` stdout fix, operator UX, re-run idempotency; filename date is this completion date, not a later TO REVIEW edit).

**Session scope:** Documentation for `GH_ORG` and generic project layout; fix `setup-project` failures after first bootstrap; improve operator-facing output; make re-runs idempotent (confirm stack + next steps, not hard errors).

**Status:** Finalized in chat. Verify on disk before merge — workspace may have diverged since this session (e.g. `README.md` may no longer contain the setup section if docs were reorganized).

---

## Problem statement (why this work happened)

1. **README** mentioned `export GH_ORG=OWNER` without explaining what `OWNER` is or how to set it, and used **blocshed** as the only example app name.
2. **First bootstrap** often ended with `ERROR: invalid spec path (internal bug)` even though the spec repo was created — `gh repo create --clone` printed the GitHub URL on **stdout**, which was captured together with the real filesystem path.
3. **Operator output** felt like failures: noisy `gh label create` lines, `INCOMPLETE:` for repos that only needed OpenCode metadata, and a closing banner that implied shell bootstrap failed when linking had succeeded.
4. **Re-run** blocked with `ERROR: Spec repo has uncommitted changes` because `sync_spec_tooling.sh` leaves updated bins on disk and `create_or_sync_spec.sh` required a clean tree before branch checkout.

**User expectation:** Running `setup-project` again from the project parent should refresh/confirm wiring for all existing repos and print clear next steps — not exit on dirty git state from the previous run.

---

## Files touched (intended final state)

| File | Role |
|------|------|
| `README.md` | `GH_ORG` docs, generic `APP` / `myapp` layout, re-run safety note |
| `bin/setup-project` | Path capture, re-run defaults, repo summary, end-of-run commit, exit code policy |
| `bin/stack/create_or_sync_spec.sh` | `gh` stdout redirect, branch/dirty-tree policy, quiet label seeding |
| `bin/stack/sync_spec_tooling.sh` | (unchanged logic; exit codes consumed by setup) |
| `bin/stack/sync_impl_tooling.sh` | `OPENCODE_SETUP_QUIET=1` during setup linking |
| `bin/stack/print_next_steps.sh` | Human-friendly completion banner; optional linked-repo count |
| `bin/lib/migrate_repos_registry.py` | `NEXT:` vs `INCOMPLETE:` messaging |
| `bin/lib/test_migrate_repos_registry.py` | Assert `NEXT:` on bootstrap migrate path |

---

## 1. README — `GH_ORG` and generic layout

### `GH_ORG`

Documented as the GitHub **owner** (user login or organization) — the `owner` in `owner/repo`. Explicitly **not** the app slug or local parent folder name.

Examples added:

```bash
export GH_ORG=your-github-login-or-org
# export GH_ORG="$(gh api user -q .login)"
```

Alternative: `setup-project --org your-github-login-or-org` (same as `GH_ORG` env in `bin/setup-project`).

### Project layout naming

Replaced **blocshed** examples with placeholders:

- Parent: `~/code/APP/` (container, no git root)
- Siblings: `APP-spec`, `APP-web`, `APP-api` (with note to replace `APP` with product slug, e.g. `myapp`)
- Bootstrap example: `~/code/myapp`, clone `myapp-web`, `myapp-api`, `myapp-spec`

### Re-runs (README)

Added that re-running `setup-project` from the project parent is **safe**: refreshes tooling, re-links implementation repos, prints next steps; existing local spec stays on current branch.

---

## 2. GitHub CLI stdout bug — spec path capture

### Root cause

`create_or_sync_spec.sh` contract: **only** print one line to stdout (absolute spec path). `gh repo create … --clone` and `gh repo clone` also print the repo URL to stdout.

Parent captured:

```bash
SPEC_PATH="$(create_or_sync_spec.sh …)"
```

Resulting value (two lines):

```
https://github.com/roborew/fidget-spec
/Users/robo/.../fidget/fidget-spec
```

`[[ ! -d "$SPEC_PATH" ]]` failed → misleading “internal bug” error after successful create.

### Fixes in `bin/stack/create_or_sync_spec.sh`

- Redirect `gh repo clone` and `gh repo create` stdout to stderr: `1>&2`
- New spec: if `git push` fails, print explicit `cd <spec> && git push` hint (no silent `|| true` only)

### Fixes in `bin/setup-project`

- Capture as `SPEC_PATH_RAW`, parse lines and keep the last path where `[[ -d "$line" ]]`
- Fallback to pre-resolved `SPEC_DIR` when capture contains `github.com` but directory exists
- Replace “internal bug” with actionable errors / re-run hints

---

## 3. Operator UX — labels, registry, completion banner

### Label seeding (`create_or_sync_spec.sh`)

- `gh label create` → `&>/dev/null` (was flooding terminal with `✓ Label "…" created`)
- Single summary: `==> Seeded canonical labels on N repo(s)`

### Registry migrate (`migrate_repos_registry.py`)

| Mode | Message | Exit |
|------|---------|------|
| `--check-only` | `INCOMPLETE: <repos>` | 3 |
| Normal bootstrap migrate | `NEXT: In OpenCode (architect → setup-project), fill application_role and capabilities for: <repos>` | 3 |

Exit code **3** means “registry metadata still TBD in OpenCode” — expected after first shell bootstrap when `docs/agents/repos.md` only lists repo names (from generated scaffold).

`is_complete()` requires non-TBD `application_role` and `capabilities`.

### Implementation repo linking (`sync_impl_tooling.sh`)

When `OPENCODE_SETUP_QUIET=1` (set by `setup-project` during link loop), suppress per-script `Synced bin/…` lines. Still prints `Linked <dir> → SPEC_REPO=…` from `link_impl_repo.sh`.

### Completion banner (`print_next_steps.sh`)

- **Exit 6:** PRD validation errors — fix and re-run `--check-only`
- **Exit 3:** “Shell bootstrap complete” + what finished (tooling, N linked impl repos) + OpenCode next step; not “registry or PRDs need…” as if shell failed
- **Exit 0:** Full stack bootstrap complete
- Optional third argument: `linked-impl-count`

### `setup-project` exit code policy

- **Exit 0** when `SYNC_CODE=3` (shell work done; OpenCode interview pending)
- **Exit non-zero** for PRD errors (`6`) and other real failures
- Pass `LINKED` count into `print_next_steps.sh`

---

## 4. Re-run idempotency (final user-facing behavior)

### Auto keep branch

If `${SPEC_DIR}/.git` exists, `setup-project` forces `KEEP_BRANCH=true` before calling `create_or_sync_spec.sh` — re-runs do not try to checkout `develop`/`main` in spec.

### Dirty spec repo — no hard stop

**Before:** `ERROR: Spec repo has uncommitted changes. Commit, stash, or re-run with --keep-branch.` → exit 1

**After (`create_or_sync_spec.sh`):**

- If dirty and branch sync would have run: `==> Spec repo has local changes; staying on <branch>` and skip branch checkout (`SKIP_BRANCH_SYNC`)
- No exit 1 solely for dirty tree

Typical dirty state: first run’s `sync_spec_tooling.sh` copied bins but did not commit.

### End-of-run commit (`setup-project`)

After sync + linking:

```bash
git -C "$SPEC_PATH" add -A
# commit: chore: sync OpenCode spec tooling from setup-project
# push (warn if push fails)
```

So a second run is not blocked by tooling-only changes.

### Stack confirmation output

Before optional `LABEL_SYNC_PAT` block:

```
==> Stack repos:
    spec: owner/app-spec
    impl: owner/app-web  (app-web/)
    impl: owner/app-ingest  (app-ingest/)
```

Missing clones reported on stderr.

---

## Expected operator flow (e.g. fidget)

```bash
export GH_ORG=roborew   # or --org roborew
cd ~/.../apps/fidget
setup-project
```

**First run:** create/clone spec, migrate registry, seed labels (quiet), sync spec tooling, link impl repos, commit spec changes if any, print next steps.

**Re-run:** use existing `fidget-spec`, keep `main`, refresh tooling/registry/linking, commit if needed, list repos, print next steps — **no** uncommitted-changes error.

**Still required in OpenCode (normal):**

```bash
cd fidget-spec && opencode
# architect → setup-project skill
# Fill application_role and capabilities in docs/agents/repos.md
```

Shell bootstrap can be complete while registry metadata is exit code 3 / `NEXT:` — that is not a shell failure.

**Validate wiring:**

```bash
setup-project --check-only /path/to/fidget
```

Uses `INCOMPLETE:` for incomplete registry (strict check mode).

---

## Options reference (unchanged semantics)

| Flag | Behavior |
|------|----------|
| `--check-only` | No writes; validate spec + impl wiring |
| `--spec-only` | Spec only; skip impl linking |
| `--keep-branch` | Explicit stay on current spec branch (redundant when spec already exists — auto-enabled) |
| `--app <slug>` | Override app slug |
| `--org <org>` | Override `GH_ORG` |

---

## Real-world incident (fidget stack)

| Symptom | Cause | Resolution in chat |
|---------|--------|---------------------|
| `invalid spec path (internal bug). Got: https://github.com/...` + path | `gh` URL on stdout | Redirect `gh` to stderr; parse path lines |
| `INCOMPLETE: roborew/fidget-web` after migrate | TBD roles in registry | Renamed to `NEXT:`; exit 3 = pending OpenCode |
| Noisy label lines | `gh label create` stdout | Suppress; one summary line |
| “Shell bootstrap done; registry or PRDs need…” after successful link | `print_next_steps` treated 3 as failure | Friendly banner; exit 0 on 3 |
| Re-run: uncommitted changes ERROR | Dirty tree + branch guard | Auto keep-branch; warn not error; commit at end |

---

## Testing

- `python3 bin/lib/test_migrate_repos_registry.py` — updated partial-registry test to expect `NEXT:` instead of `INCOMPLETE` on non-check-only migrate
- Manual: `bash -n` on `bin/setup-project`, `bin/stack/create_or_sync_spec.sh`, `bin/stack/print_next_steps.sh`

---

## Out of scope / not changed in this chat

- OpenCode **skill** `skills/setup-project/SKILL.md` interview flow (architect session) — only shell `bin/setup-project` and stack scripts
- `skills/setup-project/SKILL.md` examples may still reference legacy repo names (e.g. blocshed) — not updated here
- `check_impl_wiring.sh` `INCOMPLETE:` messages for missing impl files — unchanged
- No git commits created by the agent unless user requested

---

## Follow-up (optional)

- [ ] Confirm all listed files match this document on disk after any parallel edits
- [ ] Restore or relocate setup docs if `README.md` was shortened and setup moved to `docs/RUNBOOK.md`
- [ ] Align `skills/setup-project/SKILL.md` examples with generic `APP` naming
- [ ] Document `SETUP_VERBOSE=1` if added later for noisy label/sync output

---

## Related docs

- [`bin/setup-project`](../bin/setup-project) — entry script
- [`skills/setup-project/SKILL.md`](../skills/setup-project/SKILL.md) — OpenCode architect skill (registry interview)
- [`docs/upgrade-spec/onboarding-supplement.md`](../docs/upgrade-spec/onboarding-supplement.md) — manual GitHub checklist
- [`TO REVIEW/2026-06-01-model-routing-configuration.md`](2026-06-01-model-routing-configuration.md) — same-day session (model routing)
