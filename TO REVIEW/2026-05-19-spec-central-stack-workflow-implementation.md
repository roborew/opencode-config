# 2026-05-19 — Spec-Central Stack Workflow: Full Implementation Record

## Chat metadata (for dating and replay)

| Field | Value |
| --- | --- |
| **Cursor chat created** | **2026-05-19** (transcript directory birth: `May 19 11:42` local) |
| **Transcript ID** | `e4851f6f-4658-4c8b-bb24-e76b4db7c7b5` |
| **Transcript path** | `~/.cursor/projects/Users-robo-config-opencode/agent-transcripts/e4851f6f-4658-4c8b-bb24-e76b4db7c7b5/e4851f6f-4658-4c8b-bb24-e76b4db7c7b5.jsonl` |
| **Plan ID** | `spec-central_stack_workflow_21fd8d39` |
| **Filename date** | `2026-05-19` — matches **chat creation date**, not later follow-up sessions |

**How to replay artifacts for another AI:** Re-apply §10 StrReplace patches to a pre-session baseline, or copy §9 verbatim files. Transcript is the authoritative edit log if this doc and disk diverge.

**Session scope:** Implement the **Spec-central vertical stack workflow** plan: unify shell bootstrap into `bin/setup-project`, add spec-coordinated OpenCode skills and agents, make **GitHub issues** the execution source of truth after fanout (not local `.plan/issue.*`), extend orchestrate for `stages[]` on issues, and validate on the **blocshed** stack.

**Status:** All plan todos marked **completed** in chat. **Verify on disk** — later refactors may have removed `bin/` or skills from your checkout; use §9–§11 to recreate.

---


## Executive summary

| Area | Outcome |
| --- | --- |
| Shell bootstrap | Single entry **`~/.config/opencode/bin/setup-project`**; internals under **`bin/stack/`**; deprecated shims for `new-spec-repo`, `link-spec-repo`, `upgrade-spec-repo` |
| Layout | Parent folder (`~/code/APP/`) is **container only** — no git root or agent files at parent; siblings `APP-spec`, `APP-api`, `APP-web`, … |
| OpenCode bootstrap | **`setup-project`** skill in **spec repo** only; **`stack-bootstrap`** subagent copies impl templates |
| Execution SOT | After `bin/fanout`, **GitHub child issues** hold coarse tasks; **`issue-expand`** adds TDD **`stages[]`** in `opencode-task-json` before orchestrate |
| Orchestrate | **`orchestrate-execution`** runs **stage loop** when `opencode_meta.stages` present; **`developer`** accepts `execution_mode: github_issue_stage` |
| Close-out | **`feature-complete`** skill in spec repo rolls up cross-repo delivery and closes spec parent issue |
| Docs | `README.md`, `docs/RUNBOOK.md`, `docs/plan-artifact-schema.md`, `templates/spec-repo/README.md` updated |
| blocshed run | Shell `setup-project --keep-branch` **succeeded**; registry **TBD** stubs expected until architect skill pass |
| Permission fix | Architect bash allowlist extended for `git remote get-url origin` (and related read-only git/gh) |

---

## Problem statement (why this work happened)

1. **Three shell scripts** (`new-spec-repo`, `link-spec-repo`, `upgrade-spec-repo`) for one mental model — “make this PROJECT folder ready.”
2. **Two execution paths** — legacy local `.plan/feature.<slug>.md` vs issue-backed fanout — without a clear front door or shared stage schema on issues.
3. **Per-repo `setup-skills`** forced `cd` into every implementation repo; spec repo should coordinate the whole stack in one session.
4. **Orchestrate** could not run TDD **stages** from GitHub issue bodies when fanout only produced flat acceptance lists.

---

## Target architecture (final)

```text
~/code/APP/                    # Container ONLY (no tracked files here)
├── APP-spec/                  # PRDs, registry, fanout, product CONTEXT
├── APP-web/                   # Implementation repo(s)
├── APP-api/
└── APP-<surface>/
```

| Layer | Location | Responsibility |
| --- | --- | --- |
| Product spec | `APP-spec/docs/prd/<slug>.md` | User stories, `tickets:` definitions, approval |
| Coarse tasks | GitHub in each impl repo | One issue per PRD ticket after **`bin/fanout`** |
| Detailed plan | **Same GitHub issues** | `issue-expand`: Implementation plan + `stages[]` in fenced `opencode-task-json` |
| Session cache | `tmp/feature-context.md` | Ephemeral; **not** source of truth |
| Legacy | `.plan/feature.<slug>.md` | Option B only; migration path documented in `setup-project` skill |

---

## Production workflow (operator)

```text
# Step 1 — Shell (project parent, new OR existing stack)
cd ~/code/APP
export GH_ORG=owner
~/.config/opencode/bin/setup-project
# optional: --keep-branch, --check-only, --spec-only, --app, --org

# Step 2 — OpenCode in spec only
cd APP-spec && opencode
# architect: "Run setup-project" (or front-door option for stack setup)
#   → interview, fill docs/agents/repos.md, Task stack-bootstrap per impl repo

# Feature delivery (issue-backed path)
spec:  grill-me → to-prd → approve → bin/fanout <slug>
impl:  architect → issue-expand (feature:<slug>) → orchestrate (GitHub backlog B)
close: spec architect → feature-complete
```

**Canonical references after implementation:** `docs/RUNBOOK.md`, `docs/plan-artifact-schema.md`, `templates/spec-repo/README.md`.

---

## 3. Unified shell: `bin/setup-project`

### Entry point

- **Path:** `~/.config/opencode/bin/setup-project` (not `./bin/setup-project` inside `APP/`)
- **PATH helper:** `scripts/install-opencode-cli.sh` → `~/.local/bin`
- **Deprecation shims:** `bin/new-spec-repo`, `bin/link-spec-repo`, `bin/upgrade-spec-repo` → `exec` or delegate to `setup-project`

### CLI

```text
setup-project [options] [project-parent-dir]

  --check-only     Validate registry + PRD + impl wiring (no writes)
  --spec-only      Create/sync spec only; skip impl linking
  --keep-branch    Do not checkout develop/main in spec (stay on current branch)
  --app <slug>     Override app slug (default: lowercased parent basename)
  --org <org>      Override GH_ORG
  -h, --help
```

Default parent directory = current working directory.

### `bin/stack/` helpers (created in session)

| Script | Role |
| --- | --- |
| `common.sh` | Discovery, case-insensitive spec detection, `stack_gh_repo_from_dir`, `stack_default_app_slug` |
| `create_or_sync_spec.sh` | Create or sync spec from `templates/spec-repo`; **stdout = single absolute path only** |
| `sync_spec_tooling.sh` | Copy fanout bins/libs; run `migrate_repos_registry.py`; PRD validation |
| `sync_impl_tooling.sh` | Sync impl-side bins from templates |
| `link_impl_repo.sh` | `SPEC_REPO` in `issue-tracker.md`, `feature-context`, gitignore |
| `check_impl_wiring.sh` | Mechanical gaps for `--check-only` |
| `print_next_steps.sh` | Human completion banner |

### Mode detection

| State | Actions |
| --- | --- |
| No `APP-spec` / no `.git` | Create spec from template; discover siblings; seed labels; link impls |
| Spec exists | Sync tooling; migrate registry; validate PRDs |
| Impl siblings present | Link each (skip `*-spec` dirs) |
| Registry has `TBD` roles | Exit **3** + message to run OpenCode `setup-project` skill |

### Exit codes (shell)

| Code | Meaning |
| --- | --- |
| 0 | Full success |
| 3 | Shell work done; registry metadata still incomplete (`INCOMPLETE` / `NEXT:`) |
| 6 | PRD validation errors |
| 1+ | Hard failures (missing org, invalid paths, etc.) |

---

## 4. OpenCode agents and skills

### New agent: `stack-bootstrap`

- **File:** `agents/stack-bootstrap.md`
- **Skill:** `skills/stack-bootstrap/SKILL.md`
- **Role:** Write-capable leaf; installs OpenCode scaffolding into **one** implementation repo when architect runs `setup-project`
- **Guardrails:** May edit target repo; deny `~/.config/opencode/**`
- **Registered in:** `opencode.json` (agent entry added in session)

### New skill: `setup-project` (spec repo only)

- **File:** `skills/setup-project/SKILL.md`
- **Phases (summary):**
  - **A** — Discover parent + siblings; read `docs/agents/repos.md`
  - **B** — Interview: `application_role`, `capabilities` per repo
  - **C** — Legacy audit: `.plan/_archive/legacy/`, `docs/_archive/legacy/` rules
  - **D** — `scribe` registry; `Task` → `stack-bootstrap` per impl; `developer` runs `setup-project --check-only` on parent
- **Bash preference:** `gh repo view --json nameWithOwner` over `git remote get-url` where possible

### New skill: `issue-expand` (implementation repo)

- **File:** `skills/issue-expand/SKILL.md`
- **Role:** Enrich fanout issues: `## Implementation plan`, `stages[]` inside fenced `opencode-task-json`
- **Handoff:** Prompt user to switch to **orchestrate** → GitHub backlog `feature:<slug>`
- **Supersedes:** Local `.plan/issue.<n>.md` approach (cancelled todo `issue-plan-skill`)

### New skill: `feature-complete` (spec repo)

- **File:** `skills/feature-complete/SKILL.md`
- **Role:** Cross-repo rollup, PR links on parent issue, close spec PRD issue after all impl repos done

### Extended: `orchestrate-execution`

- **File:** `skills/orchestrate-execution/SKILL.md`
- **Change:** When `opencode_meta.stages` present on selected GitHub issue, run **stage loop** (pick next runnable stage, dispatch `developer` with `github_issue_stage`)
- **Fallback:** Flat acceptance list when no `stages[]`

### Extended: `developer`

- **File:** `agents/developer.md`
- **New contract:** `execution_mode: github_issue_stage` with `stage_id` + one object from `opencode_meta.stages[]`

### Architect wiring (`agents/architect.md`)

**Skills added to `permission.skill`:**

- `setup-project`, `issue-expand`, `feature-complete` (plus existing planning utilities)

**Tasks added to `permission.task`:**

- `stack-bootstrap: allow`
- `developer: allow` (for `gh` / `setup-project --check-only` on parent only)

**Spec-repo front door (option 2 A/B during plan; later sessions may simplify menus — see `2026-06-01-feature-pipeline-and-architect-front-door.md`):**

- **A)** Issue-backed — `issue-expand` → orchestrate GitHub backlog
- **B)** Legacy — `grill-me` → `.plan/feature.<slug>.md` → orchestrate from file

**Bash allowlist additions (permission fix for “Permission required”):**

- `git remote get-url origin`
- `git remote -v`
- `git branch --show-current`
- `gh repo view --repo *`
- `gh issue list *`

User must **approve once**, **restart session**, or **skip** remote discovery with explicit `roborew/blocshed-spec` in prompt.

### Schema doc

- **`docs/plan-artifact-schema.md`** — `opencode-task-json` + `stages[]` fields for issue bodies

### Config registration

- **`opencode.json`** — `stack-bootstrap` agent entry
- **`ocx.jsonc`** — new skills registered (session-era; later commits may have removed central skills registry — verify)

---

## 5. Bugs fixed during this chat

| Symptom | Cause | Fix |
| --- | --- | --- |
| `bin/setup-project: no such file` from `APP/` | Script lives only in OpenCode config | Document full path; `install-opencode-cli.sh`; usage header in script |
| `invalid spec path (internal bug)` + GitHub URL in path | `gh repo create/clone` printed URL on **stdout**; parent captured logs as `SPEC_PATH` | `create_or_sync_spec.sh`: logs → stderr; only final path on stdout; parent parses last valid directory line |
| `link-spec-repo` run inside `blocshed-spec` | Case mismatch `BlocShed` vs `blocshed`; `BlocShed-spec` ≠ `blocshed-spec` | Case-insensitive `*-spec` skip; app slug = **lowercased** parent basename; remotes from `git`/`gh` per repo |
| Architect **Permission required** on `git remote get-url origin` | Read-only architect; command not on bash allowlist | Add git remote / branch + `gh repo view` patterns; skill prefers `gh repo view --json nameWithOwner` |
| `INCOMPLETE` after successful shell run | Registry stubs with `TBD` for `application_role` / `capabilities` | **Expected** until OpenCode `setup-project` skill completes interview |

---

## 6. blocshed validation (user stack)

**Parent:** `/Users/robo/05_Repos/01_PROJECTS/apps/blocshed`

**Siblings:** `blocshed-spec`, `blocshed-api`, `blocshed-web`

**GitHub:** `roborew/blocshed-spec` (remote casing may differ from folder names)

**Successful command:**

```bash
cd /Users/robo/05_Repos/01_PROJECTS/apps/blocshed
export GH_ORG=roborew
~/.config/opencode/bin/setup-project --keep-branch
```

**Observed:**

- Spec stayed on **develop**
- Labels seeded on spec, api, web
- api/web linked to spec
- `docs/agents/repos.md` updated with impl entries but **TBD** stubs → exit **3** / `INCOMPLETE` — **not a shell failure**

**Next step for user (not done in shell pass):**

```bash
cd blocshed-spec && opencode
# architect → Run setup-project
# Fill application_role and capabilities; remove TBD
```

**Validate:**

```bash
~/.config/opencode/bin/setup-project --check-only /Users/robo/05_Repos/01_PROJECTS/apps/blocshed
```

---

## 7. Plan todos — completed vs cancelled

| Todo ID | Status | Deliverable |
| --- | --- | --- |
| `unified-setup-project-bin` | **Completed** | `bin/setup-project` + `bin/stack/*` + deprecation shims |
| `stack-bootstrap-agent` | **Completed** | `agents/stack-bootstrap.md` + `skills/stack-bootstrap/SKILL.md` |
| `setup-project-skill` | **Completed** | `skills/setup-project/SKILL.md` + architect wiring |
| `legacy-plan-audit` | **Completed** | Rules in `setup-project` skill (archive paths) |
| `issue-expand-skill` | **Completed** | `skills/issue-expand/SKILL.md` |
| `orchestrate-issue-stages` | **Completed** | `skills/orchestrate-execution/SKILL.md` + `developer.md` + schema doc |
| `feature-complete-skill` | **Completed** | `skills/feature-complete/SKILL.md` |
| `docs-canonical-flow` | **Completed** | README, RUNBOOK, templates/spec-repo/README |
| `align-stack-skill` | **Cancelled** | Superseded by `setup-project` |
| `init-stack-bin` | **Cancelled** | Merged into unified bin |
| `issue-plan-skill` | **Cancelled** | Superseded by `issue-expand` |
| `orchestrate-issue-plans` | **Cancelled** | Superseded by issue `stages[]` loop |

---

## 8. Files created or modified (inventory)

### New — shell

- `bin/setup-project`
- `bin/stack/common.sh`
- `bin/stack/create_or_sync_spec.sh`
- `bin/stack/sync_spec_tooling.sh`
- `bin/stack/sync_impl_tooling.sh`
- `bin/stack/link_impl_repo.sh`
- `bin/stack/check_impl_wiring.sh`
- `bin/stack/print_next_steps.sh`

### New — agents / skills / docs

- `agents/stack-bootstrap.md`
- `skills/stack-bootstrap/SKILL.md`
- `skills/setup-project/SKILL.md`
- `skills/issue-expand/SKILL.md`
- `skills/feature-complete/SKILL.md`
- `docs/plan-artifact-schema.md`

### Modified (representative)

- `bin/new-spec-repo`, `bin/link-spec-repo`, `bin/upgrade-spec-repo` (deprecation)
- `agents/architect.md` (skills, tasks, bash allowlist, front-door / routing)
- `agents/developer.md` (`github_issue_stage`)
- `skills/orchestrate-execution/SKILL.md`
- `opencode.json`, `ocx.jsonc`
- `README.md`, `docs/RUNBOOK.md`, `templates/spec-repo/README.md`
- `scripts/install-opencode-cli.sh` (PATH install; if added in session)

### Unchanged shared libs (used by stack scripts)

- `bin/lib/migrate_repos_registry.py`
- `bin/lib/read_spec_repo.sh`
- `templates/spec-repo/**` (fanout, validators — pre-existing; synced by `sync_spec_tooling.sh`)

---

## 9. Full source files (verbatim from chat transcript replay)

These are the **final** contents after all `Write` + `StrReplace` operations in transcript `e4851f6f-4658-4c8b-bb24-e76b4db7c7b5`. Create each path under `~/.config/opencode/`.

### `bin/stack/common.sh`

```bash
# shellcheck shell=bash
# Shared helpers for bin/setup-project (source only).
set -euo pipefail

stack_oc_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

# True if dirname is the spec repo for this app (case-insensitive *-spec match or layout).
stack_dir_is_spec_repo() {
  local parent_dir="$1"
  local dir="$2"
  local app_spec_name="$3"
  local path="${parent_dir}/${dir}"
  [[ "$(printf '%s' "$dir" | tr '[:upper:]' '[:lower:]')" == "$(printf '%s' "$app_spec_name" | tr '[:upper:]' '[:lower:]')" ]] && return 0
  [[ "$(printf '%s' "$dir" | tr '[:upper:]' '[:lower:]')" == *-spec ]] && stack_is_spec_repo "$path" && return 0
  return 1
}

stack_discover_targets() {
  local parent_dir="$1"
  local spec_name="$2"
  local dir
  for dir in "${parent_dir}"/*/; do
    dir="${dir%/}"
    dir="$(basename "$dir")"
    [[ "$dir" == .* ]] && continue
    [[ -d "${parent_dir}/${dir}/.git" ]] || continue
    stack_dir_is_spec_repo "$parent_dir" "$dir" "$spec_name" && continue
    printf '%s\n' "$dir"
  done
}

# Resolve on-disk spec repo path (handles BlocShed-spec vs blocshed-spec).
stack_resolve_spec_dir() {
  local parent_dir="$1"
  local app="$2"
  local canonical="${parent_dir}/${app}-spec"
  if [[ -d "${canonical}/.git" ]]; then
    cd "$canonical" && pwd
    return 0
  fi
  local d base
  for d in "${parent_dir}"/*; do
    [[ -d "$d/.git" ]] || continue
    base="$(basename "$d")"
    stack_dir_is_spec_repo "$parent_dir" "$base" "${app}-spec" || continue
    cd "$d" && pwd
    return 0
  done
  printf '%s\n' "$canonical"
}

stack_normalize_repo() {
  local org="$1"
  local target="$2"
  if [[ "$target" == */* ]]; then
    printf '%s\n' "$target"
  else
    printf '%s/%s\n' "$org" "$target"
  fi
}

stack_local_dir_for_target() {
  local target="$1"
  if [[ "$target" == */* ]]; then
    printf '%s\n' "${target##*/}"
  else
    printf '%s\n' "$target"
  fi
}

stack_spec_repo_path() {
  local parent_dir="$1"
  local app="$2"
  stack_resolve_spec_dir "$parent_dir" "$app"
}

stack_is_spec_repo() {
  local path="$1"
  [[ -d "$path/docs/prd" || -f "$path/docs/agents/repos.md" ]]
}

# owner/name from git remote (prefer gh; fallback parse).
stack_gh_repo_from_dir() {
  local dir="$1"
  local url name
  if command -v gh >/dev/null 2>&1; then
    name="$(cd "$dir" && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
    if [[ -n "$name" && "$name" == */* ]]; then
      printf '%s\n' "$name"
      return 0
    fi
  fi
  url="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
  [[ -n "$url" ]] || return 1
  case "$url" in
    git@github.com:*)
      name="${url#git@github.com:}"
      name="${name%.git}"
      ;;
    https://github.com/*|http://github.com/*)
      name="${url#https://github.com/}"
      name="${name#http://github.com/}"
      name="${name%.git}"
      ;;
    *)
      return 1
      ;;
  esac
  if [[ "$name" == */* ]]; then
    printf '%s\n' "$name"
    return 0
  fi
  return 1
}

# App slug from spec folder (blocshed-spec -> blocshed).
stack_app_slug_from_spec_dir() {
  local spec_dir="$1"
  local base="${spec_dir##*/}"
  local lower
  lower="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lower" == *-spec ]]; then
    printf '%s\n' "${lower%-spec}"
    return 0
  fi
  printf '%s\n' "$lower"
}

# Default app slug: parent folder name, lowercased (blocshed / BlocShed -> blocshed).
stack_default_app_slug() {
  local parent_dir="$1"
  printf '%s\n' "$(basename "$parent_dir" | tr '[:upper:]' '[:lower:]')"
}
```

### `bin/stack/create_or_sync_spec.sh`

```bash
#!/usr/bin/env bash
# Create or sync spec repo under a project parent directory.
# Usage: create_or_sync_spec.sh [--keep-branch] <parent-dir> <app-slug> <org> [target ...]
# Stdout: single line — absolute path to spec repo. All logs go to stderr.
# Env: SPEC_PRIMARY_BRANCH, SPEC_DEVELOP_BRANCH
set -euo pipefail
KEEP_BRANCH=false
if [[ "${1:-}" == "--keep-branch" ]]; then
  KEEP_BRANCH=true
  shift
fi
PARENT_DIR="$(cd "$1" && pwd)"
APP="$2"
ORG="$3"
shift 3
TARGETS=("$@")

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=common.sh
source "$(dirname "$0")/common.sh"

PRIMARY_BRANCH="${SPEC_PRIMARY_BRANCH:-main}"
DEVELOP_BRANCH="${SPEC_DEVELOP_BRANCH:-develop}"
SPEC_DIR="$(stack_resolve_spec_dir "$PARENT_DIR" "$APP")"
CLONE_NAME="$(basename "$SPEC_DIR")"

# Prefer GitHub remote on disk (e.g. roborew/BlocShed-spec) over guessed org/blocshed-spec.
if [[ -d "${SPEC_DIR}/.git" ]] && SPEC_REPO="$(stack_gh_repo_from_dir "$SPEC_DIR")"; then
  :
else
  SPEC_REPO="${ORG}/${APP}-spec"
fi
SPEC_NAME="${SPEC_REPO#*/}"

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  TARGETS=()
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    TARGETS+=("$t")
  done < <(stack_discover_targets "$PARENT_DIR" "${APP}-spec")
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "WARN: no implementation repos discovered under ${PARENT_DIR}" >&2
fi

CREATED_SPEC=false
if [[ -d "${SPEC_DIR}/.git" ]]; then
  echo "==> Using existing local spec repo $(basename "$SPEC_DIR") at ${SPEC_DIR}" >&2
elif gh repo view "$SPEC_REPO" &>/dev/null; then
  echo "==> Cloning ${SPEC_REPO} as ${CLONE_NAME}..." >&2
  (cd "$PARENT_DIR" && gh repo clone "$SPEC_REPO" "$CLONE_NAME")
  SPEC_DIR="$(stack_resolve_spec_dir "$PARENT_DIR" "$APP")"
else
  echo "==> Creating ${SPEC_REPO}..." >&2
  (cd "$PARENT_DIR" && gh repo create "$SPEC_REPO" --private \
    --description "Spec repo: PRDs + parent issues for ${APP}" --clone)
  CREATED_SPEC=true
  SPEC_DIR="$(stack_resolve_spec_dir "$PARENT_DIR" "$APP")"
fi

cd "$SPEC_DIR"

if [[ "$CREATED_SPEC" == "true" ]]; then
  git branch -M "${PRIMARY_BRANCH}" 2>&1 | grep -v '^$' >&2 || true
fi

if [[ "$CREATED_SPEC" != "true" && "$KEEP_BRANCH" != "true" ]]; then
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "ERROR: Spec repo has uncommitted changes. Commit, stash, or re-run with --keep-branch." >&2
    echo "       Path: ${SPEC_DIR}  branch: $(git branch --show-current 2>/dev/null || echo unknown)" >&2
    exit 1
  fi
  git fetch origin >/dev/null 2>&1 || true
  remote_default="$(gh repo view "$SPEC_REPO" --json defaultBranchRef --jq '.defaultBranchRef.name')"
  if [[ "$remote_default" == "master" ]] && git show-ref --verify --quiet refs/remotes/origin/master; then
    if ! git show-ref --verify --quiet "refs/remotes/origin/${PRIMARY_BRANCH}"; then
      git switch -c "${PRIMARY_BRANCH}" origin/master >/dev/null 2>&1
      git push -u origin "${PRIMARY_BRANCH}" >/dev/null 2>&1
      gh repo edit "${SPEC_REPO}" --default-branch "${PRIMARY_BRANCH}" >/dev/null 2>&1 || true
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
  fi
  if [[ -n "$checkout_branch" ]]; then
    current="$(git branch --show-current 2>/dev/null || true)"
    if [[ "$current" != "$checkout_branch" ]]; then
      echo "==> Spec repo: checking out ${checkout_branch} (was on ${current:-detached}) for tooling sync" >&2
      echo "    Re-run with --keep-branch to stay on your current branch." >&2
    fi
    if git show-ref --verify --quiet "refs/heads/${checkout_branch}"; then
      git switch "${checkout_branch}" >/dev/null 2>&1
    else
      git switch -c "${checkout_branch}" "origin/${checkout_branch}" >/dev/null 2>&1
    fi
    git pull --ff-only origin "${checkout_branch}" >/dev/null 2>&1 || true
  fi
elif [[ "$KEEP_BRANCH" == "true" ]]; then
  echo "==> Spec repo: keeping branch $(git branch --show-current 2>/dev/null)" >&2
fi

if [[ "$CREATED_SPEC" == "true" ]]; then
  echo "==> Copying scaffold from templates/spec-repo ..." >&2
  cp -R "${ROOT}/templates/spec-repo/." .
else
  mkdir -p docs/agents
fi

{
  echo "# Generated by setup-project."
  echo "# Routing configuration; rerunning replaces the repo list below."
  echo "repos:"
  for target in "${TARGETS[@]}"; do
    impl="${PARENT_DIR}/${target}"
    if [[ -d "${impl}/.git" ]] && full="$(stack_gh_repo_from_dir "$impl" 2>/dev/null)"; then
      :
    else
      full="$(stack_normalize_repo "$ORG" "$target")"
    fi
    echo "  - name: ${full}"
    echo "    role: target"
  done
} > docs/agents/repos.md

git add -A
if ! git diff --cached --quiet; then
  if [[ "$CREATED_SPEC" == "true" ]]; then
    git commit -m "chore: bootstrap ${SPEC_NAME} scaffold" >/dev/null 2>&1 || true
  else
    git commit -m "chore: sync ${SPEC_NAME} target repos" >/dev/null 2>&1 || true
  fi
  echo "==> Committed registry sync in spec repo ($(git branch --show-current))" >&2
fi
git push -u origin HEAD >/dev/null 2>&1 || true

seed_one() {
  local repo="$1"
  [[ -f .github/labels.yml ]] || return 0
  yq -o=json '.[]' .github/labels.yml 2>/dev/null | jq -c '.' | while read -r row; do
    name=$(echo "$row" | jq -r .name)
    color=$(echo "$row" | jq -r .color)
    desc=$(echo "$row" | jq -r '.description // ""')
    gh label create "$name" --repo "$repo" --color "$color" --description "$desc" --force 2>/dev/null || true
  done
}

if command -v yq &>/dev/null && command -v jq &>/dev/null; then
  seed_one "$SPEC_REPO" >&2
  while IFS= read -r r; do
    [[ -z "$r" ]] && continue
    seed_one "$r" >&2
  done < <(yq -r '.repos[].name' docs/agents/repos.md 2>/dev/null || true)
fi

# ONLY stdout: absolute spec path (for capture by parent script)
printf '%s\n' "$SPEC_DIR"
```

### `bin/stack/sync_spec_tooling.sh`

```bash
#!/usr/bin/env bash
# Sync fanout tooling into a spec repo; optional --check-only.
# Usage: sync_spec_tooling.sh [--check-only] <spec-repo-path>
# Exit: 0 ok, 3 registry incomplete, 6 PRD validation errors
set -euo pipefail
CHECK_ONLY=false
if [[ "${1:-}" == "--check-only" ]]; then
  CHECK_ONLY=true
  shift
fi
SPEC="${1:?spec repo path}"
OC="$(cd "$(dirname "$0")/../.." && pwd)"
TEMPLATE="${OC}/templates/spec-repo"
MIGRATE="${OC}/bin/lib/migrate_repos_registry.py"

SPEC="$(cd "$SPEC" && pwd)"

if [[ ! -d "$TEMPLATE" ]]; then
  echo "ERROR: missing OpenCode template at $TEMPLATE" >&2
  exit 1
fi

if ! [[ -d "$SPEC/docs/prd" || -f "$SPEC/docs/agents/repos.md" ]]; then
  echo "ERROR: $SPEC does not look like a spec repo" >&2
  exit 1
fi

if [[ "$CHECK_ONLY" == "true" ]]; then
  REGISTRY="$SPEC/docs/agents/repos.md"
  [[ -f "$REGISTRY" ]] || { echo "INCOMPLETE: missing $REGISTRY"; exit 3; }
  python3 "$MIGRATE" "$REGISTRY" --check-only
  VALIDATE="$SPEC/bin/lib/validate_tickets.py"
  if [[ -f "$VALIDATE" ]] && command -v yq >/dev/null 2>&1; then
    shopt -s nullglob
    for prd in "$SPEC"/docs/prd/*.md; do
      [[ "$(basename "$prd")" == "_template.md" ]] && continue
      count=$(yq '.tickets // [] | length' "$prd" 2>/dev/null || echo 0)
      [[ "${count:-0}" -gt 0 ]] || continue
      slug=$(yq -r '.slug // ""' "$prd" 2>/dev/null || basename "$prd" .md)
      echo "--> validating tickets in $slug"
      yq -o=json '.tickets' "$prd" | python3 "$VALIDATE" "$REGISTRY" || exit 6
    done
  fi
  echo "==> check-only: ok"
  exit 0
fi

mkdir -p "$SPEC/bin/lib" "$SPEC/skills/fanout-issues" "$SPEC/docs/agents" "$SPEC/docs/prd"

echo "==> Syncing spec tooling..."
install -m0755 "$TEMPLATE/bin/fanout" "$SPEC/bin/fanout"
install -m0755 "$TEMPLATE/bin/lib/validate_tickets.py" "$SPEC/bin/lib/validate_tickets.py"
install -m0755 "$TEMPLATE/bin/lib/toposort_tickets.py" "$SPEC/bin/lib/toposort_tickets.py"
[[ -f "$TEMPLATE/bin/status" ]] && install -m0755 "$TEMPLATE/bin/status" "$SPEC/bin/status"
[[ -f "$TEMPLATE/bin/new-prd" ]] && install -m0755 "$TEMPLATE/bin/new-prd" "$SPEC/bin/new-prd"
cp "$TEMPLATE/docs/prd/_template.md" "$SPEC/docs/prd/_template.md"
cp "$TEMPLATE/skills/fanout-issues/SKILL.md" "$SPEC/skills/fanout-issues/SKILL.md"

REGISTRY="$SPEC/docs/agents/repos.md"
if [[ ! -f "$REGISTRY" ]]; then
  cp "$TEMPLATE/docs/agents/repos.md" "$REGISTRY"
fi

REGISTRY_INCOMPLETE=false
python3 "$MIGRATE" "$REGISTRY" || REGISTRY_INCOMPLETE=true

PRD_ERRORS=0
if command -v yq >/dev/null 2>&1; then
  shopt -s nullglob
  for prd in "$SPEC"/docs/prd/*.md; do
    base=$(basename "$prd")
    [[ "$base" == "_template.md" ]] && continue
    count=$(yq '.tickets // [] | length' "$prd" 2>/dev/null || echo 0)
    [[ "${count:-0}" -gt 0 ]] || continue
    if ! yq -o=json '.tickets' "$prd" | python3 "$SPEC/bin/lib/validate_tickets.py" "$REGISTRY"; then
      PRD_ERRORS=$((PRD_ERRORS + 1))
    fi
  done
fi

if [[ "$REGISTRY_INCOMPLETE" == "true" ]]; then
  exit 3
fi
if [[ "$PRD_ERRORS" -gt 0 ]]; then
  exit 6
fi
exit 0
```

### `bin/stack/link_impl_repo.sh`

```bash
#!/usr/bin/env bash
# Link one implementation repo to a spec repo (internal; use setup-project).
# Usage: link_impl_repo.sh <impl-repo-dir> <owner/name-spec-repo>
set -euo pipefail
IMPL_DIR="${1:?implementation repo directory}"
SPEC_REPO="${2:?owner/name spec repo}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

cd "$IMPL_DIR"
mkdir -p docs/agents bin
cat > docs/agents/issue-tracker.md <<'EOF'
# Issue tracker

Issues for this repository are tracked on **GitHub**.

- **CLI:** `gh issue create`, `gh issue view`, `gh issue list`
- **Remote:** (see `git remote get-url origin`)

## Spec repository (parent PRDs)

- **SPEC_REPO:** __SPEC_REPO__

`bin/feature-context` reads **SPEC_REPO** from this file.
EOF
if [[ "$(uname -s)" == "Darwin" ]]; then
  sed -i '' "s|__SPEC_REPO__|${SPEC_REPO}|g" docs/agents/issue-tracker.md
else
  sed -i "s|__SPEC_REPO__|${SPEC_REPO}|g" docs/agents/issue-tracker.md
fi

if [[ ! -f bin/feature-context ]]; then
  install -m0755 "${ROOT}/templates/bin/feature-context" bin/feature-context
  echo "Installed bin/feature-context in $(basename "$IMPL_DIR")."
fi

touch .gitignore
if ! grep -q '^tmp/' .gitignore 2>/dev/null; then
  printf '\n# OpenCode scratch\ntmp/\n.research/\n.qa/\n.plan/*.completed.md\n' >> .gitignore
  echo "Appended OpenCode scratch paths to .gitignore in $(basename "$IMPL_DIR")."
fi

echo "Linked $(basename "$IMPL_DIR") → SPEC_REPO=${SPEC_REPO}"
```

### `bin/stack/check_impl_wiring.sh`

```bash
#!/usr/bin/env bash
# Report implementation repo wiring gaps (for --check-only).
# Usage: check_impl_wiring.sh <parent-dir> <org> <app-slug>
set -euo pipefail
PARENT_DIR="$(cd "$1" && pwd)"
ORG="$2"
APP="$3"
# shellcheck source=common.sh
source "$(dirname "$0")/common.sh"

SPEC_NAME="${APP}-spec"
GAPS=0

while IFS= read -r local_dir; do
  [[ -z "$local_dir" ]] && continue
  stack_dir_is_spec_repo "$PARENT_DIR" "$local_dir" "${APP}-spec" && continue
  impl="${PARENT_DIR}/${local_dir}"
  [[ -d "$impl/.git" ]] || continue
  missing=()
  [[ -f "$impl/docs/agents/issue-tracker.md" ]] || missing+=("issue-tracker.md")
  grep -q '^SPEC_REPO:' "$impl/docs/agents/issue-tracker.md" 2>/dev/null || missing+=("SPEC_REPO line")
  [[ -x "$impl/bin/feature-context" ]] || missing+=("bin/feature-context")
  grep -q '^tmp/' "$impl/.gitignore" 2>/dev/null || missing+=("gitignore scratch paths")
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "INCOMPLETE: ${local_dir}: ${missing[*]}"
    GAPS=$((GAPS + 1))
  else
    echo "OK: ${local_dir}"
  fi
done < <(stack_discover_targets "$PARENT_DIR" "$SPEC_NAME")

if [[ "$GAPS" -gt 0 ]]; then
  exit 4
fi
exit 0
```

### `bin/stack/print_next_steps.sh`

```bash
#!/usr/bin/env bash
# Print operator next steps after setup-project.
# Usage: print_next_steps.sh <spec-repo-path> <check-exit-code>
set -euo pipefail
SPEC="${1:?spec repo path}"
CHECK_CODE="${2:-0}"
OC="$(cd "$(dirname "$0")/../.." && pwd)"
SPEC="$(cd "$SPEC" && pwd)"

echo ""
echo "========================================"
if [[ "$CHECK_CODE" -eq 3 || "$CHECK_CODE" -eq 6 ]]; then
  echo "Shell bootstrap done; registry or PRDs need OpenCode setup-project skill."
  echo ""
  echo "  cd \"$SPEC\" && opencode"
  echo "  # In architect:"
  echo "  #   Run setup-project — complete docs/agents/repos.md and configure all implementation repos."
  echo ""
  echo "Re-check:"
  echo "  \"$OC/bin/setup-project\" --check-only \"$(dirname "$SPEC")\""
  exit 0
fi

echo "Stack bootstrap complete."
echo ""
echo "Next:"
echo "  cd \"$SPEC\" && opencode"
echo "  # In architect:"
echo "  #   Run setup-project"
echo ""
echo "Validate anytime (from project parent $(dirname "$SPEC")):"
echo "  \"$OC/bin/setup-project\" --check-only \"$(dirname "$SPEC")\""
echo "  # Or if OpenCode bin/ is on PATH:"
echo "  setup-project --check-only \"$(dirname "$SPEC")\""
echo ""
echo "When registry is complete: grill-me → to-prd → approve → bin/fanout <slug>"
```

### `bin/setup-project`

```bash
#!/usr/bin/env bash
# Bootstrap or upgrade a PROJECT stack: spec repo + linked implementation repos.
# Run from the project parent folder (container with PROJECT-spec and PROJECT-* siblings).
#
# Usage (script lives in the OpenCode config repo, NOT in your APP/ project folder):
#   cd ~/code/APP
#   ~/.config/opencode/bin/setup-project
# Or add once to PATH: export PATH="$HOME/.config/opencode/bin:$PATH"
#   GH_ORG=owner setup-project [options] [project-parent-dir]
#
# Options:
#   --check-only   Validate registry, PRDs, and impl wiring (no writes)
#   --spec-only    Create/sync spec only; skip linking implementation repos
#   --keep-branch  Do not checkout develop/main in the spec repo (stay on current branch)
#   --app <slug>   App slug (default: basename of parent directory)
#   --org <org>    GitHub org (default: GH_ORG env)
#   -h, --help
set -euo pipefail

OC="$(cd "$(dirname "$0")/.." && pwd)"
STACK="${OC}/bin/stack"
CHECK_ONLY=false
SPEC_ONLY=false
KEEP_BRANCH=false
APP=""
ORG="${GH_ORG:-}"
PARENT=""

usage() {
  cat <<EOF
Bootstrap or upgrade a PROJECT stack (spec + implementation repos).

Install location: ${OC}/bin/setup-project
(This is not ./bin/setup-project inside your APP folder.)

Run from the project parent directory (sibling folders: APP-spec, APP-web, ...):
  cd ~/code/APP
  export GH_ORG=your-org
  ${OC}/bin/setup-project

Optional — add OpenCode CLI tools to PATH (shell rc):
  export PATH="${OC}/bin:\$PATH"
  setup-project

Options:
  --check-only     Validate registry, PRDs, impl wiring (no writes)
  --spec-only      Create/sync spec only
  --keep-branch    Keep current git branch in spec repo (skip develop/main checkout)
  --app <slug>     App slug (default: parent folder basename)
  --org <org>      GitHub org (default: GH_ORG env)
EOF
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --check-only) CHECK_ONLY=true; shift ;;
    --spec-only) SPEC_ONLY=true; shift ;;
    --keep-branch) KEEP_BRANCH=true; shift ;;
    --app)
      APP="${2:?}"
      shift 2
      ;;
    --org)
      ORG="${2:?}"
      shift 2
      ;;
    -*)
      echo "unknown option: $1" >&2
      usage 1
      ;;
    *)
      PARENT="$1"
      shift
      ;;
  esac
done

if [[ -z "$ORG" ]]; then
  echo "ERROR: set GH_ORG or pass --org <org>" >&2
  exit 1
fi

if [[ -z "$PARENT" ]]; then
  PARENT="$(pwd)"
fi
PARENT="$(cd "$PARENT" && pwd)"

# shellcheck source=stack/common.sh
source "${STACK}/common.sh"

if [[ -z "$APP" ]]; then
  APP="$(stack_default_app_slug "$PARENT")"
fi

SPEC_DIR="$(stack_resolve_spec_dir "$PARENT" "$APP")"

# If spec exists on disk, trust folder + remote (blocshed-spec may map to roborew/BlocShed-spec).
if [[ -d "${SPEC_DIR}/.git" ]]; then
  APP="$(stack_app_slug_from_spec_dir "$SPEC_DIR")"
  if SPEC_REPO="$(stack_gh_repo_from_dir "$SPEC_DIR")"; then
    :
  else
    SPEC_REPO="${ORG}/${APP}-spec"
  fi
else
  SPEC_REPO="${ORG}/${APP}-spec"
fi
SPEC_NAME="${SPEC_REPO#*/}"

TARGETS=()
while IFS= read -r t; do
  [[ -z "$t" ]] && continue
  TARGETS+=("$t")
done < <(stack_discover_targets "$PARENT" "$SPEC_NAME")

if [[ "$CHECK_ONLY" == "true" ]]; then
  echo "==> check-only: ${PARENT}"
  CHECK_CODE=0
  if [[ -d "$SPEC_DIR" ]] && stack_is_spec_repo "$SPEC_DIR"; then
    "${STACK}/sync_spec_tooling.sh" --check-only "$SPEC_DIR" || CHECK_CODE=$?
  else
    echo "INCOMPLETE: missing or invalid spec repo at ${SPEC_DIR}"
    CHECK_CODE=3
  fi
  if [[ "$SPEC_ONLY" != "true" ]]; then
    "${STACK}/check_impl_wiring.sh" "$PARENT" "$ORG" "$APP" || {
      c=$?
      [[ "$CHECK_CODE" -eq 0 ]] && CHECK_CODE=$c
    }
  fi
  if [[ "$CHECK_CODE" -eq 0 ]]; then
    echo "==> All checks passed."
  fi
  exit "$CHECK_CODE"
fi

echo "==> Project parent: ${PARENT}"
echo "==> App slug: ${APP} (from parent folder / spec dir; override with --app)"
echo "==> Spec repo: ${SPEC_REPO}"
if [[ "$(basename "$PARENT" | tr '[:upper:]' '[:lower:]')" != "$APP" ]]; then
  echo "    Note: parent folder name differs from app slug; using on-disk spec: $(basename "$SPEC_DIR")" >&2
fi

CREATE_ARGS=()
[[ "$KEEP_BRANCH" == "true" ]] && CREATE_ARGS+=(--keep-branch)
SPEC_PATH="$("${STACK}/create_or_sync_spec.sh" "${CREATE_ARGS[@]}" "$PARENT" "$APP" "$ORG" "${TARGETS[@]}")"
if [[ ! -d "$SPEC_PATH" ]]; then
  echo "ERROR: invalid spec path (internal bug). Got: ${SPEC_PATH}" >&2
  exit 1
fi
echo "==> Spec at: ${SPEC_PATH} (branch: $(git -C "$SPEC_PATH" branch --show-current 2>/dev/null || echo unknown))"

SYNC_CODE=0
"${STACK}/sync_spec_tooling.sh" "$SPEC_PATH" || SYNC_CODE=$?

if [[ "$SPEC_ONLY" != "true" ]]; then
  echo ""
  echo "==> Linking implementation repos..."
  LINK="${STACK}/link_impl_repo.sh"
  for target in "${TARGETS[@]}"; do
    local_dir="$(stack_local_dir_for_target "$target")"
    impl_path="${PARENT}/${local_dir}"
    if stack_dir_is_spec_repo "$PARENT" "$local_dir" "${APP}-spec"; then
      echo "SKIP: ${local_dir} is the spec repo, not an implementation repo" >&2
      continue
    fi
    if [[ -d "${impl_path}/.git" ]]; then
      "$LINK" "${impl_path}" "$SPEC_REPO"
    else
      echo "WARN: ${local_dir} not found under ${PARENT}" >&2
    fi
  done
fi

echo ""
echo "=== LABEL_SYNC_PAT (optional) ==="
echo "  gh secret set LABEL_SYNC_PAT --repo ${SPEC_REPO}"
echo ""

"${STACK}/print_next_steps.sh" "$SPEC_PATH" "$SYNC_CODE"
exit "$([[ "$SYNC_CODE" -eq 0 ]] && echo 0 || echo "$SYNC_CODE")"
```

### `bin/new-spec-repo`

```bash
#!/usr/bin/env bash
echo "DEPRECATED: use bin/setup-project (from your PROJECT parent folder)" >&2
exec "$(dirname "$0")/setup-project" "$@"
```

### `bin/link-spec-repo`

```bash
#!/usr/bin/env bash
# DEPRECATED: run setup-project from the PROJECT parent folder instead.
echo "DEPRECATED: use bin/setup-project from the PROJECT parent directory" >&2
OC="$(cd "$(dirname "$0")/.." && pwd)"
SPEC_REPO="${1:?owner/name spec repo required}"
if [[ -f docs/agents/issue-tracker.md ]] && [[ -d .git ]]; then
  exec "${OC}/bin/stack/link_impl_repo.sh" "$(pwd)" "$SPEC_REPO"
fi
echo "Run from PROJECT parent: ${OC}/bin/setup-project" >&2
exit 1
```

### `bin/upgrade-spec-repo`

```bash
#!/usr/bin/env bash
# DEPRECATED: use setup-project from the PROJECT parent folder, or:
#   setup-project --check-only /path/to/PROJECT
echo "DEPRECATED: use bin/setup-project" >&2
OC="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${1:-}" == "--check-only" ]]; then
  shift
  SPEC="${1:-$(pwd)}"
  exec "${OC}/bin/stack/sync_spec_tooling.sh" --check-only "$SPEC"
fi
SPEC="${1:-$(pwd)}"
PARENT="$(dirname "$(cd "$SPEC" && pwd)")"
exec "${OC}/bin/setup-project" "$PARENT"
```

### `agents/stack-bootstrap.md`

```markdown
---
description: Cross-repo template installer for setup-project (spec-coordinated stacks only)
mode: subagent
model: openrouter/openai/gpt-5-nano
tools:
  write: true
  edit: true
  bash: true
  skill: true
permission:
  bash:
    "*": allow
    "rm -rf /*": deny
    "rm -rf ~/*": deny
  skill: { "stack-bootstrap": "allow" }
  edit:
    "~/.config/opencode/**": deny
    "*": allow
  task:
    "*": deny
---
# Stack Bootstrap Agent

You install OpenCode agent scaffolding into **implementation repositories** when the parent **architect** runs **`setup-project`**. You are a leaf worker: no Task to other agents.

## Execution readiness

- Parent must pass `load: full` and **`local_path`** (absolute path to one target repo).
- Load the **`stack-bootstrap`** skill before first tool use when `load: full`.

## Responsibilities

- Copy bundled templates from the OpenCode config checkout into paths **under `local_path` only**.
- Run `chmod +x` on `bin/feature-context` when installed.
- Create `.plan/_archive/legacy/` or `docs/_archive/legacy/` when the parent requests legacy migration.
- Run read-only validation commands the parent specifies (`setup-project --check-only`, etc.) and return stdout.

## Hard rules

1. **Never edit application source** (`src/`, `app/`, `lib/` package code, etc.) unless the parent explicitly lists a doc-only path.
2. **Never write outside `local_path`** for that Task.
3. Do not modify `~/.config/opencode/**`.
4. Do not delete files; **move** to `_archive/legacy/` only when the parent provides exact source and destination paths.
5. Return a concise report: files created/updated, commands run, failures.
```

### `skills/stack-bootstrap/SKILL.md`

```markdown
---
name: stack-bootstrap
description: Install OpenCode templates into one implementation repo path; optional legacy .plan/docs archive moves. Invoked only from setup-project via architect.
---

# Stack bootstrap

## Parent contract

The architect Task prompt must include:

- `local_path`: absolute path to **one** implementation git repo
- `spec_repo`: `owner/APP-spec` for `issue-tracker.md` substitution
- `operations`: list of `copy_templates` | `archive_legacy_plan` | `run_check`

## copy_templates

Resolve OpenCode config root as `OC="${OPENCODE_CONFIG:-$HOME/.config/opencode}"`.

Copy when missing or when parent says `force: true` for that file:

| Source | Destination (under `local_path`) |
|--------|----------------------------------|
| `skills/setup-skills/templates/issue-tracker.md` | `docs/agents/issue-tracker.md` (set `SPEC_REPO:` line) |
| `skills/setup-skills/templates/triage-labels.md` | `docs/agents/triage-labels.md` |
| `skills/setup-skills/templates/domain.md` | `docs/agents/domain.md` |
| `templates/bin/feature-context` | `bin/feature-context` (chmod +x) |
| `templates/.github/ISSUE_TEMPLATE/child-feature.yml` | `.github/ISSUE_TEMPLATE/child-feature.yml` |
| `docs/templates/opencode.md.template` | `opencode.md` (only if missing) |

Ensure `.gitignore` contains:

```gitignore
tmp/
.research/
.qa/
.plan/*.completed.md
```

## archive_legacy_plan

When parent provides `source` and `dest` both under `local_path/.plan/`:

```bash
mkdir -p "$(dirname "$dest")"
mv "$source" "$dest"
```

Create `local_path/.plan/_archive/legacy/README.md` once:

```markdown
# Legacy plans

Archived during setup-project when work moved to GitHub issue-backed execution.
```

## run_check

```bash
"${OC}/bin/setup-project" --check-only "$(dirname "$(dirname "$local_path")")"
```

Return exit code and last 30 lines of output.
```

### `skills/setup-project/SKILL.md`

```markdown
---
name: setup-project
description: Spec-repo-only stack bootstrap — discover siblings, interview, legacy .plan/docs audit, configure all implementation repos via stack-bootstrap and scribe. Replaces per-repo setup-skills for vertical stacks.
modelTier: smart
roleReminder: "Run only in PROJECT-spec (docs/prd/ or spec layout). Never ask the user to cd into each implementation repo."
---

# Setup project (spec repo)

Orchestrate **one OpenCode session in `PROJECT-spec`** to configure the entire sibling stack under the parent folder. The parent `PROJECT/` directory must contain **no** project files — only `PROJECT-spec` and `PROJECT-*` implementation repos.

## Preconditions

- Session cwd is the **spec repo** (`docs/prd/` or `docs/agents/repos.md`).
- Sibling implementation repos exist at `../<repo-basename>` (discovered from git remotes in `docs/agents/repos.md` or directory scan).
- Shell bootstrap already ran from the **project parent** folder (e.g. `~/code/APP`), using the OpenCode config script — **not** `./bin/setup-project` inside `APP/`:

  ```bash
  export PATH="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}/bin:$PATH"
  cd ~/code/APP && setup-project
  ```

  Optional re-check via delegated bash (same path as `skills/stack-bootstrap` uses):

  ```bash
  OC="${OPENCODE_CONFIG_DIR:-${OPENCODE_CONFIG:-$HOME/.config/opencode}}"
  "$OC/bin/setup-project" --check-only "$(dirname "$PWD")"
  ```

## Phase A — Discover scope

1. Read `docs/agents/repos.md`.
2. **Spec repo identity:** use `gh repo view --json nameWithOwner -q .nameWithOwner` (preferred — architect bash allowlist). Fallback: `git remote get-url origin` only if allowed; otherwise read `SPEC_REPO` from any impl sibling's `docs/agents/issue-tracker.md`.
3. List sibling git directories: `ls -d ../*/ 2>/dev/null` and filter those with `.git` (skip `*-spec` folders). Match registry `repo:` entries to folder names via basename (`roborew/blocshed-api` → `../blocshed-api`).
4. Do **not** run mutating git commands. For remote URLs on siblings, use registry + `gh repo view --repo owner/name --json nameWithOwner` or Task **`developer`** `load: minimal` with `git -C ../blocshed-api remote get-url origin`.
Emit a **Setup status** table per repo:

| Repo | In registry | issue-tracker | triage-labels | feature-context | child-feature.yml | opencode.md | CONTEXT.md |
|------|-------------|---------------|---------------|-----------------|-------------------|-------------|--------------|

Flag orphans (local git dir not in registry) and registry entries without local clones.

## Phase B — Interview (stack-wide)

One topic at a time (same substance as **`setup-skills`**):

- Shared triage labels (`docs/agents/triage-labels.md` pattern for all repos).
- Per repo: `application_role`, `capabilities`, `non_goals`, `agent_owner`, `default_test_commands`.
- Product vocabulary → spec `CONTEXT.md` / `LANGUAGE.md`.

## Phase C — Legacy audit (implementation repos)

For **each** sibling implementation repo, read-only scan then propose batch actions; **human confirms** before moves.

### Audit targets

| Location | Action |
|----------|--------|
| `.plan/feature.*.md` (not `*.completed.md`) | See migration table |
| `.plan/debug.*`, `refactor.*`, `review.*`, `design.*` | Keep if active; else archive |
| `docs/agents/` | Merge toward template set; duplicates → `docs/_archive/legacy/` |
| `CONTEXT.md` vs spec | Impl = repo gotchas only; product glossary stays in **spec** `CONTEXT.md` |

### Migration rules

| Situation | Action |
|-----------|--------|
| `.plan/feature.<slug>.md`, no open `feature:<slug>` issues in that repo | **stack-bootstrap** `archive_legacy_plan` → `.plan/_archive/legacy/<slug>.md` |
| `.plan/feature.<slug>.md`, open `feature:<slug>` issues | Tell user to run **`issue-expand`** then archive; offer to archive after expand |
| Obsolete `docs/agents/*` | **stack-bootstrap** move to `docs/_archive/legacy/` or **scribe** merge |
| Conflicting product terms in impl `CONTEXT.md` | **scribe** trims impl file; documents split in `docs/agents/domain.md` |

**Non-destructive:** archive, never delete. Summarize: "Archived N plans, updated M repos, K need your input."

## Phase D — Apply

1. **scribe** — update spec `docs/agents/repos.md` with full registry schema (`repo`, `application_role`, `capabilities`, `non_goals`, `agent_owner`, optional `default_test_commands`).
2. **stack-bootstrap** — one Task per implementation repo (`load: full`, `local_path`, `spec_repo`, `operations: [copy_templates]`).
3. Legacy archives — **stack-bootstrap** per confirmed move.
4. **developer** (bash) — run from spec repo:
   ```bash
   OC="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
   bash -lc "$OC/bin/setup-project --check-only $(dirname "$PWD")"
   ```
5. Report pass/fail. If exit 3: registry incomplete. If exit 4: impl wiring gaps. If exit 6: PRD ticket validation errors.

## Done message

When check passes:

- Stack is ready for `grill-me` / `to-prd` / `bin/fanout`.
- Implementation work uses **issue-expand** → **orchestrate** (not per-repo setup-skills).
- Close features with **feature-complete** in this spec repo.

## Hard rules

- Do not invoke `to-prd`, `fanout`, or `orchestrate` from this skill.
- Do not infer backend/frontend from repo names; use registry fields.
- **setup-skills** remains for a **single orphan repo** not in a stack — not for normal stack onboarding.
```

### `skills/issue-expand/SKILL.md`

```markdown
---
name: issue-expand
description: Deepen GitHub child issues with TDD stages in opencode-task-json and Implementation plan sections. Issue queue is source of truth — no new .plan files for spec-driven features.
modelTier: smart
roleReminder: "Implementation repo only. Architect plans; developer runs gh issue edit."
---

# Issue expand

Enrich **layer-2** fanout tickets before **orchestrate** runs. Output lives on **GitHub issues**, not local `.plan/` files.

## Preconditions

- Implementation repo with `docs/agents/issue-tracker.md` (`SPEC_REPO:` line).
- `gh` authenticated.
- Child issues labelled `feature:<slug>` exist (from `bin/fanout`).

## Feature selection

List distinct open feature labels:

```bash
gh issue list --state open --json labels --jq '[.[].labels[].name | select(startswith("feature:"))] | unique | .[]'
```

- **One slug** → confirm: "Working on `<slug>` — N open tickets."
- **Several** → numbered menu; user picks (or they passed `feature:<slug>` upfront).
- **Single issue** → user gave `#42`; expand only that issue.

Optional hydrate per issue:

```bash
bin/feature-context <issue-number>
```

## Planning depth

Match **`architect-plan`** rigor for one ticket at a time:

- Claude Context readiness before discovery.
- Files to change, TDD order, risks, test strategy.
- 1–5 **`stages`** per issue (3–7 steps total across a large ticket is fine).

## opencode-task-json extension

Preserve existing fields (`task_id`, `owner`, `commit_message`, `acceptance`, `test_commands`, `depends_on`, `capability`). Add:

```json
"stages": [
  {
    "stage_id": "1-red",
    "owner": "developer",
    "objective": "Failing test for ...",
    "files": ["path/to/file.test.ts"],
    "acceptance": ["Test fails for the right reason"],
    "test_commands": ["pnpm test path/to/file.test.ts"],
    "commit_message": "test(api): add failing test for ..."
  }
]
```

Last stage `commit_message` may use `Closes: #<n>` semantics when appropriate.

## Issue body layout

Keep existing sections. Append or update:

```markdown
## Implementation plan

<human-readable bullets: files, order, notes>

## OpenCode task (machine-readable)
```opencode-task-json
{ ... full meta including stages ... }
```
```

## Human gate

Show proposed stages and files **before** any GitHub write. User must confirm.

## GitHub writes (architect → developer)

Task **`developer`** with `load: minimal`:

```bash
gh issue edit <n> --body-file /tmp/issue-body.md
```

Body must be assembled verbatim from architect draft. Never edit source code in this Task.

For batch expand, one issue per developer Task.

## After expand

Prompt: **Switch to `orchestrate`** → GitHub backlog `feature:<slug>`. Orchestrate runs **`stages[]`** when present.

## Hard rules

- Do **not** invoke `scribe` to write `.plan/feature.*` or `.plan/issue.*` on this path.
- Do **not** invoke `orchestrate`.
- Child issues (mode B) only when user explicitly approves splitting a ticket.
```

### `skills/feature-complete/SKILL.md`

```markdown
---
name: feature-complete
description: Close a spec-driven feature after all implementation repos finished — cross-repo issue rollup, PR links on spec parent issue, close PRD parent.
modelTier: smart
roleReminder: "Run in PROJECT-spec only. Do not close the spec parent from an implementation repo session."
---

# Feature complete

**Level 3** ceremony: whole feature done across all repos. Per-repo work should already be closed via **Mode F** in each implementation repo.

## Preconditions

- Session cwd is **spec repo** (`docs/prd/`, `docs/agents/repos.md`).
- User provides kebab **`feature:<slug>`** (without prefix) or `feature:<slug>` label string.
- `docs/prd/<slug>.md` exists with `parent_issue` URL in frontmatter.

## Data collection

1. Read `docs/prd/<slug>.md` and `docs/agents/repos.md`.
2. Task **`developer`** `load: minimal` — for each registry `repo`:

   ```bash
   gh issue list --repo <owner/name> -l "feature:<slug>" --state all -L 200 \
     --json number,title,state,url,labels
   ```

3. Compare PRD **`tickets:`** `id` values to closed issues per repo. Flag open or missing tickets.
4. Collect PR URLs from issue comments, linked PRs, or:

   ```bash
   gh search prs "repo:<owner/name> <slug>" --json number,url,state --limit 20
   ```

## Rollup comment on spec parent

Parse `parent_issue` from PRD frontmatter (GitHub issue URL). Task **`developer`**:

```bash
gh issue comment <parent-n> --repo <spec-owner/name> --body-file /tmp/rollup.md
```

Rollup table columns: **Repo** | **Issue** | **State** | **PR link**

## Human gate

Present rollup and gaps. Ask: **Close spec parent issue?** Only on explicit yes.

## Close parent

```bash
gh issue close <parent-n> --repo <spec-owner/name>
```

Optional: `gh issue edit` add label `state:done`.

## PRD delivery record

Task **`scribe`** to append to `docs/prd/<slug>.md`:

```markdown
## Delivery record

- **Completed:** <date>
- **PRs:** <bulleted list>
```

## Per-repo reminder

If any repo still has **open** `feature:<slug>` issues, **stop** — tell user to finish **Mode F** in that impl repo first. Do not close spec parent.

## Hard rules

- Do not invoke `orchestrate` or write application source.
- Final **parent close** happens in **this spec session** only (not from impl repo architect).
```


## 10. StrReplace patches (apply to existing files)

#### `opencode.json`

```diff
--- before
+++ after
```

**Replace this exact block:**

```
    "scribe": {
      "mode": "subagent",
      "model": "openrouter/openai/gpt-5-nano",
      "steps": 5
    },
```

**With:**

```
    "scribe": {
      "mode": "subagent",
      "model": "openrouter/openai/gpt-5-nano",
      "steps": 5
    },
    "stack-bootstrap": {
      "mode": "subagent",
      "model": "openrouter/openai/gpt-5-nano",
      "steps": 15
    },
```


#### `agents/architect.md`

```diff
--- before
+++ after
```

**Replace this exact block:**

```
  skill: { "architect-plan": "allow", "architect-review": "allow", "github-issue-run": "allow", "grill-me": "allow", "handoff": "allow", "to-issues": "allow", "to-prd": "allow", "triage": "allow", "research": "allow", "improve-codebase-architecture": "allow", "zoom-out": "allow", "caveman": "allow", "setup-skills": "allow" }
  task:
    "*": deny
    strategist: allow
    debugger: allow
    refactor: allow
    review: allow
    document: allow
    designer: allow
    scribe: allow
```

**With:**

```
  skill: { "architect-plan": "allow", "architect-review": "allow", "github-issue-run": "allow", "grill-me": "allow", "handoff": "allow", "to-issues": "allow", "to-prd": "allow", "triage": "allow", "research": "allow", "improve-codebase-architecture": "allow", "zoom-out": "allow", "caveman": "allow", "setup-skills": "allow", "setup-project": "allow", "issue-expand": "allow", "feature-complete": "allow" }
  task:
    "*": deny
    strategist: allow
    debugger: allow
    refactor: allow
    review: allow
    document: allow
    designer: allow
    scribe: allow
    stack-bootstrap: allow
    developer: allow
```


#### `agents/architect.md`

```diff
--- before
+++ after
```

**Replace this exact block:**

```
2. Implementation feature / child issue (implementation repo): plan the code slice from an issue or local requirement, then hand off to orchestrate.
```

**With:**

```
2. Implementation feature (implementation repo): **A)** issue-backed — expand GitHub tickets (`issue-expand`) then orchestrate; **B)** legacy local `.plan/feature.<slug>.md` then orchestrate.
```


#### `agents/architect.md`

```diff
--- before
+++ after
```

**Replace this exact block:**

```
8. Setup / bootstrap repo config: install/link agent docs, labels, domain layout, or spec repo wiring.
```

**With:**

```
8. Setup / bootstrap stack: **spec repo** → `setup-project` (all siblings); single orphan repo → `setup-skills`.
```


#### `agents/architect.md`

```diff
--- before
+++ after
```

**Replace this exact block:**

```
- If `repos:` is empty or incomplete, run **`setup-skills`** or update the registry via scribe before creating tickets.

**Hard Rules in this agent are authoritative.** Load **only one** *planning-phase* sub-skill per turn among `grill-me`, `architect-plan`, and `architect-review`
```

**With:**

```
- If `repos:` is empty or incomplete, run **`setup-project`** (spec repo) or **`setup-skills`** (single repo) before creating tickets.

**Implementation feature (option 2) — planning mode fork:** When the user selects implementation feature in an **implementation repo**, ask once:

```text
A) Issue-backed (recommended) — enrich GitHub tickets for feature:<slug>; orchestrate runs from the queue.
B) Legacy local plan — .plan/feature.<slug>.md then orchestrate from file.
```

- **A** → load **`issue-expand`** (not `architect-plan` for the primary artifact).
- **B** → complete **`grill-me`** if required, then **`architect-plan`** + scribe → `.plan/`.

**Hard Rules in this agent are authoritative.** Load **only one** *planning-phase* sub-skill per turn among `grill-me`, `architect-plan`, and `architect-review`
```


#### `agents/architect.md`

```diff
--- before
+++ after
```

**Replace this exact block:**

```
- **Setup skills:** User asks to bootstrap `docs/agents/*` + `AGENTS.md` / README block for issue tracker + labels + domain layout → load **`setup-skills`**.
```

**With:**

```
- **Setup project:** User asks to bootstrap the full stack, align siblings, or audit legacy `.plan` files → in **spec repo** load **`setup-project`**; in a single non-stack repo load **`setup-skills`**.
- **Setup skills:** Per-repo bootstrap only when not using a spec-coordinated stack → load **`setup-skills`**.
- **Issue expand:** User wants to deepen GitHub tickets before orchestrate, or chose option 2A → load **`issue-expand`**.
- **Feature complete:** User wants to close the spec parent PRD issue after all impl repos are done → in **spec repo** load **`feature-complete`**.
```


#### `agents/architect.md`

```diff
--- before
+++ after
```

**Replace this exact block:**

```
For **utility** skills (`handoff`, `zoom-out`, `caveman`, `to-issues`, `to-prd`, `triage`, `research`, `improve-codebase-architecture`, `setup-skills`), load **only** that utility for the turn unless the user explicitly combines requests.
```

**With:**

```
For **utility** skills (`handoff`, `zoom-out`, `caveman`, `to-issues`, `to-prd`, `triage`, `research`, `improve-codebase-architecture`, `setup-skills`, `setup-project`, `issue-expand`, `feature-complete`), load **only** that utility for the turn unless the user explicitly combines requests.
```


#### `agents/architect.md`

```diff
--- before
+++ after
```

**Replace this exact block:**

```
6. You may **only** invoke: `strategist`, `debugger`, `refactor`, `review`, `document`, `designer`, and `scribe`. Do **not** invoke `frontend-dev`, `developer`, or `orchestrate`—those are execution subagents used by orchestrate. **Mode B is narrower:** after an orchestrate handoff for review/docs, you may invoke only `review`, `document`, and `scribe`.
```

**With:**

```
6. You may invoke: `strategist`, `debugger`, `refactor`, `review`, `document`, `designer`, `scribe`, `stack-bootstrap`, and **`developer`** only for `gh issue edit` / `gh issue comment` / `gh issue create` when **`issue-expand`** or **`feature-complete`** requires GitHub writes. Do **not** invoke `developer` for product code. Do **not** invoke `orchestrate`. **Mode B is narrower:** after an orchestrate handoff for review/docs, you may invoke only `review`, `document`, and `scribe` (plus `developer` for GitHub comments when closing issues per user request).
```


#### `agents/architect.md`

```diff
--- before
+++ after
```

**Replace this exact block:**

```
If `repos:` is empty or incomplete, run **`setup-skills`** or update the registry via scribe before creating tickets.

**Hard Rules in this agent are authoritative.** Load **only one** *planning-phase* sub-skill per turn among `grill-me`, `architect-plan`, and `architect-review`—do not load `architect-plan` or invoke planning investigation until the **grill-me** phase is complete for this planning episode. For **utility** skills (`handoff`, `zoom-out`, `caveman`, `to-issues`, `to-prd`, `triage`, `research`, `improve-codebase-architecture`, `setup-skills`, `setup-project`, `issue-expand`, `feature-complete`), load **only** that utility for the turn unless the user explicitly combines requests.
```

**With:**

```
If `repos:` is empty or incomplete, run **`setup-project`** (spec repo) or **`setup-skills`** (single repo) before creating tickets.

**Implementation feature (option 2) — planning mode fork:** When the user selects implementation feature in an **implementation repo**, ask once:

```text
A) Issue-backed (recommended) — enrich GitHub tickets for feature:<slug>; orchestrate runs from the queue.
B) Legacy local plan — .plan/feature.<slug>.md then orchestrate from file.
```

- **A** → load **`issue-expand`** (not `architect-plan` for the primary artifact).
- **B** → complete **`grill-me`** if required, then **`architect-plan`** + scribe → `.plan/`.

**Hard Rules in this agent are authoritative.** Load **only one** *planning-phase* sub-skill per turn among `grill-me`, `architect-plan`, and `architect-review`—do not load `architect-plan` or invoke planning investigation until the **grill-me** phase is complete for this planning episode. For **utility** skills (`handoff`, `zoom-out`, `caveman`, `to-issues`, `to-prd`, `triage`, `research`, `improve-codebase-architecture`, `setup-skills`, `setup-project`, `issue-expand`, `feature-complete`), load **only** that utility for the turn unless the user explicitly combines requests.
```


#### `skills/orchestrate-execution/SKILL.md`

```diff
--- before
+++ after
```

**Replace this exact block:**

```
4. **Implement:** Task `developer` or `frontend-dev` per `opencode_meta.owner` with **`load: full`** unless trivial. Include in the Task body the full **GitHub issue contract**:
   - `execution_mode: github_issue`
   - `issue_number`, `repo`, `title`
   - `opencode_meta` verbatim (JSON: task_id, owner, commit_message, acceptance, test_commands, depends_on)

5. **Verify:** Task `verifier` with `load: full` and the same **GitHub issue contract** plus the child completion report.

6. **Grade** the child report using the same rubric as **Child Report Grading Gate** (tests, `git_commit` when files changed, subject aligned with `commit_message`, `Refs: #<issue_number>` or equivalent in commit message).

7. On PASS: Task `developer` `load: minimal` to transition:

   `…/issue-state-transition.sh "<repo>" "<number>" state:ready-for-review`

   Then optional `gh issue comment` via developer with verifier summary + `git_commit` hash.

8. On FAIL: transition to `state:blocked` or leave `state:in-progress` and invoke `helper` per **`orchestrate-recovery`** — do not advance the queue until resolved.

9. **Repeat** from step 2 for the same slug until discovery fails.
```

**With:**

```
4. **Stages vs flat issue:** Parse `opencode_meta` from the discovery JSON.
   - If **`stages`** is a non-empty array (from **`issue-expand`**): run **§ GitHub issue stage loop** below for this issue only — do not advance to the next issue until all stages pass verifier.
   - Else **flat mode:** single implement pass using root `acceptance` and `test_commands` (fanout default).

5. **Implement (flat mode):** Task `developer` or `frontend-dev` per `opencode_meta.owner` with **`load: full`**. **GitHub issue contract:**
   - `execution_mode: github_issue`
   - `issue_number`, `repo`, `title`
   - `opencode_meta` verbatim

6. **Verify (flat mode):** Task `verifier` with `load: full` and the same contract plus completion report.

7. **Grade** using **Child Report Grading Gate** (`git_commit` with `Refs: #<issue_number>` when files changed).

8. On PASS (flat or all stages done): transition `state:ready-for-review`; optional `gh issue comment` with summary + commit hash.

9. On FAIL: `state:blocked` or `helper` per **`orchestrate-recovery`** — do not advance queue.

10. **Repeat** from step 2 for the same slug until discovery fails.

### GitHub issue stage loop (`opencode_meta.stages`)

When `stages[]` is present, for **each** stage in order:

1. Task owner from `stage.owner` (`developer` | `frontend-dev`) with `load: full` and contract:
   - `execution_mode: github_issue_stage`
   - `issue_number`, `repo`, `stage_id`, `stage` object (objective, files, acceptance, test_commands, commit_message)
   - `issue_ref: #<n>` for commits
2. Task `verifier` with same stage contract + completion report.
3. Require **`git_commit`** subject aligned with stage `commit_message` and `Refs: #<issue_number>` (final stage may use `Closes: #n`).
4. On stage FAIL: retry or `helper`; do not advance stage index.
5. After last stage PASS: proceed to step 8 (ready-for-review) for this issue.
```


#### `agents/developer.md`

```diff
--- before
+++ after
```

**Replace this exact block:**

```
1. **Start contract:** Either (a) receive an explicit `.plan/<type>.<slug>.md` path, **or** (b) receive **`execution_mode: github_issue`** with `issue_number`, `repo`, and `opencode_meta` (JSON: task_id, commit_message, acceptance, test_commands, owner). Do not start without one of these.
```

**With:**

```
1. **Start contract:** Either (a) receive an explicit `.plan/<type>.<slug>.md` path, **or** (b) receive **`execution_mode: github_issue`** with `issue_number`, `repo`, and `opencode_meta`, **or** (c) receive **`execution_mode: github_issue_stage`** with `issue_number`, `repo`, `stage_id`, and `stage` (one object from `opencode_meta.stages[]`). Do not start without one of these.
```


#### `agents/developer.md`

```diff
--- before
+++ after
```

**Replace this exact block:**

```
3. **GitHub issue mode:** Treat `opencode_meta.acceptance` as acceptance criteria, `opencode_meta.test_commands` as mandatory checks, and `opencode_meta.commit_message` as the required one-line commit subject (append `Refs: #<issue_number>`). Discover files via codebase search only as needed to satisfy acceptance; do not expand scope beyond the issue + meta.
```

**With:**

```
3. **GitHub issue mode:** Treat `opencode_meta.acceptance` as acceptance criteria, `opencode_meta.test_commands` as mandatory checks, and `opencode_meta.commit_message` as the required one-line commit subject (append `Refs: #<issue_number>`). Discover files via codebase search only as needed to satisfy acceptance; do not expand scope beyond the issue + meta.
4. **GitHub issue stage mode:** Implement only the given `stage` object (`objective`, `files`, `acceptance`, `test_commands`, `commit_message`). Micro-TDD required. Commit subject must match `stage.commit_message` with `Refs: #<issue_number>` (or `Closes: #n` when parent instructs final stage).
```


#### `agents/developer.md`

```diff
--- before
+++ after
```

**Replace this exact block:**

```
4. **GitHub issue stage mode:** Implement only the given `stage` object (`objective`, `files`, `acceptance`, `test_commands`, `commit_message`). Micro-TDD required. Commit subject must match `stage.commit_message` with `Refs: #<issue_number>` (or `Closes: #n` when parent instructs final stage).
4. No redesign. Follow the plan or issue contract exactly.
5. If environment preflight fails, stop with `ENV_BLOCKED` and do not retry the same command.
6. If the same test fails twice without a code change, stop with `blocker_code: STAGE_STUCK` and return to orchestrate.
7. Emit one final report only. Do not repeat completion text or wait for additional prompting after reporting.
8. **Post-completion guard:**
```

**With:**

```
4. **GitHub issue stage mode:** Implement only the given `stage` object (`objective`, `files`, `acceptance`, `test_commands`, `commit_message`). Micro-TDD required. Commit subject must match `stage.commit_message` with `Refs: #<issue_number>` (or `Closes: #n` when parent instructs final stage).
5. No redesign. Follow the plan or issue contract exactly.
6. If environment preflight fails, stop with `ENV_BLOCKED` and do not retry the same command.
7. If the same test fails twice without a code change, stop with `blocker_code: STAGE_STUCK` and return to orchestrate.
8. Emit one final report only. Do not repeat completion text or wait for additional prompting after reporting.
9. **Post-completion guard:**
```


#### `agents/developer.md`

```diff
--- before
+++ after
```

**Replace this exact block:**

```
9. **Brevity.** Default to concise structured output:
```

**With:**

```
10. **Brevity.** Default to concise structured output:
```


#### `docs/plan-artifact-schema.md`

```diff
--- before
+++ after
```

**Replace this exact block:**

```
## OutOfScope
- ...
```
```

**With:**

```
## OutOfScope
- ...
```

## GitHub issue task JSON (`opencode-task-json`)

Fanout and **`issue-expand`** embed a fenced `opencode-task-json` block in GitHub issue bodies. This is the **execution source of truth** for spec-driven features (no parallel `.plan/issue.*` files).

### Root fields (fanout)

| Field | Required | Purpose |
|-------|----------|---------|
| `task_id` | yes | Stable id from PRD ticket |
| `owner` | yes | `developer` or `frontend-dev` |
| `commit_message` | yes | Default commit subject for flat mode |
| `acceptance` | yes | String array |
| `test_commands` | yes | Shell commands |
| `depends_on` | no | Ticket ids (fanout resolves to **Blocked by**) |
| `capability` | no | Registry capability |
| `stages` | no | Added by **issue-expand** — see below |

### `stages[]` (issue-expand)

When non-empty, **orchestrate** runs one stage per loop (`execution_mode: github_issue_stage`) before marking the issue ready-for-review.

| Field | Required | Purpose |
|-------|----------|---------|
| `stage_id` | yes | e.g. `1-red`, `2-green` |
| `owner` | yes | `developer` or `frontend-dev` |
| `objective` | yes | One stage goal |
| `files` | no | Paths to touch |
| `acceptance` | yes | Stage acceptance strings |
| `test_commands` | yes | Commands for verifier |
| `commit_message` | yes | Subject for this stage's commit (`Refs: #n`) |

Human-readable detail may also appear under `## Implementation plan` in the issue body.
```


#### `ocx.jsonc`

```diff
--- before
+++ after
```

**Replace this exact block:**

```
      "fanout-issues": {
        "description": "Spec-repo cross-repo child issue fanout",
        "defaultModel": "openrouter/deepseek/deepseek-v4-flash"
      }
```

**With:**

```
      "fanout-issues": {
        "description": "Spec-repo cross-repo child issue fanout",
        "defaultModel": "openrouter/deepseek/deepseek-v4-flash"
      },
      "setup-project": {
        "description": "Spec-repo stack bootstrap and legacy plan audit",
        "defaultModel": "openrouter/deepseek/deepseek-v4-flash"
      },
      "issue-expand": {
        "description": "Enrich GitHub issues with TDD stages before orchestrate",
        "defaultModel": "openrouter/deepseek/deepseek-v4-flash"
      },
      "feature-complete": {
        "description": "Close spec parent issue after cross-repo delivery",
        "defaultModel": "openrouter/deepseek/deepseek-v4-flash"
      }
```


#### `skills/setup-project/SKILL.md`

```diff
--- before
+++ after
```

**Replace this exact block:**

```
- Shell bootstrap already ran: `bin/setup-project` from the parent folder (optional: re-run `setup-project --check-only` via delegated bash).
```

**With:**

```
- Shell bootstrap already ran from the **project parent** folder (e.g. `~/code/APP`), using the OpenCode config script — **not** `./bin/setup-project` inside `APP/`:

  ```bash
  export PATH="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}/bin:$PATH"
  cd ~/code/APP && setup-project
  ```

  Optional re-check via delegated bash (same path as `skills/stack-bootstrap` uses):

  ```bash
  OC="${OPENCODE_CONFIG_DIR:-${OPENCODE_CONFIG:-$HOME/.config/opencode}}"
  "$OC/bin/setup-project" --check-only "$(dirname "$PWD")"
  ```
```


#### `agents/architect.md`

```diff
--- before
+++ after
```

**Replace this exact block:**

```
    "git grep": allow
    "git grep *": allow
    "gh auth status": allow
    "gh repo view --json nameWithOwner": allow
    "gh repo view --json nameWithOwner *": allow
```

**With:**

```
    "git grep": allow
    "git grep *": allow
    "git remote -v": allow
    "git remote -v *": allow
    "git remote get-url origin": allow
    "git remote get-url origin *": allow
    "git branch --show-current": allow
    "git branch --show-current *": allow
    "gh auth status": allow
    "gh repo view --json nameWithOwner": allow
    "gh repo view --json nameWithOwner *": allow
    "gh repo view --repo * --json nameWithOwner": allow
    "gh issue list *": allow
```


#### `skills/setup-project/SKILL.md`

```diff
--- before
+++ after
```

**Replace this exact block:**

```
## Phase A — Discover scope

1. Read `docs/agents/repos.md`.
2. List sibling git directories: `ls -d ../*/ 2>/dev/null` and filter those with `.git`.
3. Emit a **Setup status** table per repo:
```

**With:**

```
## Phase A — Discover scope

1. Read `docs/agents/repos.md`.
2. **Spec repo identity:** use `gh repo view --json nameWithOwner -q .nameWithOwner` (preferred — architect bash allowlist). Fallback: `git remote get-url origin` only if allowed; otherwise read `SPEC_REPO` from any impl sibling's `docs/agents/issue-tracker.md`.
3. List sibling git directories: `ls -d ../*/ 2>/dev/null` and filter those with `.git` (skip `*-spec` folders). Match registry `repo:` entries to folder names via basename (`roborew/blocshed-api` → `../blocshed-api`).
4. Do **not** run mutating git commands. For remote URLs on siblings, use registry + `gh repo view --repo owner/name --json nameWithOwner` or Task **`developer`** `load: minimal` with `git -C ../blocshed-api remote get-url origin`.
5. Emit a **Setup status** table per repo:
```


#### `skills/setup-project/SKILL.md`

```diff
--- before
+++ after
```

**Replace this exact block:**

```
5. Emit a **Setup status** table per repo:

| Repo | In registry | issue-tracker | triage-labels | feature-context | child-feature.yml | opencode.md | CONTEXT.md |
|------|-------------|---------------|---------------|-----------------|-------------------|-------------|--------------|

Flag orphans (local git dir not in registry) and registry entries without local clones.
```

**With:**

```
Emit a **Setup status** table per repo:

| Repo | In registry | issue-tracker | triage-labels | feature-context | child-feature.yml | opencode.md | CONTEXT.md |
|------|-------------|---------------|---------------|-----------------|-------------------|-------------|--------------|

Flag orphans (local git dir not in registry) and registry entries without local clones.
```


---

## 11. Critical snippets (bugs fixed in same chat)

### 11.1 `create_or_sync_spec.sh` — stdout contract (parent capture bug)

Parent must capture **only** the directory path:

```bash
SPEC_PATH="$("${STACK}/create_or_sync_spec.sh" "${CREATE_ARGS[@]}" "$PARENT" "$APP" "$ORG" "${TARGETS[@]}")"
```

Child must send logs to **stderr** and print **one line** to stdout:

```bash
# gh clone/create — redirect URL noise away from stdout
(cd "$PARENT_DIR" && gh repo clone "$SPEC_REPO" "$CLONE_NAME") 1>&2
# ...
# ONLY stdout: absolute spec path
printf '%s\n' "$SPEC_DIR"
```

### 11.2 `setup-project` — skip spec repo when linking impls

```bash
if stack_dir_is_spec_repo "$PARENT" "$local_dir" "${APP}-spec"; then
  echo "SKIP: ${local_dir} is the spec repo, not an implementation repo" >&2
  continue
fi
```

### 11.3 `common.sh` — case-insensitive spec discovery

```bash
stack_dir_is_spec_repo() {
  local parent_dir="$1" dir="$2" app_spec_name="$3"
  [[ "$(printf '%s' "$dir" | tr '[:upper:]' '[:lower:]')" == \
     "$(printf '%s' "$app_spec_name" | tr '[:upper:]' '[:lower:]')" ]] && return 0
  [[ "$(printf '%s' "$dir" | tr '[:upper:]' '[:lower:]')" == *-spec ]] && \
     stack_is_spec_repo "${parent_dir}/${dir}" && return 0
  return 1
}
```

### 11.4 `stack_default_app_slug` — lowercase parent basename

```bash
stack_default_app_slug() {
  basename "$1" | tr '[:upper:]' '[:lower:]'
}
```

### 11.5 `gh repo view` preferred in `setup-project` skill (architect bash)

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

---

*Document produced from Cursor chat `e4851f6f-4658-4c8b-bb24-e76b4db7c7b5` (created **2026-05-19**). Filename `2026-05-19-spec-central-stack-workflow-implementation.md` sorts with other reviews from that chat day.*
## 12. Operator cheat sheet

| Goal | Where | Action |
| --- | --- | --- |
| Bootstrap / refresh stack wiring | `APP/` parent | `GH_ORG=owner ~/.config/opencode/bin/setup-project` |
| Check wiring only | `APP/` parent | `setup-project --check-only /path/to/APP` |
| Fill registry roles | `APP-spec` + architect | Run **`setup-project`** skill |
| New feature (issue-backed) | spec → impl | PRD → fanout → impl **issue-expand** → orchestrate backlog |
| Close feature cross-repo | `APP-spec` + architect | **`feature-complete`** |
| Legacy single-repo feature | impl + architect option B | grill-me → `.plan` → orchestrate file picker |

---

## 13. Follow-up checklist

- [ ] Confirm all paths in §6 exist on disk in your `~/.config/opencode` checkout (restore from git if missing)
- [ ] Complete architect **`setup-project`** in `blocshed-spec`; re-run `--check-only` until registry complete
- [ ] New architect session after permission changes if `git remote` still prompts
- [ ] Commit/push OpenCode config when satisfied
- [ ] If `link-spec-repo` was mistakenly run inside spec earlier, verify spec repo has no impl-only artifacts

---

## 14. Related TO REVIEW docs (same folder, date sort)

Later sessions extended or fixed overlapping areas — read together:

| File | Relationship |
| --- | --- |
| `2026-06-01-setup-project-shell-bootstrap.md` | Re-run UX, gh stdout, `NEXT:` messaging, end-of-run commit |
| `2026-06-01-setup-project-workflow-and-deepseek-bash-fixes.md` | Architect fizzling, `INCOMPLETE` vs `OK`, bash `2>&1` deny fix |
| `2026-06-01-feature-pipeline-and-architect-front-door.md` | PRD parser, registry YAML, architect menus, blocshed gates |
| `2026-06-01-spec-repo-markdown-parser.md` | `SPEC_REPO` parsing in impl `issue-tracker.md` |
| `2026-05-20-setup-project-empty-targets-fix.md` | Empty `TARGETS` / spec-only bootstrap |
| `2026-05-20-setup-project-cross-stack-scope.md` | Parent-folder scoping |
| `2026-05-19-issue-backed-workflow-orchestrate-handoff.md` | Why orchestrate handoff after issue-expand |

---

---

*Document produced from Cursor chat `e4851f6f-4658-4c8b-bb24-e76b4db7c7b5` (created **2026-05-19**). Filename `2026-05-19-spec-central-stack-workflow-implementation.md` sorts with other reviews from that chat day.*
