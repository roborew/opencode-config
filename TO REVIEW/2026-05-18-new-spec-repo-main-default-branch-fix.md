# 2026-05-18 — `new-spec-repo` Default Branch Fix (`main`, Not `master`)

## Document metadata

| Field | Value |
| --- | --- |
| **Filename date (`2026-05-18`)** | **Cursor chat creation date** (ISO `YYYY-MM-DD` prefix for sort order in `TO REVIEW/`). Not the date this markdown was last edited. |
| **Cursor chat created** | **2026-05-18 12:33 BST** — filesystem birth time of session transcript |
| **Implementation finalized** | **2026-05-18** — same session; code change applied in the first implementation turn |
| **Cursor chat ID** | `999008cb-eb41-401b-908f-3ef0238b5646` |
| **Transcript path** | `.cursor/projects/Users-robo-config-opencode/agent-transcripts/999008cb-eb41-401b-908f-3ef0238b5646/999008cb-eb41-401b-908f-3ef0238b5646.jsonl` |
| **Purpose** | Full reconstruction guide for another AI or operator: problem, root cause, exact patch, surrounding script context, verification |

**Session scope:** Stop **brand-new** application spec repos from being created on **`master`** when bootstrapping via `~/.config/opencode/bin/new-spec-repo`. User follows **git-flow** naming (`main` + `develop`); this chat scoped the fix to **`main`** on first create only.

**Status:** Implemented and finalized in the Cursor chat above. **Verify on disk before merge** — repo layout may have moved logic to `bin/stack/create_or_sync_spec.sh` / `setup-project`; port the same guard to whichever script owns `gh repo create --clone`.

**Explicit non-goals (this chat):** Existing-repo sync off legacy `master`, preferring `develop` for day-to-day work, GitHub migration automation, and `.github/workflows/config-integrity.yml` changes. See [`2026-05-18-new-spec-repo-git-flow-main-develop.md`](2026-05-18-new-spec-repo-git-flow-main-develop.md) for a **separate, broader** session on existing-repo git-flow behaviour.

---

## Executive summary

| Topic | Outcome |
| --- | --- |
| **Symptom** | New spec repos bootstrap with first commit/push on **`master`** instead of **`main`** |
| **Root cause** | `gh repo create --clone` leaves local HEAD on Git’s `init.defaultBranch` (often still `master`); script never renamed before first commit |
| **Fix** | After `cd "${SPEC_NAME}"`, when `CREATED_SPEC=true`, run `git branch -M main` **before** scaffold copy, commit, and push |
| **Files changed** | `bin/new-spec-repo` only (one insertion block, ~5 lines) |
| **Unchanged** | Existing-repo branch checkout (`CREATED_SPEC=false`), `link-spec-repo`, templates |

---

## User request (verbatim)

> When creating the spec folder, it keeps creating as master, but actually I followed git flow organization, so it needs to be main and develop, but main in this instance. Can you change the code so it doesn't do master and use main instead?

---

## Investigation performed in chat

### 1. Repo-wide search for `master`

```bash
rg '\bmaster\b' /Users/robo/.config/opencode
```

**Findings at investigation time:**

| Path | Relevance |
| --- | --- |
| `bin/new-spec-repo` | **Target** — creates/clones spec repo, commits, pushes |
| `.github/workflows/config-integrity.yml` | `push: branches: [main, master]` — OpenCode config repo CI only; **not changed** in this chat |
| `dcp.jsonc` | Third-party schema URL `…/master/dcp.schema.json` — **not this repo’s branch policy** |
| `templates/spec-repo/.github/workflows/sync-labels.yml` | Already `branches: [main]` — no change needed |

No `master` references under `templates/spec-repo/` bootstrap content.

### 2. `gh repo create` behaviour

`gh repo create --help` documents that cloned repos use the **configured repository default branch** for GitHub, but an **empty local clone** still initializes from **local Git** `init.defaultBranch`.

Verified locally in chat:

```bash
rm -rf /tmp/git-branch-test && mkdir /tmp/git-branch-test && cd /tmp/git-branch-test
git init
git symbolic-ref HEAD          # → refs/heads/master (on operator machine)
git branch -M main
git symbolic-ref HEAD          # → refs/heads/main
```

### 3. Script flow identified

`bin/new-spec-repo` sets `CREATED_SPEC=true` only on the **`gh repo create … --clone`** path (remote did not exist). That path then:

1. `cd "${SPEC_NAME}"`
2. *(missing guard before fix)* — immediately proceeded to scaffold/commit
3. `cp -R templates/spec-repo/…`
4. `git commit` + `git push -u origin HEAD` → published whatever local branch name Git chose

The **existing-repo** path (`CREATED_SPEC=false`) already read GitHub `defaultBranchRef` — out of scope for this chat’s bug (new repos only).

---

## Exact change applied (re-apply spec)

### File

`bin/new-spec-repo`

### Patch type

Single `StrReplace` immediately after `cd "${SPEC_NAME}"`.

### `old_string` (must match exactly)

```bash
cd "${SPEC_NAME}"

DEFAULT_BRANCH=""
```

### `new_string` (insert this block)

```bash
cd "${SPEC_NAME}"

# Empty gh clones follow local init.defaultBranch (often still "master"). Rename before first commit so the default branch is main.
if [[ "$CREATED_SPEC" == "true" ]]; then
  git branch -M main
fi

DEFAULT_BRANCH=""
```

### Why this placement

| Order | Step | Branch name used |
| --- | --- | --- |
| 1 | `gh repo create … --clone` | Local HEAD = `init.defaultBranch` (often `master`) |
| 2 | `cd "${SPEC_NAME}"` | Still on `master` |
| **3 (NEW)** | `git branch -M main` when `CREATED_SPEC=true` | Renamed to **`main`** |
| 4 | `cp -R templates/spec-repo/…` | Working tree on `main` |
| 5 | `git commit` | Commit on `main` |
| 6 | `git push -u origin HEAD` | Creates **`origin/main`**; GitHub sets default to first pushed branch |

**Do not** run `git branch -M main` when `CREATED_SPEC=false` — that would rename branches during sync of legacy repos and conflict with git-flow work in the broader session doc.

---

## Surrounding script context (before fix)

Relevant section of `bin/new-spec-repo` **before** this chat’s edit (line numbers approximate; verify on disk):

```bash
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

if [[ "$CREATED_SPEC" == "true" ]]; then
  echo "Copying scaffold from ${ROOT}/templates/spec-repo ..."
  cp -R "${ROOT}/templates/spec-repo/." .
else
  mkdir -p docs/agents
fi
# … repos.md generation, git add, commit, push …
git push -u origin HEAD || true
```

---

## Surrounding script context (after fix)

```bash
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

# Empty gh clones follow local init.defaultBranch (often still "master"). Rename before first commit so the default branch is main.
if [[ "$CREATED_SPEC" == "true" ]]; then
  git branch -M main
fi

DEFAULT_BRANCH=""
if [[ "$CREATED_SPEC" != "true" ]]; then
  DEFAULT_BRANCH="$(gh repo view "$SPEC_REPO" --json defaultBranchRef --jq .defaultBranchRef.name)"
  # … unchanged existing-repo branch sync …
fi

if [[ "$CREATED_SPEC" == "true" ]]; then
  echo "Copying scaffold from ${ROOT}/templates/spec-repo ..."
  cp -R "${ROOT}/templates/spec-repo/." .
else
  mkdir -p docs/agents
fi
# … unchanged through git push -u origin HEAD …
```

---

## Port target if `bin/new-spec-repo` was consolidated

Search for the create path:

```bash
rg -n 'CREATED_SPEC=true|gh repo create.*--clone' bin/
```

Likely alternate owner: `bin/stack/create_or_sync_spec.sh` (called from `bin/setup-project`). Apply the **same 5-line block** immediately after `cd` into the spec directory on the **create-only** branch, before first commit.

Example port location pattern:

```bash
# After: cd "${SPEC_DIR}" or cd "${SPEC_NAME}"
# When:   variable indicating brand-new create (CREATED_SPEC=true or equivalent)
if [[ "${CREATED_SPEC:-false}" == "true" ]]; then
  git branch -M main
fi
```

---

## Files touched (this chat)

| File | Change |
| --- | --- |
| `bin/new-spec-repo` | Insert `git branch -M main` guard when `CREATED_SPEC=true` |

**Not modified:**

| File | Notes |
| --- | --- |
| `bin/link-spec-repo` | No branch logic |
| `templates/spec-repo/**` | Workflows already use `main` |
| `.github/workflows/config-integrity.yml` | Still `[main, master]` at review time; optional follow-up |
| `dcp.jsonc` | Upstream schema URL only |

---

## Operator usage (unchanged)

```bash
export GH_ORG=your-github-login-or-org
cd /path/to/APP   # siblings: APP-spec, APP-web, APP-api, …
~/.config/opencode/bin/new-spec-repo
```

Post-fix verification inside new spec repo:

```bash
cd APP-spec
git branch --show-current                    # expect: main
git log -1 --oneline                         # bootstrap commit on main
git remote show origin | grep 'HEAD branch'  # expect: main (after first push)
```

---

## Manual fix for spec repos already on `master`

This chat did **not** automate migration. One-time operator steps:

```bash
cd APP-spec
git branch -M main
git push -u origin main
```

Then GitHub → **Settings → General → Default branch → `main`**, and delete remote **`master`** when safe.

For git-flow **`develop`**, create and push separately from `main`; not part of this chat’s patch.

---

## Verification checklist (for re-applier)

```bash
# 1. Syntax
bash -n bin/new-spec-repo

# 2. Confirm patch present
rg -n 'branch -M main|CREATED_SPEC' bin/new-spec-repo

# 3. Local init.defaultBranch simulation
tmpdir=$(mktemp -d)
cd "$tmpdir"
git init
git branch --show-current    # often: master
git branch -M main
git branch --show-current    # expect: main

# 4. End-to-end (optional; creates real GitHub repo)
# cd /path/to/test-parent && GH_ORG=… new-spec-repo testapp
# cd testapp-spec && git branch --show-current  # expect: main
```

---

## Before / after behaviour

| Scenario | Before | After |
| --- | --- | --- |
| Brand-new spec via `gh repo create --clone` | First push to **`master`** when local `init.defaultBranch=master` | Renamed to **`main`** before scaffold; push creates **`origin/main`** |
| Existing local spec re-sync | Uses GitHub `defaultBranchRef` | **Unchanged** |
| Clone existing remote spec | Clone path; `CREATED_SPEC=false` | **Unchanged** |
| Git-flow `develop` preference on sync | Not implemented | Not implemented (see git-flow doc) |

---

## AI re-apply checklist

1. Locate `bin/new-spec-repo` (or consolidated `create_or_sync_spec.sh`).
2. Find `cd "${SPEC_NAME}"` (or equivalent) immediately after `CREATED_SPEC=true` assignment block.
3. Insert the 5-line `git branch -M main` block **before** any scaffold copy, commit, or push.
4. Guard with `CREATED_SPEC=true` only — do not run on existing-repo sync.
5. Run `bash -n` on the script.
6. Confirm no duplicate `git branch -M` blocks unless intentional (broader git-flow session may use `PRIMARY_BRANCH` variable instead of literal `main`).

---

## Related docs in `TO REVIEW/`

| File | Relationship |
| --- | --- |
| [`2026-05-18-new-spec-repo-git-flow-main-develop.md`](2026-05-18-new-spec-repo-git-flow-main-develop.md) | **Separate chat** — existing-repo sync, `develop` preference, `master`→`main` migration, `gh --jq` fix |
| [`2026-05-17-new-spec-repo-spec-repo-change-expectations.md`](2026-05-17-new-spec-repo-spec-repo-change-expectations.md) | When reruns produce commits in spec repo |
| [`2026-06-01-readme-web-mobile-naming-and-new-spec-repo-automation.md`](2026-06-01-readme-web-mobile-naming-and-new-spec-repo-automation.md) | Full `new-spec-repo` script snapshot for sibling discovery / repos.md |
| [`2026-06-01-setup-project-shell-bootstrap.md`](2026-06-01-setup-project-shell-bootstrap.md) | Overlapping bootstrap if stack moved under `setup-project` |

---

*End of record. Filename **`2026-05-18-…`** = Cursor chat **created** 2026-05-18; implementation **completed** same session.*
