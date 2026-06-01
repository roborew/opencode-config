# 2026-05-18 — `new-spec-repo` Git-Flow Branches (`main` / `develop`, Never `master`)

**Cursor chat created:** 2026-05-18 13:13 BST  
**Chat transcript:** [Git-flow / master branch fix](c5b6a856-7c41-4f35-b23f-7e2c971f50c8) (`c5b6a856-7c41-4f35-b23f-7e2c971f50c8`)

**Filename date rule:** Use the **Cursor chat creation date** (above), not the calendar day a TO REVIEW file was written or renamed later.

**Session scope:** Stop `~/.config/opencode/bin/new-spec-repo` from checking out, committing, or pushing to `master` when syncing an existing spec repo. Align with git-flow: **`main`** (GitHub default / release) and **`develop`** (integration when present). Fix `gh repo view --jq` so the script runs after the branch-policy change.

**Status:** Implemented and finalized in chat `c5b6a856-7c41-4f35-b23f-7e2c971f50c8`. **Verify on disk before merge** — this workspace snapshot may not include `bin/`; port the same blocks into `bin/stack/create_or_sync_spec.sh` or `bin/setup-project` if those supersede `new-spec-repo`.

**Baseline:** Assumes the **2026-05-17 / 2026-06-01** `new-spec-repo` create-or-sync script (see [`2026-06-01-readme-web-mobile-naming-and-new-spec-repo-automation.md`](2026-06-01-readme-web-mobile-naming-and-new-spec-repo-automation.md) §4). This session **patches** that script; it does not replace discovery, `repos.md` generation, label seeding, or `link-spec-repo` loops.

---

## Executive summary

| Area | Outcome |
|------|---------|
| Existing spec sync | Never `git switch` to `master`; prefer `origin/develop`, else `origin/main` |
| Legacy GitHub default `master` | One-time publish `main` from `origin/master`, `gh repo edit --default-branch main` |
| New spec create | `git branch -M "${PRIMARY_BRANCH}"` before first commit (typically `main`) |
| Branch protection | Target GitHub default branch; **skip** if default is still `master` |
| `gh` CLI | Fix `--jq` quoting (`accepts at most 1 arg(s), received 2`) |
| OpenCode CI | `.github/workflows/config-integrity.yml` push trigger: `main` only (remove `master`) |

---

## Problem reported (operator log)

```text
~/.config/opencode/bin/new-spec-repo
Using existing local spec repo blocshed-spec...
Switched to a new branch 'master'
[master e409017] chore: sync blocshed-spec target repos
...
HEAD -> master
branch 'master' set up to track 'origin/master'.
remote: Bypassed rule violations for refs/heads/master:
remote: - Changes must be made through a pull request.
```

**Expectation:** Git flow uses **`main`** and **`develop`**, not **`master`**, for spec-repo sync work.

---

## Root cause

For **`CREATED_SPEC=false`**, the script used GitHub **`defaultBranchRef`** verbatim (still `master` on `roborew/BlocShed-spec`):

```bash
DEFAULT_BRANCH="$(gh repo view "$SPEC_REPO" --json defaultBranchRef --jq .defaultBranchRef.name)"
git switch -c "$DEFAULT_BRANCH" "origin/${DEFAULT_BRANCH}"
```

The **new-repo** path could rename to `main` only when `CREATED_SPEC=true`; **existing** clones still followed remote default.

---

## Implementation order (for another AI replaying this chat)

Apply edits to `bin/new-spec-repo` in this order:

1. Add `PRIMARY_BRANCH` / `DEVELOP_BRANCH` env defaults after `PARENT_DIR`.
2. Extend script header comments (env + never-`master` policy).
3. After `cd "${SPEC_NAME}"`: add `git branch -M "${PRIMARY_BRANCH}"` for new repos; **replace** the entire existing-repo `DEFAULT_BRANCH` checkout block with fetch + migration + `checkout_branch` logic.
4. Replace branch-protection block (resolve default via `gh`, refuse `master`, wrap API call).
5. Fix both `gh repo view … --jq` call sites (existing-repo + branch protection).
6. Edit `.github/workflows/config-integrity.yml` push branches.

---

## Change 1 — Branch env vars (after `PARENT_DIR`)

**Add** immediately after `PARENT_DIR="$(pwd)"`:

```bash
# Git flow: never work on master. Prefer develop when it exists on the remote, else main.
PRIMARY_BRANCH="${SPEC_PRIMARY_BRANCH:-main}"
DEVELOP_BRANCH="${SPEC_DEVELOP_BRANCH:-develop}"
```

| Env var | Default | Meaning |
|---------|---------|---------|
| `SPEC_PRIMARY_BRANCH` | `main` | Production/default branch; migration target off `master` |
| `SPEC_DEVELOP_BRANCH` | `develop` | Preferred checkout when `origin/develop` exists |

---

## Change 2 — Script header comments

**Replace** the lone `target-repo:` usage line tail with:

```bash
#   GH_ORG=roborew new-spec-repo <app-slug> [target-repo ...]
#   target-repo: local folder name (e.g. app-web, app-mobile, app-api) or full owner/repo
# Env (optional): SPEC_PRIMARY_BRANCH (default main), SPEC_DEVELOP_BRANCH (default develop).
# Sync checks out develop if present on origin, else main — never master. If GitHub still
# defaults to master and main is missing, the script publishes main and sets it default.
```

---

## Change 3 — After `cd "${SPEC_NAME}"` (new + existing repo branches)

**Remove** this block (2026-05-17 baseline — checks out whatever GitHub default is, including `master`):

```bash
DEFAULT_BRANCH=""
if [[ "$CREATED_SPEC" != "true" ]]; then
  DEFAULT_BRANCH="$(gh repo view "$SPEC_REPO" --json defaultBranchRef --jq .defaultBranchRef.name)"
  if [[ -n "$DEFAULT_BRANCH" ]]; then
    if ! git diff --quiet || ! git diff --cached --quiet; then
      echo "Spec repo ${SPEC_NAME} has uncommitted changes; commit or stash them before syncing." >&2
      exit 1
    fi

    git fetch origin "$DEFAULT_BRANCH" >/dev/null 2>&1 || true
    if git show-ref --verify --quiet "refs/heads/${DEFAULT_BRANCH}"; then
      git switch "$DEFAULT_BRANCH" >/dev/null
    else
      git switch -c "$DEFAULT_BRANCH" "origin/${DEFAULT_BRANCH}" >/dev/null
    fi
    git pull --ff-only origin "$DEFAULT_BRANCH" >/dev/null 2>&1 || true
  fi
fi
```

**Insert** in its place (and add new-repo rename **before** the `CREATED_SPEC != true` block):

```bash
# Empty gh clones follow local init.defaultBranch (often still "master"). Rename before first commit.
if [[ "$CREATED_SPEC" == "true" ]]; then
  git branch -M "${PRIMARY_BRANCH}"
fi

if [[ "$CREATED_SPEC" != "true" ]]; then
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Spec repo ${SPEC_NAME} has uncommitted changes; commit or stash them before syncing." >&2
    exit 1
  fi

  git fetch origin >/dev/null 2>&1 || true

  remote_default="$(gh repo view "$SPEC_REPO" --json defaultBranchRef --jq '.defaultBranchRef.name')"
  # If GitHub still defaults to master but there is no main yet, publish main and move the default.
  if [[ "$remote_default" == "master" ]] && git show-ref --verify --quiet refs/remotes/origin/master; then
    if ! git show-ref --verify --quiet "refs/remotes/origin/${PRIMARY_BRANCH}"; then
      echo "Migrating ${SPEC_REPO} from master to ${PRIMARY_BRANCH} (default branch on GitHub will be updated)..."
      git switch -c "${PRIMARY_BRANCH}" origin/master >/dev/null
      git push -u origin "${PRIMARY_BRANCH}" >/dev/null
      gh repo edit "${SPEC_REPO}" --default-branch "${PRIMARY_BRANCH}" >/dev/null || {
        echo "WARN: pushed ${PRIMARY_BRANCH} but could not set GitHub default branch (needs repo admin)." >&2
      }
      git fetch origin >/dev/null 2>&1 || true
    fi
  fi

  checkout_branch=""
  if git show-ref --verify --quiet "refs/remotes/origin/${DEVELOP_BRANCH}"; then
    checkout_branch="${DEVELOP_BRANCH}"
  elif git show-ref --verify --quiet "refs/remotes/origin/${PRIMARY_BRANCH}"; then
    checkout_branch="${PRIMARY_BRANCH}"
  elif [[ -n "$remote_default" && "$remote_default" != "null" && "$remote_default" != "master" ]]; then
    checkout_branch="$remote_default"
  else
    echo "Spec repo ${SPEC_NAME}: no origin/${PRIMARY_BRANCH} or origin/${DEVELOP_BRANCH}; clone or fix remotes." >&2
    exit 1
  fi

  if git show-ref --verify --quiet "refs/heads/${checkout_branch}"; then
    git switch "${checkout_branch}" >/dev/null
  else
    git switch -c "${checkout_branch}" "origin/${checkout_branch}" >/dev/null
  fi
  git pull --ff-only origin "${checkout_branch}" >/dev/null 2>&1 || true
fi
```

**Behavior notes:**

- **Checkout** for sync commits uses `checkout_branch` (`develop` > `main` > non-`master` default).
- **Migration** runs only when GitHub default is `master` and `origin/main` is missing.
- **`git push -u origin HEAD`** later in the script pushes the checkout branch, not `master`.

---

## Change 4 — Branch protection block

**Remove:**

```bash
echo "Branch protection on default branch..."
DEFAULT_BRANCH="${DEFAULT_BRANCH:-$(gh repo view "$SPEC_REPO" --json defaultBranchRef --jq .defaultBranchRef.name)}"
gh api -X PUT "repos/${SPEC_REPO}/branches/${DEFAULT_BRANCH}/protection" \
  --input - >/dev/null 2>&1 <<'JSON' || echo "(branch protection skipped — adjust permissions)"
{
  "required_status_checks": null,
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": true
}
JSON
```

**Replace with:**

```bash
echo "Branch protection on GitHub default branch..."
DEFAULT_BRANCH="$(gh repo view "$SPEC_REPO" --json defaultBranchRef --jq '.defaultBranchRef.name')"
if [[ "$DEFAULT_BRANCH" == "master" ]]; then
  echo "Refusing to configure branch protection on master; set GitHub default to ${PRIMARY_BRANCH} (migrated repos) or ${DEVELOP_BRANCH}." >&2
  DEFAULT_BRANCH=""
fi
if [[ -n "$DEFAULT_BRANCH" && "$DEFAULT_BRANCH" != "null" ]]; then
gh api -X PUT "repos/${SPEC_REPO}/branches/${DEFAULT_BRANCH}/protection" \
  --input - >/dev/null 2>&1 <<'JSON' || echo "(branch protection skipped — adjust permissions)"
{
  "required_status_checks": null,
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": true
}
JSON
else
  echo "(skipped branch protection — no safe default branch resolved)"
fi
```

Protection applies to **GitHub’s default branch** (expected `main` after migration), not necessarily the branch used for sync commits (`develop`).

---

## Change 5 — `gh repo view --jq` fix (regression from Change 3/4)

**Symptom:**

```text
Using existing local spec repo blocshed-spec...
accepts at most 1 arg(s), received 2
```

**Wrong** (shell splits `-r` and `.defaultBranchRef.name` into two `gh` arguments):

```bash
gh repo view "$SPEC_REPO" --json defaultBranchRef --jq -r .defaultBranchRef.name
```

**Correct** (both call sites: `remote_default` and `DEFAULT_BRANCH`):

```bash
gh repo view "$SPEC_REPO" --json defaultBranchRef --jq '.defaultBranchRef.name'
```

Verify:

```bash
gh repo view OWNER/APP-spec --json defaultBranchRef --jq '.defaultBranchRef.name'
```

---

## Change 6 — `.github/workflows/config-integrity.yml`

**File:** `.github/workflows/config-integrity.yml`

**Before** (`push` trigger):

```yaml
  push:
    branches: [main, master]
```

**After:**

```yaml
  push:
    branches: [main]
```

**Not changed:** `dcp.jsonc` schema URL may still contain `/master/` in an upstream GitHub path (third-party).

**On-disk note (2026-06-01 review):** OpenCode config checkout may still show `[main, master]` if this session’s workflow edit was never committed — apply Change 6 explicitly.

---

## Appendix A — Session-final `bin/new-spec-repo` (full script)

Complete script after all changes in this chat. Merge with §4 of the readme automation doc if your tree still has the pre-session abort-on-exists version.

```bash
#!/usr/bin/env bash
# Create or sync an application spec repo from templates/spec-repo.
# Run from the parent folder that contains cloned implementation repos.
# Usage:
#   GH_ORG=roborew new-spec-repo                 # app slug = current folder; targets = sibling git dirs
#   GH_ORG=roborew new-spec-repo <app-slug>      # targets = sibling git dirs
#   GH_ORG=roborew new-spec-repo <app-slug> [target-repo ...]
#   target-repo: local folder name (e.g. app-web, app-mobile, app-api) or full owner/repo
# Env (optional): SPEC_PRIMARY_BRANCH (default main), SPEC_DEVELOP_BRANCH (default develop).
# Sync checks out develop if present on origin, else main — never master. If GitHub still
# defaults to master and main is missing, the script publishes main and sets it default.
set -euo pipefail

ORG="${GH_ORG:-roborew}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PARENT_DIR="$(pwd)"
# Git flow: never work on master. Prefer develop when it exists on the remote, else main.
PRIMARY_BRANCH="${SPEC_PRIMARY_BRANCH:-main}"
DEVELOP_BRANCH="${SPEC_DEVELOP_BRANCH:-develop}"

if [[ $# -gt 0 ]]; then
  APP="$1"
  shift || true
else
  APP="$(basename "$PARENT_DIR")"
fi

SPEC_NAME="${APP}-spec"
SPEC_REPO="${ORG}/${SPEC_NAME}"
TARGETS=("$@")

discover_targets() {
  local spec_name="$1"
  local dir

  for dir in */; do
    dir="${dir%/}"
    [[ "$dir" == "$spec_name" ]] && continue
    [[ "$dir" == .* ]] && continue
    [[ -d "$dir/.git" ]] || continue
    printf '%s\n' "$dir"
  done
}

normalize_repo() {
  local target="$1"
  if [[ "$target" == */* ]]; then
    printf '%s\n' "$target"
  else
    printf '%s/%s\n' "$ORG" "$target"
  fi
}

local_dir_for_target() {
  local target="$1"
  if [[ "$target" == */* ]]; then
    printf '%s\n' "${target##*/}"
  else
    printf '%s\n' "$target"
  fi
}

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  TARGETS=()
  while IFS= read -r target; do
    [[ -z "$target" ]] && continue
    TARGETS+=("$target")
  done < <(discover_targets "$SPEC_NAME")
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "WARN: no implementation repo folders discovered under ${PARENT_DIR}" >&2
  echo "      Clone repos as siblings here, or pass target repo names explicitly." >&2
fi

CREATED_SPEC=false
if [[ -d "${SPEC_NAME}/.git" ]]; then
  echo "Using existing local spec repo ${SPEC_NAME}..."
elif gh repo view "$SPEC_REPO" &>/dev/null; then
  echo "Cloning existing ${SPEC_REPO}..."
  gh repo clone "$SPEC_REPO" "$SPEC_NAME"
else
  echo "Creating ${SPEC_REPO}..."
  gh repo create "$SPEC_REPO" --private --description "Spec repo: PRDs + parent issues for ${APP}" --clone
  CREATED_SPEC=true
fi

cd "${SPEC_NAME}"

# Empty gh clones follow local init.defaultBranch (often still "master"). Rename before first commit.
if [[ "$CREATED_SPEC" == "true" ]]; then
  git branch -M "${PRIMARY_BRANCH}"
fi

if [[ "$CREATED_SPEC" != "true" ]]; then
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Spec repo ${SPEC_NAME} has uncommitted changes; commit or stash them before syncing." >&2
    exit 1
  fi

  git fetch origin >/dev/null 2>&1 || true

  remote_default="$(gh repo view "$SPEC_REPO" --json defaultBranchRef --jq '.defaultBranchRef.name')"
  if [[ "$remote_default" == "master" ]] && git show-ref --verify --quiet refs/remotes/origin/master; then
    if ! git show-ref --verify --quiet "refs/remotes/origin/${PRIMARY_BRANCH}"; then
      echo "Migrating ${SPEC_REPO} from master to ${PRIMARY_BRANCH} (default branch on GitHub will be updated)..."
      git switch -c "${PRIMARY_BRANCH}" origin/master >/dev/null
      git push -u origin "${PRIMARY_BRANCH}" >/dev/null
      gh repo edit "${SPEC_REPO}" --default-branch "${PRIMARY_BRANCH}" >/dev/null || {
        echo "WARN: pushed ${PRIMARY_BRANCH} but could not set GitHub default branch (needs repo admin)." >&2
      }
      git fetch origin >/dev/null 2>&1 || true
    fi
  fi

  checkout_branch=""
  if git show-ref --verify --quiet "refs/remotes/origin/${DEVELOP_BRANCH}"; then
    checkout_branch="${DEVELOP_BRANCH}"
  elif git show-ref --verify --quiet "refs/remotes/origin/${PRIMARY_BRANCH}"; then
    checkout_branch="${PRIMARY_BRANCH}"
  elif [[ -n "$remote_default" && "$remote_default" != "null" && "$remote_default" != "master" ]]; then
    checkout_branch="$remote_default"
  else
    echo "Spec repo ${SPEC_NAME}: no origin/${PRIMARY_BRANCH} or origin/${DEVELOP_BRANCH}; clone or fix remotes." >&2
    exit 1
  fi

  if git show-ref --verify --quiet "refs/heads/${checkout_branch}"; then
    git switch "${checkout_branch}" >/dev/null
  else
    git switch -c "${checkout_branch}" "origin/${checkout_branch}" >/dev/null
  fi
  git pull --ff-only origin "${checkout_branch}" >/dev/null 2>&1 || true
fi

if [[ "$CREATED_SPEC" == "true" ]]; then
  echo "Copying scaffold from ${ROOT}/templates/spec-repo ..."
  cp -R "${ROOT}/templates/spec-repo/." .
else
  mkdir -p docs/agents
fi

{
  echo "# Generated by new-spec-repo."
  echo "# This file is routing configuration; rerunning the script replaces this list."
  echo "repos:"
  for target in "${TARGETS[@]}"; do
    full="$(normalize_repo "$target")"
    echo "  - name: ${full}"
    echo "    role: target"
  done
} > docs/agents/repos.md

git add -A
if git diff --cached --quiet; then
  echo "Spec repo already up to date."
else
  if [[ "$CREATED_SPEC" == "true" ]]; then
    git commit -m "chore: bootstrap ${SPEC_NAME} scaffold" || true
  else
    git commit -m "chore: sync ${SPEC_NAME} target repos" || true
  fi
fi
git push -u origin HEAD || true

echo "Branch protection on GitHub default branch..."
DEFAULT_BRANCH="$(gh repo view "$SPEC_REPO" --json defaultBranchRef --jq '.defaultBranchRef.name')"
if [[ "$DEFAULT_BRANCH" == "master" ]]; then
  echo "Refusing to configure branch protection on master; set GitHub default to ${PRIMARY_BRANCH} (migrated repos) or ${DEVELOP_BRANCH}." >&2
  DEFAULT_BRANCH=""
fi
if [[ -n "$DEFAULT_BRANCH" && "$DEFAULT_BRANCH" != "null" ]]; then
gh api -X PUT "repos/${SPEC_REPO}/branches/${DEFAULT_BRANCH}/protection" \
  --input - >/dev/null 2>&1 <<'JSON' || echo "(branch protection skipped — adjust permissions)"
{
  "required_status_checks": null,
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": true
}
JSON
else
  echo "(skipped branch protection — no safe default branch resolved)"
fi

seed_one() {
  local repo="$1"
  yq -o=json '.[]' .github/labels.yml 2>/dev/null | jq -c '.' | while read -r row; do
    name=$(echo "$row" | jq -r .name)
    color=$(echo "$row" | jq -r .color)
    desc=$(echo "$row" | jq -r '.description // ""')
    gh label create "$name" --repo "$repo" --color "$color" --description "$desc" --force 2>/dev/null || true
  done
}

if command -v yq &>/dev/null && command -v jq &>/dev/null; then
  echo "Seeding labels into ${SPEC_REPO}..."
  seed_one "$SPEC_REPO"
  while IFS= read -r r; do
    [[ -z "$r" ]] && continue
    echo "Seeding labels into ${r}..."
    seed_one "$r"
  done < <(yq -r '.repos[].name' docs/agents/repos.md 2>/dev/null || true)
else
  echo "WARN: install yq + jq to seed labels from .github/labels.yml" >&2
fi

echo ""
echo "Linking local implementation repos to ${SPEC_REPO}..."
for target in "${TARGETS[@]}"; do
  local_dir="$(local_dir_for_target "$target")"
  if [[ -d "${PARENT_DIR}/${local_dir}" ]]; then
    echo "Linking ${local_dir}..."
    (cd "${PARENT_DIR}/${local_dir}" && "${ROOT}/bin/link-spec-repo" "$SPEC_REPO")
  else
    echo "WARN: local directory ${local_dir} not found; skipped link-spec-repo" >&2
  fi
done

echo ""
echo "=== GitHub Project (optional) ==="
echo "Create a Project v2 board in the browser: https://github.com/orgs/${ORG}/projects — link repos ${SPEC_REPO} ${TARGETS[*]:-}"
echo "Automated field setup is not fully available via gh in all versions; enable **Auto-add to project** per repo in project settings."
echo ""
echo "=== LABEL_SYNC_PAT ==="
echo "Add a fine-grained PAT (Issues: write) for sibling repos:"
echo "  gh secret set LABEL_SYNC_PAT --repo ${SPEC_REPO}"
echo ""
echo "Done. Spec repo: https://github.com/${SPEC_REPO}"
```

---

## Appendix B — Port to `create_or_sync_spec.sh` (if consolidated)

If `new-spec-repo` is a thin wrapper or removed, apply the same logic after entering the spec repo directory:

1. `PRIMARY_BRANCH` / `DEVELOP_BRANCH` constants (or stack-level env).
2. New-create: `git branch -M "${PRIMARY_BRANCH}"`.
3. Existing: fetch all → `remote_default` with quoted `--jq` → optional master→main migration → `checkout_branch` selection (never `master`).
4. Branch protection: resolve default with quoted `--jq`; skip when `master`.

---

## Files touched (this session)

| File | Change |
|------|--------|
| `bin/new-spec-repo` | § Change 1–5; Appendix A |
| `.github/workflows/config-integrity.yml` | § Change 6 |

**Out of scope:**

- `bin/link-spec-repo`
- `templates/spec-repo/**`
- Deleting remote `origin/master` (operator)

---

## Operator follow-up (`blocshed-spec` / any legacy spec)

```bash
cd /path/to/parent   # siblings: *-spec, *-api, *-web
export GH_ORG=roborew
~/.config/opencode/bin/new-spec-repo
```

Inside spec repo:

```bash
git branch --show-current          # develop or main, never master
git remote show origin | grep 'HEAD branch'   # expect main after migration
```

If only `main` exists but you want sync on `develop`:

```bash
cd APP-spec
git checkout main
git checkout -b develop
git push -u origin develop
# next new-spec-repo run prefers develop
```

---

## Verification checklist

```bash
bash -n bin/new-spec-repo
gh repo view roborew/BlocShed-spec --json defaultBranchRef --jq '.defaultBranchRef.name'
grep -n 'branches:' .github/workflows/config-integrity.yml
```

---

## Before / after

| Scenario | Before | After |
|----------|--------|-------|
| New spec (`CREATED_SPEC=true`) | Optional `main` rename only in later session | `git branch -M "${PRIMARY_BRANCH}"` before bootstrap |
| Existing, GitHub default `master` | Checkout/push `master` | Migrate to `main` if missing; never checkout `master` |
| `origin/develop` exists | Used GitHub default | Checkout **`develop`** for sync |
| Branch protection | On default (could be `master`) | On GitHub default; skip if `master` |
| `gh --jq` | Broken two-arg form | `'.defaultBranchRef.name'` |

---

## Related docs in `TO REVIEW/`

| Date | Doc | Relationship |
|------|-----|--------------|
| 2026-05-17 | `2026-05-17-readme-web-mobile-naming-and-new-spec-repo-automation.md` | Baseline create-or-sync script (§4) |
| 2026-05-18 | *(this doc)* | Git-flow + `gh --jq` + CI `main`-only |
| 2026-05-17 | `2026-05-17-new-spec-repo-spec-repo-change-expectations.md` | When reruns commit `repos.md` |
| 2026-06-01 | `2026-06-01-new-spec-repo-main-default-branch-fix.md` | Narrow bootstrap-only `git branch -M main` (subset of Change 3) |
| 2026-06-01 | `2026-06-01-setup-project-shell-bootstrap.md` | Stack consolidation follow-up |

---

## Suggested commit message (OpenCode config repo)

```text
fix(bin): new-spec-repo git-flow branches (main/develop, never master)

Prefer develop/main checkout for existing spec repos; migrate GitHub default
off master when main is missing; fix gh --jq quoting; skip branch protection
on master; CI push trigger main only.
```
