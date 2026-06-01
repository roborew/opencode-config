# 2026-05-18 — `new-spec-repo` Git-Flow Branches (`main` / `develop`, Never `master`)

**Session completed:** 2026-05-18 — when this chat finished the `bin/new-spec-repo` branch-policy and `gh --jq` fixes (transcript started that day; not the later calendar day the TO REVIEW file was first written).

**Session scope:** Stop `~/.config/opencode/bin/new-spec-repo` from checking out, committing, or pushing to `master` when syncing an existing spec repo. Align with git-flow convention: **`main`** (release/default on GitHub) and **`develop`** (integration work when present). Fix a follow-up `gh` CLI failure that blocked the script after the branch changes.

**Status:** Implemented and finalized in this chat. Verify on disk before merge — repo layout may have moved (e.g. logic consolidated into `setup-project` / `bin/stack/create_or_sync_spec.sh`); search for the behaviors below if `bin/new-spec-repo` is absent.

---

## Problem reported

Running `~/.config/opencode/bin/new-spec-repo` against an existing local spec repo (`blocshed-spec`) produced:

```text
Using existing local spec repo blocshed-spec...
Switched to a new branch 'master'
...
HEAD -> master
branch 'master' set up to track 'origin/master'.
```

GitHub also reported bypassed branch-protection violations for `refs/heads/master`.

**Expectation:** Git flow uses **`main`** and **`develop`** for work — not **`master`**. Spec repos should migrate off `master` toward `main` as the GitHub default; day-to-day sync should prefer **`develop`** when it exists on the remote.

---

## Root cause

For **existing** spec repos (`CREATED_SPEC=false`), the script used GitHub’s **`defaultBranchRef`** verbatim:

```bash
DEFAULT_BRANCH="$(gh repo view "$SPEC_REPO" --json defaultBranchRef --jq .defaultBranchRef.name)"
git switch -c "$DEFAULT_BRANCH" "origin/${DEFAULT_BRANCH}"
```

When the remote default was still **`master`** (legacy `BlocShed-spec`), the script created/checked out **`master`** locally and pushed there.

The **new-repo** path already renamed the first local branch to `main` (`git branch -M main`), but that only ran when `CREATED_SPEC=true` — not when re-syncing an existing clone.

---

## What was implemented

### 1. Git-flow branch policy (`bin/new-spec-repo`)

**Configurable env (optional):**

| Variable | Default | Meaning |
|----------|---------|---------|
| `SPEC_PRIMARY_BRANCH` | `main` | Production/default branch name on GitHub after migration |
| `SPEC_DEVELOP_BRANCH` | `develop` | Integration branch; preferred checkout when `origin/develop` exists |

**New repositories (`CREATED_SPEC=true`):**

- Before first commit: `git branch -M "${PRIMARY_BRANCH}"` (typically `main`), not `master`.

**Existing repositories (`CREATED_SPEC=false`):**

1. `git fetch origin` (all refs).
2. Read `remote_default` from GitHub (`defaultBranchRef.name`).
3. **Migration (one-time):** If `remote_default == master` and `origin/main` does **not** exist:
   - Create local `main` from `origin/master`.
   - `git push -u origin main`.
   - `gh repo edit "${SPEC_REPO}" --default-branch main` (requires repo admin).
   - Re-fetch.
4. **Checkout (never `master`):**
   - If `origin/develop` exists → checkout **`develop`**.
   - Else if `origin/main` exists → checkout **`main`**.
   - Else if GitHub default is non-null and **not** `master` → checkout that branch.
   - Else → exit with error (no safe branch).
5. `git pull --ff-only` on the chosen checkout branch.

**Commits and push:**

- Sync commit (`chore: sync … target repos`) and `git push -u origin HEAD` run on the **checkout branch** above (e.g. `develop`), not on `master`.

**Branch protection:**

- Applied to GitHub’s **current default branch** (after migration, expected `main`).
- **Refuses** to configure protection on `master` (clears target and skips API call with a clear message).

**Header comment** added to the script documenting env vars and “never master” behavior.

### 2. CI workflow (OpenCode config repo)

**File:** `.github/workflows/config-integrity.yml`

- **Before:** `push` trigger on `branches: [main, master]`.
- **After:** `branches: [main]` only.

**Not changed:** `dcp.jsonc` schema URL still references upstream `…/master/dcp.schema.json` (third-party path, not this repo’s branch policy).

### 3. Bug fix — `gh repo view` / `--jq` (blocked re-run)

**Symptom after branch changes:**

```text
Using existing local spec repo blocshed-spec...
accepts at most 1 arg(s), received 2
```

**Cause:** Invalid `gh` invocation:

```bash
# WRONG — shell passes -r as jq expr; .defaultBranchRef.name becomes a 2nd repo arg
gh repo view "$SPEC_REPO" --json defaultBranchRef --jq -r .defaultBranchRef.name
```

**Fix (both call sites — `remote_default` and `DEFAULT_BRANCH`):**

```bash
gh repo view "$SPEC_REPO" --json defaultBranchRef --jq '.defaultBranchRef.name'
```

`gh` accepts **one** jq expression argument; raw output mode is not passed via a separate `-r` flag to `gh`.

---

## Files touched (this session)

| File | Change |
|------|--------|
| `bin/new-spec-repo` | Git-flow checkout/migration; branch protection guard; `--jq` fix; usage/env comments |
| `.github/workflows/config-integrity.yml` | Remove `master` from push branches |

**Out of scope (unchanged in this session):**

- `bin/link-spec-repo` — no branch logic.
- `templates/spec-repo/**` — no `master` references found at time of change.
- Remote deletion of `origin/master` — left to operator after `main` is default and consumers are updated.

---

## Operator follow-up (e.g. `blocshed-spec`)

1. Re-run `new-spec-repo` from the app parent folder (siblings: `blocshed-spec`, `blocshed-api`, `blocshed-web`, etc.).
2. Confirm checkout is **`develop`** (if pushed) or **`main`**, not `master`.
3. Confirm GitHub **default branch** is **`main`** (Settings → General).
4. Optionally delete remote **`master`** once nothing depends on it.
5. If sync commits should land on **`develop`** but only **`main`** exists, create and push `develop` from `main`; next run prefers `develop`.

---

## Verification checklist

```bash
# From opencode config repo (if present)
bash -n bin/new-spec-repo

# Dry mental check: gh jq
gh repo view OWNER/APP-spec --json defaultBranchRef --jq '.defaultBranchRef.name'

# After sync, inside spec repo
git branch --show-current   # expect develop or main, never master
git remote show origin | grep 'HEAD branch'  # expect main (after migration)
```

---

## Before / after (behavior summary)

| Scenario | Before | After |
|----------|--------|-------|
| New spec repo via `gh repo create --clone` | `main` only on first commit path | `main` via `git branch -M main` before bootstrap commit |
| Existing repo, GitHub default `master` | Checkout/push `master` | Migrate to `main` on GitHub if missing; never checkout `master` |
| Existing repo, `origin/develop` exists | N/A (used GitHub default) | Checkout **`develop`** for sync work |
| Branch protection | Applied to whatever GitHub default was (including `master`) | Applied to GitHub default; **skip** if still `master` |
| `gh repo view … --jq` | Broken (`accepts at most 1 arg`) | Single quoted jq expression |

---

## Related docs in `TO REVIEW/`

| Date | Doc | Relationship |
|------|-----|--------------|
| 2026-05-17 | `2026-05-17-readme-web-mobile-naming-and-new-spec-repo-automation.md` | Prior session — create-or-sync, default-branch checkout (still followed GitHub default when it was `master`) |
| 2026-05-18 | *(this doc)* | Branch policy (`main` / `develop`, never `master`) + `gh --jq` fix |
| 2026-06-01 | `2026-06-01-new-spec-repo-spec-repo-change-expectations.md` | Later — when reruns produce commits vs “already up to date” |
| 2026-06-01 | `2026-06-01-setup-project-shell-bootstrap.md` | Later — overlapping stack/bootstrap themes if logic moved under `setup-project` |

If `new-spec-repo` was removed in favor of `setup-project`, port the **checkout order**, **master→main migration**, and **`--jq` quoting** into the active stack script and delete or thin-wrap the legacy entrypoint.
