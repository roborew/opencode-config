# 2026-06-01 — `setup-project` Shell Bootstrap: Fixes, UX, and Re-run Behavior

**Cursor chat created:** 2026-06-01 15:36 (local filesystem birth time of transcript)  
**Cursor chat ID:** `99386ce0-cceb-494a-9323-3f83ae12676d`  
**Filename date (`2026-06-01`):** Same as chat creation date (ISO `YYYY-MM-DD` for sort order in `TO REVIEW/`).  
**Last transcript activity:** 2026-06-01 ~19:21 (implementation + TO REVIEW doc edits in same thread).

**Session scope:** README `GH_ORG` / generic layout; fix `gh` stdout breaking spec path capture; operator UX (labels, `NEXT:` messaging, completion banner); re-run idempotency (no dirty-tree hard stop, auto keep-branch, end-of-run commit).

**Status:** Finalized in chat. **Verify on disk before merge** — `README.md` may have been shortened later; `bin/setup-project` and stack scripts may need re-application from snippets below.

---

## How to use this doc (another AI / re-implementer)

1. Apply changes in **Apply order** (bottom) — dependencies matter (`create_or_sync_spec.sh` before relying on path capture in `setup-project`).
2. Match **exact** `old_string` blocks when using search-replace; if the repo drifted, use the **Final file excerpts** as source of truth.
3. Run tests: `python3 bin/lib/test_migrate_repos_registry.py` and `bash -n` on edited shell scripts.
4. Smoke test: `cd <project-parent> && GH_ORG=<org> setup-project` twice — second run must not error on uncommitted spec changes.

---

## Problem statement

| # | Issue | User-visible symptom |
|---|--------|----------------------|
| 1 | README used `GH_ORG=OWNER` without explanation; **blocshed** as only app example | Confusion about owner vs slug |
| 2 | `gh repo create --clone` prints repo URL on **stdout** | `ERROR: invalid spec path (internal bug). Got: https://github.com/...` + path |
| 3 | `gh label create` verbose; `INCOMPLETE:` after successful link | Felt like failure |
| 4 | `print_next_steps` + exit code 3 | “registry or PRDs need OpenCode…” after linking worked |
| 5 | `create_or_sync_spec.sh` required clean git tree before branch checkout | Re-run: `ERROR: Spec repo has uncommitted changes` |

**Target behavior:** `setup-project` is **idempotent** from project parent — confirm/sync repos, print next steps; OpenCode registry interview remains a separate step (`exit 3` / `NEXT:` is normal).

---

## Files touched

| File | Change summary |
|------|----------------|
| `README.md` | `GH_ORG`, `APP`/`myapp` layout, re-run note (may no longer be in root README if docs moved) |
| `bin/setup-project` | Path parse, auto `--keep-branch`, link quiet, commit, stack list, exit 0 on sync code 3 |
| `bin/stack/create_or_sync_spec.sh` | `gh` `1>&2`, dirty-tree policy, labels quiet, push messaging |
| `bin/stack/print_next_steps.sh` | Exit 3/6 banners, `LINKED` arg |
| `bin/stack/sync_impl_tooling.sh` | `OPENCODE_SETUP_QUIET` |
| `bin/lib/migrate_repos_registry.py` | `NEXT:` on bootstrap migrate |
| `bin/lib/test_migrate_repos_registry.py` | Expect `NEXT:` |

---

## 1. README.md (setup section — may need restoring elsewhere)

If the root `README.md` no longer has a Setup section, add equivalent content to `docs/RUNBOOK.md` or restore these blocks.

### 1.1 Project layout (replace blocshed)

```markdown
2. **Project layout** — The parent folder `~/code/APP/` is a **container only** (no git root there). Siblings are typically lowercase: **`APP-spec`**, **`APP-web`**, **`APP-api`** (replace `APP` with your product slug, e.g. `myapp`). The parent folder name becomes the app slug (lowercased): `myapp`. GitHub remotes may use different casing (`your-org/MyApp-spec`); setup reads **git remote** from each clone. There is **no** `bin/setup-project` inside the project folder.
```

### 1.2 Shell bootstrap + `GH_ORG`

Markdown block to add under Setup:

    4. **Shell bootstrap (once per stack, new or existing)** — run from `~/code/APP` (the parent folder, not inside `APP-spec`):

    **`GH_ORG`** is the GitHub **owner** (user login or organization name) — the `owner` in `owner/repo`. It is not the app slug and not the local folder name. Set it once per shell (or add to `~/.zshrc`):

Shell examples to include in that section:

```bash
export GH_ORG=your-github-login-or-org
# or discover your user login:
# export GH_ORG="$(gh api user -q .login)"
```

Then note: pass `--org your-github-login-or-org` to `setup-project` instead of exporting `GH_ORG`.

```bash
mkdir -p ~/code/myapp && cd ~/code/myapp
gh repo clone "$GH_ORG/myapp-web"   # GitHub repo names; local folders match clone dir names
gh repo clone "$GH_ORG/myapp-api"
gh repo clone "$GH_ORG/myapp-spec"   # if the spec repo already exists
setup-project
# Stay on your current spec branch (e.g. feature work):
# setup-project --keep-branch
```

### 1.3 Re-runs vs branches

```markdown
**Re-runs:** Safe to run `setup-project` again from the project parent — it refreshes tooling, re-links implementation repos, and prints next steps. An existing local spec repo stays on its current branch (no forced checkout).

**Branches (first-time spec only):** On a **new** spec repo, `setup-project` may check out `develop` or `main` for the initial scaffold. Implementation repos are never branch-switched.
```

---

## 2. `bin/stack/create_or_sync_spec.sh`

### 2.1 Redirect `gh` stdout (clone + create)

**Find:**

```bash
  (cd "$PARENT_DIR" && gh repo clone "$SPEC_REPO" "$CLONE_NAME")
```

**Replace with:**

```bash
  # gh prints repo URL to stdout; keep stdout for the final path line only.
  (cd "$PARENT_DIR" && gh repo clone "$SPEC_REPO" "$CLONE_NAME" 1>&2)
```

**Find:**

```bash
  (cd "$PARENT_DIR" && gh repo create "$SPEC_REPO" --private \
    --description "Spec repo: PRDs + parent issues for ${APP}" --clone)
```

**Replace with:**

```bash
  (cd "$PARENT_DIR" && gh repo create "$SPEC_REPO" --private \
    --description "Spec repo: PRDs + parent issues for ${APP}" --clone 1>&2)
```

### 2.2 Dirty tree — warn and skip branch sync (do not `exit 1`)

**Replace block** starting with:

```bash
if [[ "$CREATED_SPEC" != "true" && "$KEEP_BRANCH" != "true" ]]; then
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "ERROR: Spec repo has uncommitted changes. Commit, stash, or re-run with --keep-branch." >&2
    echo "       Path: ${SPEC_DIR}  branch: $(git branch --show-current 2>/dev/null || echo unknown)" >&2
    exit 1
  fi
  git fetch origin >/dev/null 2>&1 || true
```

**With:**

```bash
SKIP_BRANCH_SYNC=false
if [[ "$CREATED_SPEC" != "true" && "$KEEP_BRANCH" != "true" ]]; then
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "==> Spec repo has local changes; staying on $(git branch --show-current 2>/dev/null || echo unknown)" >&2
    SKIP_BRANCH_SYNC=true
  fi
fi

if [[ "$CREATED_SPEC" != "true" && "$KEEP_BRANCH" != "true" && "$SKIP_BRANCH_SYNC" != "true" ]]; then
  git fetch origin >/dev/null 2>&1 || true
```

(Keep the rest of the branch-checkout logic inside this `if` unchanged, ending with `elif [[ "$KEEP_BRANCH" == "true" ]]; then` …)

### 2.3 Push messaging for new spec

**Replace:**

```bash
git push -u origin HEAD >/dev/null 2>&1 || true
```

**With:**

```bash
if [[ "$CREATED_SPEC" == "true" ]]; then
  if ! git push -u origin HEAD 1>&2; then
    echo "WARN: Could not push spec scaffold. When ready:" >&2
    echo "       cd ${SPEC_DIR} && git push -u origin HEAD" >&2
  fi
else
  git push -u origin HEAD >/dev/null 2>&1 || true
fi
```

### 2.4 Quiet label seeding

**Replace entire `seed_one` + label loop** with:

```bash
seed_one() {
  local repo="$1"
  [[ -f .github/labels.yml ]] || return 0
  yq -o=json '.[]' .github/labels.yml 2>/dev/null | jq -c '.' | while read -r row; do
    name=$(echo "$row" | jq -r .name)
    color=$(echo "$row" | jq -r .color)
    desc=$(echo "$row" | jq -r '.description // ""')
    gh label create "$name" --repo "$repo" --color "$color" --description "$desc" --force &>/dev/null || true
  done
}

if command -v yq &>/dev/null && command -v jq &>/dev/null; then
  LABEL_REPOS=("$SPEC_REPO")
  while IFS= read -r r; do
    [[ -z "$r" ]] && continue
    LABEL_REPOS+=("$r")
  done < <(yq -r '.repos[].name' docs/agents/repos.md 2>/dev/null || true)
  for repo in "${LABEL_REPOS[@]}"; do
    seed_one "$repo"
  done
  echo "==> Seeded canonical labels on ${#LABEL_REPOS[@]} repo(s)" >&2
fi
```

**Contract (unchanged):** Only `printf '%s\n' "$SPEC_DIR"` goes to stdout at end of script.

---

## 3. `bin/setup-project`

### 3.1 Auto `--keep-branch` when spec exists

**Before** `CREATE_ARGS=()`:

```bash
# Re-runs: never force spec branch checkout (tooling sync may leave local changes).
if [[ -d "${SPEC_DIR}/.git" ]]; then
  KEEP_BRANCH=true
fi
CREATE_ARGS=()
[[ "$KEEP_BRANCH" == "true" ]] && CREATE_ARGS+=(--keep-branch)
```

### 3.2 Parse `SPEC_PATH` from `create_or_sync_spec` capture

**Replace:**

```bash
if [[ ${#CREATE_ARGS[@]} -gt 0 ]]; then
  SPEC_PATH="$("${STACK}/create_or_sync_spec.sh" "${CREATE_ARGS[@]}" "${SYNC_SPEC_ARGS[@]}")"
else
  SPEC_PATH="$("${STACK}/create_or_sync_spec.sh" "${SYNC_SPEC_ARGS[@]}")"
fi
if [[ ! -d "$SPEC_PATH" ]]; then
  echo "ERROR: invalid spec path (internal bug). Got: ${SPEC_PATH}" >&2
  exit 1
fi
```

**With:**

```bash
SPEC_PATH_RAW=""
if [[ ${#CREATE_ARGS[@]} -gt 0 ]]; then
  SPEC_PATH_RAW="$("${STACK}/create_or_sync_spec.sh" "${CREATE_ARGS[@]}" "${SYNC_SPEC_ARGS[@]}")"
else
  SPEC_PATH_RAW="$("${STACK}/create_or_sync_spec.sh" "${SYNC_SPEC_ARGS[@]}")"
fi
SPEC_PATH=""
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" ]] && continue
  if [[ -d "$line" ]]; then
    SPEC_PATH="$line"
  fi
done <<< "$SPEC_PATH_RAW"

if [[ -z "$SPEC_PATH" || ! -d "$SPEC_PATH" ]]; then
  if [[ -d "$SPEC_DIR" ]] && stack_is_spec_repo "$SPEC_DIR"; then
    SPEC_PATH="$SPEC_DIR"
    if [[ "$SPEC_PATH_RAW" == *github.com* ]]; then
      echo "WARN: GitHub CLI wrote a repo URL to stdout; continuing with ${SPEC_PATH}" >&2
      echo "       If linking or tooling sync did not run, re-run from ${PARENT}:" >&2
      echo "         setup-project" >&2
    fi
  else
    echo "ERROR: could not resolve local spec repo path." >&2
    if [[ "$SPEC_PATH_RAW" == *github.com* ]]; then
      echo "       A spec repo may have been created on GitHub. Check ${PARENT}/$(basename "$SPEC_DIR")" >&2
      echo "       then re-run: cd ${PARENT} && setup-project" >&2
    fi
    echo "       Captured output:" >&2
    printf '         %s\n' "$SPEC_PATH_RAW" >&2
    exit 1
  fi
fi
```

### 3.3 Linking + quiet + end commit + stack list + exit policy

**Replace** from `SYNC_CODE=0` through final `exit` with:

```bash
SYNC_CODE=0
"${STACK}/sync_spec_tooling.sh" "$SPEC_PATH" || SYNC_CODE=$?

LINKED=0
if [[ "$SPEC_ONLY" != "true" && ${#TARGETS[@]} -gt 0 ]]; then
  echo ""
  echo "==> Linking implementation repos..."
  export OPENCODE_SETUP_QUIET=1
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
      LINKED=$((LINKED + 1))
    else
      echo "WARN: ${local_dir} not found under ${PARENT}" >&2
    fi
  done
  unset OPENCODE_SETUP_QUIET
fi

# Commit tooling/registry updates so the next re-run is not blocked.
if git -C "$SPEC_PATH" rev-parse --git-dir &>/dev/null; then
  git -C "$SPEC_PATH" add -A
  if ! git -C "$SPEC_PATH" diff --cached --quiet; then
    if git -C "$SPEC_PATH" commit -m "chore: sync OpenCode spec tooling from setup-project" >/dev/null 2>&1; then
      echo "==> Committed spec tooling updates ($(git -C "$SPEC_PATH" branch --show-current))" >&2
      git -C "$SPEC_PATH" push origin HEAD >/dev/null 2>&1 || \
        echo "NOTE: Push spec repo when ready: cd ${SPEC_PATH} && git push" >&2
    else
      echo "NOTE: Spec repo has local OpenCode sync files (commit when ready)" >&2
    fi
  fi
fi

if [[ ${#TARGETS[@]} -gt 0 ]]; then
  echo ""
  echo "==> Stack repos:"
  echo "    spec: ${SPEC_REPO}"
  for target in "${TARGETS[@]}"; do
    local_dir="$(stack_local_dir_for_target "$target")"
    if [[ -d "${PARENT}/${local_dir}/.git" ]]; then
      echo "    impl: ${target}  (${local_dir}/)"
    else
      echo "    impl: ${target}  (missing clone: ${local_dir}/)" >&2
    fi
  done
fi

echo ""
echo "=== LABEL_SYNC_PAT (optional) ==="
echo "  gh secret set LABEL_SYNC_PAT --repo ${SPEC_REPO}"
echo ""

"${STACK}/print_next_steps.sh" "$SPEC_PATH" "$SYNC_CODE" "$LINKED"
# Exit 3 = registry metadata still TBD in OpenCode; shell work succeeded.
if [[ "$SYNC_CODE" -eq 3 ]]; then
  exit 0
fi
exit "$SYNC_CODE"
```

---

## 4. `bin/stack/sync_impl_tooling.sh`

**Replace** the sync loop tail:

```bash
  install -m0755 "$src" "$IMPL/bin/${script}"
  strip_crlf "$IMPL/bin/${script}"
  if [[ "${OPENCODE_SETUP_QUIET:-}" != "1" ]]; then
    echo "Synced bin/${script}"
  fi
done
```

---

## 5. `bin/stack/print_next_steps.sh` (full final file)

```bash
#!/usr/bin/env bash
# Print operator next steps after setup-project.
# Usage: print_next_steps.sh <spec-repo-path> <sync-exit-code> [linked-impl-count]
set -euo pipefail
SPEC="${1:?spec repo path}"
CHECK_CODE="${2:-0}"
LINKED="${3:-0}"
OC="$(cd "$(dirname "$0")/../.." && pwd)"
SPEC="$(cd "$SPEC" && pwd)"
PARENT="$(dirname "$SPEC")"

echo ""
echo "========================================"
if [[ "$CHECK_CODE" -eq 6 ]]; then
  echo "Shell bootstrap finished with PRD validation errors."
  echo ""
  echo "  Fix ticket/registry issues in the spec repo, then re-run:"
  echo "  \"$OC/bin/setup-project\" --check-only \"$PARENT\""
  exit 0
fi

if [[ "$CHECK_CODE" -eq 3 ]]; then
  echo "Shell bootstrap complete."
  if [[ "$LINKED" -gt 0 ]]; then
    echo ""
    echo "  Done: spec tooling synced; ${LINKED} implementation repo(s) linked."
  else
    echo ""
    echo "  Done: spec tooling synced."
  fi
  echo "  Next (OpenCode): architect → setup-project — fill application_role and"
  echo "  capabilities in docs/agents/repos.md (normal on first run)."
  echo ""
  echo "  cd \"$SPEC\" && opencode"
  echo ""
  echo "  Re-check shell wiring anytime:"
  echo "  \"$OC/bin/setup-project\" --check-only \"$PARENT\""
  exit 0
fi

echo "Stack bootstrap complete."
if [[ "$LINKED" -gt 0 ]]; then
  echo ""
  echo "  Linked ${LINKED} implementation repo(s); registry and tooling are ready."
fi

echo ""
echo "Next:"
echo "  cd \"$SPEC\" && opencode"
echo "  # In architect:"
echo "  #   Run setup-project"
echo ""
echo "Validate anytime (from project parent ${PARENT}):"
echo "  \"$OC/bin/setup-project\" --check-only \"${PARENT}\""
echo "  # Or if OpenCode bin/ is on PATH:"
echo "  setup-project --check-only \"${PARENT}\""
echo ""
echo "Pipeline: docs/FEATURE-PIPELINE.md"
echo "  grill-me → to-prd → bin/fanout → issue-expand → orchestrate → feature-complete"
echo "  PRD edits: bin/feature-upgrade <slug> (spec) or feature-upgrade <slug> (project parent)"
```

---

## 6. `bin/lib/migrate_repos_registry.py`

### 6.1 Bootstrap migrate message (non-check-only only)

**Replace:**

```python
    incomplete = [r["repo"] for r in normalized if not is_complete(r)]
    if incomplete:
        print("INCOMPLETE: " + ", ".join(incomplete))
        sys.exit(3)
```

**With:**

```python
    incomplete = [r["repo"] for r in normalized if not is_complete(r)]
    if incomplete:
        joined = ", ".join(incomplete)
        print(
            "NEXT: In OpenCode (architect → setup-project), fill application_role "
            f"and capabilities for: {joined}"
        )
        sys.exit(3)
```

**Leave `--check-only` path unchanged** — still prints `INCOMPLETE:` for strict validation.

### 6.2 `is_complete()` (reference — do not change unless broken)

```python
def is_complete(entry: dict) -> bool:
    role = str(entry.get("application_role") or "")
    caps = entry.get("capabilities") or []
    if not entry.get("repo"):
        return False
    if "TBD" in role or not role.strip():
        return False
    if not caps or any("TBD" in str(c) for c in caps):
        return False
    return True
```

---

## 7. `bin/lib/test_migrate_repos_registry.py`

In `test_incomplete_does_not_rewrite`:

```python
        self.assertIn("NEXT:", output)
        self.assertEqual(code, 3)
```

(was `self.assertIn("INCOMPLETE", output)`.)

---

## Exit codes and messaging (reference)

| Source | Code | Meaning | Operator message |
|--------|------|---------|------------------|
| `sync_spec_tooling.sh` | 0 | Registry + PRDs OK | “Stack bootstrap complete” path |
| `sync_spec_tooling.sh` | 3 | Registry TBD | `NEXT:` + `print_next_steps` “Shell bootstrap complete” |
| `sync_spec_tooling.sh` | 6 | PRD ticket errors | PRD validation banner |
| `setup-project` (shell) | 0 | Includes sync code 3 | Shell work OK; OpenCode step pending |
| `setup-project --check-only` | 3 | Incomplete registry | `INCOMPLETE:` (strict) |

---

## Real-world validation (fidget stack)

```bash
export GH_ORG=roborew
cd /Users/robo/05_Repos/01_PROJECTS/apps/fidget
setup-project
# Second run must succeed without "uncommitted changes" error
setup-project
setup-project --check-only .
```

Expected after first shell bootstrap:

- `Linked fidget-web → SPEC_REPO=roborew/fidget-spec` (and ingest)
- `NEXT: … fill application_role and capabilities for: roborew/fidget-ingest, roborew/fidget-web`
- Closing banner: **Shell bootstrap complete** + OpenCode next step

---

## Apply order (re-implementation)

1. `bin/stack/create_or_sync_spec.sh` — `gh` redirect, dirty-tree, push, labels  
2. `bin/lib/migrate_repos_registry.py` + `test_migrate_repos_registry.py`  
3. `bin/stack/sync_impl_tooling.sh`  
4. `bin/stack/print_next_steps.sh` (full file)  
5. `bin/setup-project` — keep-branch, path parse, tail (link/quiet/commit/list/exit)  
6. `README.md` (or RUNBOOK) — docs sections  
7. Test + smoke run  

---

## Out of scope (this chat)

- `skills/setup-project/SKILL.md` OpenCode interview (architect session)
- `check_impl_wiring.sh` impl `INCOMPLETE:` strings
- Git commits to opencode config repo (user-driven)

---

## Related TO REVIEW (same chat creation date)

| Doc | Relationship |
|-----|----------------|
| [`2026-06-01-setup-project-workflow-and-deepseek-bash-fixes.md`](2026-06-01-setup-project-workflow-and-deepseek-bash-fixes.md) | Same day — fidget/orchestrate/DeepSeek/bash permission follow-on |
| [`2026-06-01-model-routing-configuration.md`](2026-06-01-model-routing-configuration.md) | Same day — separate session |
| [`2026-06-01-new-project-initialization-setup-guide.md`](2026-06-01-new-project-initialization-setup-guide.md) | Links to this doc for shell bootstrap |

---

## Transcript source

All edits above were applied in Cursor chat `99386ce0-cceb-494a-9323-3f83ae12676d` (transcript path: `.cursor/projects/Users-robo-config-opencode/agent-transcripts/99386ce0-cceb-494a-9323-3f83ae12676d/99386ce0-cceb-494a-9323-3f83ae12676d.jsonl`).
