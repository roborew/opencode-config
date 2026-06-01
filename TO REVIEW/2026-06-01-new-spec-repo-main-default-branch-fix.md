# 2026-06-01 — `new-spec-repo` Default Branch Fix (`main`, Not `master`)

**Session scope:** Stop brand-new application spec repos from being created on **`master`** when bootstrapping via `~/.config/opencode/bin/new-spec-repo`. Align with git-flow naming where **`main`** is the production/default branch (with **`develop`** used separately for integration work).

**Session completed:** 2026-06-01 — when this chat finalized the `git branch -M main` bootstrap fix in `bin/new-spec-repo` (before the TO REVIEW write-up).

**Status:** Implemented and finalized in this chat. Verify on disk before merge — if `bin/` was reorganized under `setup-project` / `bin/stack/create_or_sync_spec.sh`, port the same behavior there.

---

## Problem reported

When creating a spec folder/repo, the script kept using **`master`** as the branch name. The user follows **git-flow** organization and expects **`main`** (and **`develop`** for ongoing integration), not **`master`**, for this workflow.

Observed failure mode on **new** spec repos:

- `gh repo create … --clone` completes successfully.
- First commit and push land on **`master`** instead of **`main`**.
- GitHub branch protection and downstream tooling (workflows under `templates/spec-repo/` already target **`main`**) are misaligned.

---

## Root cause

For a **brand-new** spec repo (`CREATED_SPEC=true`), the script:

1. Runs `gh repo create "$SPEC_REPO" --private … --clone`.
2. `cd`s into the empty clone.
3. Copies the scaffold from `templates/spec-repo/`.
4. Commits and pushes with `git push -u origin HEAD`.

The empty clone’s initial branch name comes from the **local Git setting** `init.defaultBranch`, not from git-flow or GitHub org policy. On many machines that default is still **`master`**, so the first push creates **`origin/master`** even when the user expects **`main`**.

The script already had logic to respect GitHub’s default branch when **syncing an existing** spec repo (`gh repo view … defaultBranchRef`), but that path does not run on first create — so legacy **`master`** leaked in on bootstrap only.

---

## What was implemented

### Change in `bin/new-spec-repo`

Immediately after `cd "${SPEC_NAME}"`, when the repo was **just created** in this run:

```bash
# Empty gh clones follow local init.defaultBranch (often still "master"). Rename before first commit so the default branch is main.
if [[ "$CREATED_SPEC" == "true" ]]; then
  git branch -M main
fi
```

**Placement:** Before copying the scaffold, committing, or pushing — so the bootstrap commit and `git push -u origin HEAD` both publish **`main`**, which becomes GitHub’s default branch for the new empty remote.

**Scope of this session:**

| Path | Handled in this chat? |
|------|------------------------|
| New spec repo bootstrap (`CREATED_SPEC=true`) | **Yes** — force local branch to `main` before first commit |
| Existing spec repo sync (`CREATED_SPEC=false`) | **No** — still follows GitHub `defaultBranchRef` (may still be `master` on legacy remotes) |
| Prefer `develop` for day-to-day sync | **No** — out of scope for this chat |
| Migrate legacy `master` → `main` on GitHub | **No** — manual operator step (see below) |
| `.github/workflows/config-integrity.yml` (`main` vs `master` triggers) | **Not changed** — mentioned as optional follow-up only |

---

## Files touched (this session)

| File | Change |
|------|--------|
| `bin/new-spec-repo` | Add `git branch -M main` on the new-repo path before scaffold commit |

**Unchanged (verified at review time):**

| File | Notes |
|------|--------|
| `templates/spec-repo/.github/workflows/sync-labels.yml` | Already triggers on `branches: [main]` |
| `bin/link-spec-repo` | No branch logic |
| `.github/workflows/config-integrity.yml` | Still lists `push` branches `[main, master]` in OpenCode config repo |

---

## Operator follow-up

### New spec repos (after fix)

Re-run or create as usual from the app parent folder:

```bash
export GH_ORG=your-github-login-or-org
cd /path/to/APP   # siblings: APP-spec, APP-web, APP-api, …
~/.config/opencode/bin/new-spec-repo
```

Confirm inside the new spec repo:

```bash
cd APP-spec
git branch --show-current   # expect: main
git remote show origin | grep 'HEAD branch'   # expect: main (after first push)
```

### Existing spec repos still on `master`

This chat did **not** add automatic migration. One-time manual fix:

```bash
cd APP-spec
git branch -M main
git push -u origin main
```

Then in GitHub: **Settings → General → Default branch → `main`**, and delete remote **`master`** when nothing else references it.

If you use git-flow with **`develop`**, create and push it from `main` separately; that was not part of this session’s code change.

---

## Verification checklist

```bash
# Syntax check (from OpenCode config repo)
bash -n bin/new-spec-repo

# Simulate local init.defaultBranch=master behavior on a throwaway repo
tmpdir=$(mktemp -d)
cd "$tmpdir"
git init
git branch --show-current          # often: master
git branch -M main
git branch --show-current          # expect: main
```

After a real bootstrap, confirm the GitHub repo’s default branch is **`main`** and the first commit is on **`main`**, not **`master`**.

---

## Before / after

| Scenario | Before | After (this session) |
|----------|--------|----------------------|
| First-time `gh repo create --clone` + scaffold | First push to **`master`** when local `init.defaultBranch` is `master` | Local branch renamed to **`main`** before first commit; push creates **`origin/main`** |
| Re-sync existing spec repo | Uses GitHub default branch as-is | Unchanged |
| Git-flow `develop` checkout on sync | Not implemented | Not implemented |

---

## Related docs in `TO REVIEW/`

Same date, different sessions (sort together under `2026-06-01-*`):

- `2026-05-18-new-spec-repo-git-flow-main-develop.md` — broader branch policy (existing-repo migration, `develop` preference, `gh --jq` fix); may extend beyond what was finalized in this chat.
- `2026-06-01-new-spec-repo-spec-repo-change-expectations.md` — when reruns produce commits in the spec repo (clarification only).
- `2026-06-01-setup-project-shell-bootstrap.md` — overlapping bootstrap themes if logic lives under `bin/stack/create_or_sync_spec.sh`.

If `new-spec-repo` is deprecated in favor of `setup-project`, apply the same **`git branch -M main`** guard on the **create** path in whichever script owns `gh repo create --clone`.
