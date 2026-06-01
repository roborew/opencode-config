# 2026-05-20 — setup-project Cross-Stack Scope Investigation

**Cursor chat created:** 2026-05-20 ([chat transcript](edf3b0e3-b944-43a3-83d5-a786cfeb7f7f))

**Session scope:** Diagnose why running `setup-project` for a new project appeared to modify or wire unrelated projects; document root cause, call chain, operator remediation, and optional hardening for a future implementer.

**Status:** Investigation and operator guidance finalized in chat (2026-05-20). **No shell script changes were authored or committed in this chat.** This review doc was created/updated in chat. Related script fixes (empty `TARGETS` nounset) were observed as pre-existing uncommitted work at session start — documented below with diffs for cross-reference; see also [`2026-06-01-setup-project-empty-targets-fix.md`](2026-06-01-setup-project-empty-targets-fix.md).

---

## Problem reported

User message (2026-05-20):

> I am running setup in a new project and its going into all the other projects ???? WHy??/

**Observed behaviour:** Running stack bootstrap (`setup-project`) for a **new** project caused setup to run against **other projects** as well — linking impl repos, rewriting registry files, syncing tooling, and seeding GitHub labels outside the intended stack.

---

## Executive summary

| Finding | Detail |
| --- | --- |
| **Root cause** | `setup-project` scopes to a **project parent directory** (`pwd` or explicit path), then discovers **every git sibling** under it — no app-prefix filter. |
| **Typical trigger** | Running from too high a folder (e.g. `~/code/` or `~/05_Repos/01_PROJECTS/apps/`) where multiple products' clones coexist as siblings. |
| **Blast radius** | Overwrites spec `docs/agents/repos.md`, commit/push, label seed on all listed repos, `link_impl_repo.sh` on each impl target. |
| **Code changed in this chat** | None (investigation + this markdown doc only). |
| **Recommended fix (operator)** | One container folder per stack; re-run from correct parent; audit/revert collateral. |
| **Recommended fix (code, future)** | Filter `stack_discover_targets` to `${APP}-*` prefix; warn on multi-spec parents. |

---

## Call chain (end-to-end)

```text
setup-project
  ├─ Resolve PARENT (= pwd or arg), APP (= basename parent or --app), ORG (= GH_ORG)
  ├─ stack_resolve_spec_dir(PARENT, APP) → SPEC_DIR
  ├─ stack_discover_targets(PARENT, SPEC_NAME) → TARGETS[]
  ├─ create_or_sync_spec.sh [--keep-branch] PARENT APP ORG [targets...]
  │     ├─ Regenerate docs/agents/repos.md from TARGETS
  │     ├─ git commit + push
  │     └─ seed_one() labels on spec + every repo in repos.md
  ├─ sync_spec_tooling.sh SPEC_DIR
  └─ For each target in TARGETS[] (if not SPEC_ONLY):
        link_impl_repo.sh IMPL_PATH SPEC_REPO
          ├─ Write docs/agents/issue-tracker.md (SPEC_REPO: line)
          └─ sync_impl_tooling.sh IMPL_PATH
```

---

## Root cause (detailed)

### 1. Parent directory selection

`bin/setup-project` defaults to the current working directory:

```bash
if [[ -z "$PARENT" ]]; then
  PARENT="$(pwd)"
fi
PARENT="$(cd "$PARENT" && pwd)"
```

Override: pass path as last positional arg, e.g. `setup-project --org OWNER ~/code/myapp`.

**Implication:** If the user runs `setup-project` from a shared parent containing multiple products' clones, **all** of them are in scope.

### 2. App slug resolution

```bash
if [[ -z "$APP" ]]; then
  APP="$(stack_default_app_slug "$PARENT")"
fi

# stack_default_app_slug — parent folder basename, lowercased
stack_default_app_slug() {
  local parent_dir="$1"
  printf '%s\n' "$(basename "$parent_dir" | tr '[:upper:]' '[:lower:]')"
}
```

If a spec repo already exists on disk, slug is taken from the spec folder name instead:

```bash
if [[ -d "${SPEC_DIR}/.git" ]]; then
  APP="$(stack_app_slug_from_spec_dir "$SPEC_DIR")"
  # blocshed-spec → blocshed
fi
```

### 3. Broad sibling discovery (the cross-stack bug)

Full function from `bin/stack/common.sh`:

```bash
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

stack_is_spec_repo() {
  local path="$1"
  [[ -d "$path/docs/prd" || -f "$path/docs/agents/repos.md" ]]
}
```

**What gets skipped as targets:** Any `*-spec` folder that looks like a spec repo (`docs/prd/` or `docs/agents/repos.md`).

**What gets included:** **Every other** directory with `.git` — regardless of app name prefix. So `blocshed-web`, `other-api`, etc. are all targets if they share the parent.

**What is NOT filtered:** `${APP}-web`, `${APP}-api` prefix matching.

### 4. Target list wired into setup-project

```bash
TARGETS=()
while IFS= read -r t; do
  [[ -z "$t" ]] && continue
  TARGETS+=("$t")
done < <(stack_discover_targets "$PARENT" "$SPEC_NAME")

SYNC_SPEC_ARGS=("$PARENT" "$APP" "$ORG")
[[ ${#TARGETS[@]} -gt 0 ]] && SYNC_SPEC_ARGS+=("${TARGETS[@]}")
SPEC_PATH="$("${STACK}/create_or_sync_spec.sh" "${SYNC_SPEC_ARGS[@]}")"
```

### 5. Registry overwrite + push + label seeding

From `bin/stack/create_or_sync_spec.sh`:

```bash
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

# ... create/clone spec repo ...

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
  git commit -m "chore: sync ${SPEC_NAME} target repos" >/dev/null 2>&1 || true
fi
git push -u origin HEAD >/dev/null 2>&1 || true

# Label seeding on spec + every repo in repos.md
if command -v yq &>/dev/null && command -v jq &>/dev/null; then
  seed_one "$SPEC_REPO" >&2
  while IFS= read -r r; do
    [[ -z "$r" ]] && continue
    seed_one "$r" >&2
  done < <(yq -r '.repos[].name' docs/agents/repos.md 2>/dev/null || true)
fi
```

**Implication:** A bad discovery list is committed, pushed, and propagated to GitHub labels on **every** listed repo.

### 6. Implementation repo linking

From `bin/setup-project`:

```bash
if [[ "$SPEC_ONLY" != "true" && ${#TARGETS[@]} -gt 0 ]]; then
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
```

From `bin/stack/link_impl_repo.sh` (what gets written to each impl repo):

```bash
cat > docs/agents/issue-tracker.md <<'EOF'
# Issue tracker
...
- **SPEC_REPO:** __SPEC_REPO__
EOF
# sed replaces __SPEC_REPO__ with owner/name-spec-repo
"${ROOT}/bin/stack/sync_impl_tooling.sh" "$IMPL_DIR"
```

**Implication:** Unrelated impl repos get repointed to the new spec's `SPEC_REPO` and receive a full tooling sync.

### 7. Spec repo resolution edge case

If `{parent}/{app}-spec` does not exist, `stack_resolve_spec_dir` scans for **any** `*-spec` that passes `stack_is_spec_repo`:

```bash
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
```

With multiple `*-spec` repos under one parent, the **first matching** spec on disk may be used — another source of cross-stack confusion when parent is too broad.

---

## Intended layout (documented design)

From `bin/setup-project` header and `README.md`:

```text
~/code/myapp/              ← run setup-project FROM HERE (container only, no .git)
  myapp-spec/
  myapp-web/
  myapp-api/
```

```bash
# Documented usage
cd ~/code/APP
export GH_ORG=OWNER
setup-project
# or: ~/.config/opencode/bin/setup-project --org OWNER ~/code/APP
```

---

## Failure modes (with examples)

### Mode A — flat layout under shared parent

```text
/Users/robo/05_Repos/01_PROJECTS/apps/    ← user runs setup here
  newproject-spec/
  newproject-web/
  blocshed-spec/        ← skipped (spec)
  blocshed-web/         ← INCLUDED as target
  offthechain-api/      ← INCLUDED as target
```

**Result:** `newproject-spec/docs/agents/repos.md` lists `blocshed-web`, `offthechain-api`, etc.; those repos get `SPEC_REPO: roborew/newproject-spec`.

### Mode B — running from `~/code/` instead of `~/code/myapp/`

Same as Mode A if all product clones are direct children of `~/code/`.

### Mode C — OpenCode architect skill amplifies bad registry

After bad shell bootstrap, `skills/setup-project/SKILL.md` Phase A reads `docs/agents/repos.md` and discovers siblings via `../`. A corrupted registry causes agent-driven fanout across the wrong repo set.

Relevant skill precondition (shell bootstrap must run from project parent):

```bash
cd ~/code/APP && setup-project
```

Check-only from spec repo:

```bash
OC="${OPENCODE_CONFIG_DIR:-${OPENCODE_CONFIG:-$HOME/.config/opencode}}"
"$OC/bin/setup-project" --check-only "$(dirname "$PWD")"
```

---

## Git diff observed at session start (NOT authored in this chat)

At the beginning of this chat, `git status` showed uncommitted changes to two files. These address a **different** failure (empty `TARGETS` nounset when no impl repos exist) but were present alongside the cross-stack investigation. Full diff as captured in chat:

```diff
diff --git a/bin/setup-project b/bin/setup-project
--- a/bin/setup-project
+++ b/bin/setup-project
@@ -161,7 +161,7 @@ echo "==> Spec at: ${SPEC_PATH} (branch: $(git -C "$SPEC_PATH" branch --show-cur
 SYNC_CODE=0
 "${STACK}/sync_spec_tooling.sh" "$SPEC_PATH" || SYNC_CODE=$?
 
-if [[ "$SPEC_ONLY" != "true" ]]; then
+if [[ "$SPEC_ONLY" != "true" && ${#TARGETS[@]} -gt 0 ]]; then
   echo ""
   echo "==> Linking implementation repos..."
   LINK="${STACK}/link_impl_repo.sh"

diff --git a/bin/stack/create_or_sync_spec.sh b/bin/stack/create_or_sync_spec.sh
--- a/bin/stack/create_or_sync_spec.sh
+++ b/bin/stack/create_or_sync_spec.sh
@@ -18,6 +18,7 @@ TARGETS=("$@")
 ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
 # shellcheck source=common.sh
 source "$(dirname "$0")/common.sh"
+set +u # common.sh enables nounset; TARGETS may be empty when no impl repos exist
```

**To recreate those fixes** (separate from cross-stack scope):

1. In `create_or_sync_spec.sh`, place `set +u` **immediately after** `source common.sh` (not before it — `common.sh` re-enables nounset).
2. In `setup-project`, guard the impl-linking block with `${#TARGETS[@]} -gt 0`.

See [`2026-06-01-setup-project-empty-targets-fix.md`](2026-06-01-setup-project-empty-targets-fix.md) for full context, validation command, and expected behaviour.

---

## Proposed hardening (NOT implemented — for a future AI implementer)

To prevent cross-stack bleed even when users run from a shared parent, replace `stack_discover_targets` with app-prefix filtering:

```bash
# PROPOSED — add to bin/stack/common.sh (not on disk as of this review)
stack_discover_targets() {
  local parent_dir="$1"
  local spec_name="$2"
  local app_prefix="$3"   # NEW: e.g. "myapp" from APP slug
  local dir lower name_lower prefix_lower
  prefix_lower="$(printf '%s' "$app_prefix" | tr '[:upper:]' '[:lower:]')"
  for dir in "${parent_dir}"/*/; do
    dir="${dir%/}"
    dir="$(basename "$dir")"
    [[ "$dir" == .* ]] && continue
    [[ -d "${parent_dir}/${dir}/.git" ]] || continue
    stack_dir_is_spec_repo "$parent_dir" "$dir" "$spec_name" && continue
    name_lower="$(printf '%s' "$dir" | tr '[:upper:]' '[:lower:]')"
    [[ "$name_lower" == "${prefix_lower}-"* ]] || continue
    printf '%s\n' "$dir"
  done
}
```

Update call sites to pass `$APP`:

```bash
# bin/setup-project
done < <(stack_discover_targets "$PARENT" "$SPEC_NAME" "$APP")

# bin/stack/create_or_sync_spec.sh
done < <(stack_discover_targets "$PARENT_DIR" "${APP}-spec" "$APP")

# bin/stack/check_impl_wiring.sh
done < <(stack_discover_targets "$PARENT_DIR" "$SPEC_NAME" "$APP")
```

Optional guard in `setup-project` after discovery:

```bash
# PROPOSED — warn when parent contains git dirs that don't match APP-*
for dir in "${PARENT}"/*/; do
  [[ -d "${dir}/.git" ]] || continue
  base="$(basename "${dir%/}")"
  stack_dir_is_spec_repo "$PARENT" "$base" "${APP}-spec" && continue
  lower="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
  [[ "$lower" == "${APP}-"* ]] && continue
  echo "WARN: ignoring ${base} (does not match app prefix ${APP}-)" >&2
done
```

Optional fail-fast when multiple spec repos share a parent:

```bash
# PROPOSED
spec_count=0
for d in "${PARENT}"/*; do
  [[ -d "$d/.git" ]] || continue
  base="$(basename "$d")"
  stack_dir_is_spec_repo "$PARENT" "$base" "${APP}-spec" || continue
  spec_count=$((spec_count + 1))
done
if [[ "$spec_count" -gt 1 ]]; then
  echo "ERROR: multiple spec repos under ${PARENT}; use a dedicated container folder per stack." >&2
  exit 1
fi
```

---

## Operator guidance (finalized in chat)

### Diagnose before re-running

```bash
cd /path/to/project-parent
pwd
ls -d */
export GH_ORG=your-org
setup-project --check-only "$(pwd)"
```

If output lists repos from other products (`OK: blocshed-web` when bootstrapping `myapp`), the parent path is wrong.

### Correct layout and bootstrap

```bash
mkdir -p ~/code/myapp && cd ~/code/myapp
gh repo clone "$GH_ORG/myapp-spec"
gh repo clone "$GH_ORG/myapp-web"
export GH_ORG=OWNER
setup-project
```

### Remediation after a bad run

| Artifact | What to check | Action |
| --- | --- | --- |
| `*/docs/agents/issue-tracker.md` in unrelated impl repos | `SPEC_REPO:` points at wrong spec | Revert commit or fix line |
| `*-spec/docs/agents/repos.md` | Stray `repos:` entries | Revert `chore: sync * target repos` commit |
| GitHub labels | Unexpected labels on wrong repos | Manual cleanup if needed |
| Local clones | Repos under wrong parent | Move into per-project container folders |

---

## What was actioned in this chat (2026-05-20)

| Action | Status |
| --- | --- |
| Root-cause investigation of cross-stack scope | Done |
| Operator remediation guidance | Done |
| Optional hardening spec for future implementer | Documented (not coded) |
| Create/update TO REVIEW markdown | Done (this file) |
| Modify `bin/setup-project` / `common.sh` for prefix filter | **Not done** |
| Commit script changes | **Not done** |
| Revert user's project repos | **Not done** (paths not provided) |

---

## What was NOT done in this chat

| Item | Status |
| --- | --- |
| Add `${APP}-*` prefix filter to `stack_discover_targets` | Suggested only |
| Warn when multiple `*-spec` repos exist under one parent | Suggested only |
| Revert collateral changes in user's project repos | Not performed |
| End-to-end re-run of `setup-project` on user's machine | Not performed |

---

## Review checklist

- [ ] Rename/confirm this file is `2026-05-20-setup-project-cross-stack-scope.md` (matches chat creation date)
- [ ] Confirm project layout uses one container folder per stack
- [ ] Run `setup-project --check-only` from intended parent; verify target list
- [ ] Audit impl repos touched incorrectly (`issue-tracker.md`, synced `bin/*`)
- [ ] Audit spec `docs/agents/repos.md` for stray entries; revert if needed
- [ ] Decide whether to implement app-prefix filtering (see Proposed hardening section)
- [ ] Confirm empty-`TARGETS` fixes are merged (see related doc)
- [ ] Re-run shell bootstrap from correct parent; then architect **setup-project** skill in spec if needed

---

## References

| Resource | Path |
| --- | --- |
| Stack bootstrap entry | `bin/setup-project` |
| Discovery helpers | `bin/stack/common.sh` |
| Registry + label seed | `bin/stack/create_or_sync_spec.sh` |
| Impl wiring | `bin/stack/link_impl_repo.sh` |
| Check-only wiring | `bin/stack/check_impl_wiring.sh` |
| Agent phase | `skills/setup-project/SKILL.md` |
| Related fix (empty TARGETS) | `TO REVIEW/2026-06-01-setup-project-empty-targets-fix.md` |
| Cursor chat transcript | `edf3b0e3-b944-43a3-83d5-a786cfeb7f7f` |
