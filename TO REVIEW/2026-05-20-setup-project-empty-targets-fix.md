# 2026-05-20 — setup-project empty TARGETS fix

**Cursor chat created:** 2026-05-20  
**Chat transcript ID:** `fc73e91c-16a7-40fa-9045-108b66f86aa6`  
**Work completed:** 2026-05-20 (same session — fix and verification in one chat)

**Session scope:** Fix `setup-project` / `create_or_sync_spec.sh` crash when no implementation repos exist under the project parent directory (`TARGETS` array empty + Bash nounset).

**Status:** Implemented and finalized in chat. Verify on disk before merge — workspace may have diverged since this session.

---

## Executive summary

| Item | Detail |
| --- | --- |
| **Trigger** | `setup-project` for new app `offthechain` with zero sibling impl git repos |
| **Symptom** | `TARGETS[@]: unbound variable` at `create_or_sync_spec.sh` line ~130 while writing `docs/agents/repos.md` |
| **Root cause** | `set +u` was placed *before* `source common.sh`; `common.sh` re-enables `set -u`, so empty-array expansion fails |
| **Fix 1** | Move `set +u` to **after** `source common.sh` in `create_or_sync_spec.sh` |
| **Fix 2** | Guard impl-linking loop in `setup-project` with `${#TARGETS[@]} -gt 0` |
| **Files touched** | 2 — no changes to `common.sh`, templates, or discovery logic |

---

## Problem reported (verbatim)

User ran stack bootstrap for a greenfield project parent with no implementation repos yet:

```text
setup-project
==> Project parent: /Users/robo/05_Repos/01_PROJECTS/apps/offthechain
==> App slug: offthechain (from parent folder / spec dir; override with --app)
==> Spec repo: roborew/offthechain-spec
WARN: no implementation repos discovered under /Users/robo/05_Repos/01_PROJECTS/apps/offthechain
==> Creating roborew/offthechain-spec...
==> Copying scaffold from templates/spec-repo ...
/Users/robo/.config/opencode/bin/stack/create_or_sync_spec.sh: line 130: TARGETS[@]: unbound variable
```

Script aborted after GitHub repo creation and scaffold copy, before committing the empty registry.

---

## Architecture / call flow

```text
setup-project
  │
  ├─ stack_discover_targets(PARENT, SPEC_NAME) → empty list
  ├─ TARGETS=()  (no impl repos under parent)
  │
  └─ create_or_sync_spec.sh PARENT APP ORG   # no extra target args
        │
        ├─ TARGETS=("$@")  → still empty after discovery fallback
        ├─ gh repo create + cp templates/spec-repo
        │
        └─ write docs/agents/repos.md
              for target in "${TARGETS[@]}"   ← FAILS under set -u when empty
```

**Why empty TARGETS is valid:** A new project may have only the spec repo (or nothing yet). Bootstrap should succeed with an empty `repos:` registry; user adds impl repos later and re-runs `setup-project`.

---

## Root cause (detailed)

### Bash nounset + empty arrays

With `set -u` (nounset), expanding an empty array is an error:

```bash
set -u
TARGETS=()
for t in "${TARGETS[@]}"; do echo "$t"; done
# bash: TARGETS[@]: unbound variable
```

Reproduced in session — exit 127.

### Why `set -u` was active at the failing loop

`bin/stack/create_or_sync_spec.sh` originally had:

```bash
set -euo pipefail
set +u          # ← disabled nounset here
...
source "$(dirname "$0")/common.sh"   # ← common.sh runs set -euo pipefail again
# nounset is ON again; no set +u after source
...
for target in "${TARGETS[@]}"; do    # ← crash when TARGETS empty
```

`bin/stack/common.sh` line 3 (unchanged — **do not remove**):

```bash
set -euo pipefail
```

Any script that sources `common.sh` must assume nounset is re-enabled unless it explicitly runs `set +u` afterward.

### Secondary failure site

`bin/setup-project` also uses `set -euo pipefail` and had:

```bash
for target in "${TARGETS[@]}"; do   # impl linking — same crash if TARGETS empty
```

Fixing only `create_or_sync_spec.sh` would leave `setup-project` broken on the next step.

---

## Changes implemented — recreation guide for another AI

Apply **exactly two edits** in **two files**. No new files. No changes to `common.sh`.

---

### Edit 1 — `bin/stack/create_or_sync_spec.sh`

#### 1a. Remove early `set +u` (top of file)

**BEFORE:**

```bash
#!/usr/bin/env bash
# Create or sync spec repo under a project parent directory.
# Usage: create_or_sync_spec.sh [--keep-branch] <parent-dir> <app-slug> <org> [target ...]
# Stdout: single line — absolute path to spec repo. All logs go to stderr.
# Env: SPEC_PRIMARY_BRANCH, SPEC_DEVELOP_BRANCH
set -euo pipefail
set +u
KEEP_BRANCH=false
```

**AFTER:**

```bash
#!/usr/bin/env bash
# Create or sync spec repo under a project parent directory.
# Usage: create_or_sync_spec.sh [--keep-branch] <parent-dir> <app-slug> <org> [target ...]
# Stdout: single line — absolute path to spec repo. All logs go to stderr.
# Env: SPEC_PRIMARY_BRANCH, SPEC_DEVELOP_BRANCH
set -euo pipefail
KEEP_BRANCH=false
```

#### 1b. Add `set +u` immediately after sourcing `common.sh`

**BEFORE:**

```bash
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=common.sh
source "$(dirname "$0")/common.sh"

PRIMARY_BRANCH="${SPEC_PRIMARY_BRANCH:-main}"
DEVELOP_BRANCH="${SPEC_DEVELOP_BRANCH:-develop}"
```

**AFTER:**

```bash
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=common.sh
source "$(dirname "$0")/common.sh"
set +u # common.sh enables nounset; TARGETS may be empty when no impl repos exist

PRIMARY_BRANCH="${SPEC_PRIMARY_BRANCH:-main}"
DEVELOP_BRANCH="${SPEC_DEVELOP_BRANCH:-develop}"
```

#### 1c. Context — code that must NOT change (but must now succeed)

TARGETS discovery (already correct; leave as-is):

```bash
shift 3
TARGETS=("$@")

# ... later ...

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
```

Failing block (loop unchanged — fix is nounset placement, not loop rewrite):

```bash
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
```

**Expected output file when TARGETS is empty:**

```yaml
# Generated by setup-project.
# Routing configuration; rerunning replaces the repo list below.
repos:
```

---

### Edit 2 — `bin/setup-project`

#### 2a. Guard impl-linking section when TARGETS is empty

**BEFORE:**

```bash
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
```

**AFTER:**

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

#### 2b. Context — already-correct guard (do not duplicate; leave as-is)

Passing targets into `create_or_sync_spec.sh` was already safe:

```bash
CREATE_ARGS=()
[[ "$KEEP_BRANCH" == "true" ]] && CREATE_ARGS+=(--keep-branch)
SYNC_SPEC_ARGS=("$PARENT" "$APP" "$ORG")
[[ ${#TARGETS[@]} -gt 0 ]] && SYNC_SPEC_ARGS+=("${TARGETS[@]}")
if [[ ${#CREATE_ARGS[@]} -gt 0 ]]; then
  SPEC_PATH="$("${STACK}/create_or_sync_spec.sh" "${CREATE_ARGS[@]}" "${SYNC_SPEC_ARGS[@]}")"
else
  SPEC_PATH="$("${STACK}/create_or_sync_spec.sh" "${SYNC_SPEC_ARGS[@]}")"
fi
```

TARGETS population in `setup-project` (unchanged):

```bash
TARGETS=()
while IFS= read -r t; do
  [[ -z "$t" ]] && continue
  TARGETS+=("$t")
done < <(stack_discover_targets "$PARENT" "$SPEC_NAME")
```

---

## Unified diff (reference)

```diff
--- a/bin/stack/create_or_sync_spec.sh
+++ b/bin/stack/create_or_sync_spec.sh
@@ -4,7 +4,6 @@
 # Env: SPEC_PRIMARY_BRANCH, SPEC_DEVELOP_BRANCH
 set -euo pipefail
-set +u
 KEEP_BRANCH=false
 if [[ "${1:-}" == "--keep-branch" ]]; then
   KEEP_BRANCH=true
@@ -18,6 +17,7 @@
 ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
 # shellcheck source=common.sh
 source "$(dirname "$0")/common.sh"
+set +u # common.sh enables nounset; TARGETS may be empty when no impl repos exist
 
 PRIMARY_BRANCH="${SPEC_PRIMARY_BRANCH:-main}"
 DEVELOP_BRANCH="${SPEC_DEVELOP_BRANCH:-develop}"

--- a/bin/setup-project
+++ b/bin/setup-project
@@ -161,7 +161,7 @@
 SYNC_CODE=0
 "${STACK}/sync_spec_tooling.sh" "$SPEC_PATH" || SYNC_CODE=$?
 
-if [[ "$SPEC_ONLY" != "true" ]]; then
+if [[ "$SPEC_ONLY" != "true" && ${#TARGETS[@]} -gt 0 ]]; then
   echo ""
   echo "==> Linking implementation repos..."
   LINK="${STACK}/link_impl_repo.sh"
```

---

## Alternative fixes considered (not chosen)

| Approach | Why not used |
| --- | --- |
| Remove `set -u` from `common.sh` | Breaks contract for all stack scripts that rely on nounset after source |
| Rewrite loop as `if (( ${#TARGETS[@]} )); then for ... fi` | Works but duplicates guard; `set +u` after source fixes all empty-array sites in this script |
| Use `"${TARGETS[@]+"${TARGETS[@]}"}"` | Valid Bash idiom but less readable than `set +u` for a script with multiple optional arrays |
| Default `TARGETS=(placeholder)` | Wrong semantics — would write fake registry entries |

---

## Expected behaviour after fix

### Empty parent (no impl repos)

1. `WARN: no implementation repos discovered under <parent>` (stderr — unchanged)
2. Spec repo created/cloned on GitHub
3. Scaffold copied from `templates/spec-repo`
4. `docs/agents/repos.md` committed with empty `repos:`
5. `sync_spec_tooling.sh` runs
6. **No** “Linking implementation repos…” section
7. Exit 0; stdout ends with absolute spec path

### After adding impl repo(s)

1. Re-run `setup-project` from same parent
2. `TARGETS` populated via `stack_discover_targets`
3. Registry updated in `docs/agents/repos.md`
4. Impl linking runs for each discovered repo

---

## Validation performed in chat

### Unit repro — empty array after source + set +u

```bash
bash -c '
set -euo pipefail
source /Users/robo/.config/opencode/bin/stack/common.sh
set +u
TARGETS=()
{
  echo "repos:"
  for target in "${TARGETS[@]}"; do
    echo "  - name: ${target}"
  done
}
echo OK
'
```

**Result:** exit 0, prints `repos:` then `OK`.

### Syntax check

```bash
bash -n /Users/robo/.config/opencode/bin/stack/create_or_sync_spec.sh
```

### Not run in session

Full end-to-end:

```bash
cd /Users/robo/05_Repos/01_PROJECTS/apps/offthechain
~/.config/opencode/bin/setup-project
```

(Requires `gh` auth, network, and project paths.)

---

## Files modified

| File | Lines changed | Summary |
| --- | --- | --- |
| [`bin/stack/create_or_sync_spec.sh`](../bin/stack/create_or_sync_spec.sh) | ~2 hunks | Remove early `set +u`; add `set +u` after `source common.sh` |
| [`bin/setup-project`](../bin/setup-project) | 1 line | Add `&& ${#TARGETS[@]} -gt 0` to impl-linking `if` |

**Not modified:**

- `bin/stack/common.sh` — still has `set -euo pipefail` at top
- `stack_discover_targets` — discovery logic unchanged
- `templates/spec-repo/**` — scaffold unchanged
- `gh repo create` / clone flow unchanged

---

## Review checklist

- [ ] `create_or_sync_spec.sh`: no `set +u` before `source common.sh`
- [ ] `create_or_sync_spec.sh`: `set +u` immediately after `source common.sh` with comment
- [ ] `setup-project`: impl linking guarded with `${#TARGETS[@]} -gt 0`
- [ ] Re-run `setup-project` on empty parent — completes without `TARGETS[@]` error
- [ ] Spec repo `docs/agents/repos.md` has `repos:` with no entries when no impl repos
- [ ] Add impl repo sibling, re-run — registry and linking populate

---

## Related docs

- [`2026-05-20-setup-project-cross-stack-scope.md`](2026-05-20-setup-project-cross-stack-scope.md) — separate investigation: setup touching wrong projects (parent-dir scope); no code overlap with this fix
- [`2026-06-01-setup-project-workflow-and-deepseek-bash-fixes.md`](2026-06-01-setup-project-workflow-and-deepseek-bash-fixes.md) — operator workflow / bash permission fixes; complementary

---

## References

- Cursor chat: `fc73e91c-16a7-40fa-9045-108b66f86aa6` (created 2026-05-20)
- Entrypoint: `bin/setup-project` → `bin/stack/create_or_sync_spec.sh`
- Shared helpers: `bin/stack/common.sh`
