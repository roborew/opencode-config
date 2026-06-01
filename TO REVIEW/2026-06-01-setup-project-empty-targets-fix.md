# 2026-06-01 — setup-project empty TARGETS fix

**Session scope:** Fix `setup-project` failure when no implementation repos exist under the project parent directory.

**Status:** Finalized in chat (2026-06-01). Verify on disk before merge — workspace may have diverged since this session.

---

## Objective

Allow `setup-project` to complete successfully when bootstrapping a spec repo for a project that has **no linked implementation repos yet** (empty `TARGETS` array).

---

## Problem reported

Running `setup-project` for the **offthechain** project failed during spec repo creation:

```text
==> Project parent: /Users/robo/05_Repos/01_PROJECTS/apps/offthechain
==> App slug: offthechain (from parent folder / spec dir; override with --app)
==> Spec repo: roborew/offthechain-spec
WARN: no implementation repos discovered under /Users/robo/05_Repos/01_PROJECTS/apps/offthechain
==> Creating roborew/offthechain-spec...
==> Copying scaffold from templates/spec-repo ...
/Users/robo/.config/opencode/bin/stack/create_or_sync_spec.sh: line 130: TARGETS[@]: unbound variable
```

The script aborted while writing `docs/agents/repos.md` in the newly created spec repo.

---

## Root cause

1. `bin/stack/create_or_sync_spec.sh` starts with `set -euo pipefail` and had an early `set +u` to allow optional empty arrays.
2. It then **sources** `bin/stack/common.sh`, which also runs `set -euo pipefail` and **re-enables nounset** (`-u`).
3. When no implementation repos are discovered under the project parent, `TARGETS` remains an empty array.
4. Under `set -u`, expanding an empty array in `for target in "${TARGETS[@]}"; do` triggers:

   ```text
   TARGETS[@]: unbound variable
   ```

This is a known Bash behaviour: nounset treats `"${empty_array[@]}"` as unbound.

The same failure would have occurred later in `bin/setup-project` when linking implementation repos if the first script had been fixed in isolation.

---

## Changes implemented

### 1. `bin/stack/create_or_sync_spec.sh`

| Before | After |
| --- | --- |
| `set +u` immediately after initial `set -euo pipefail` (line ~7) | Removed early `set +u` |
| Nounset re-enabled by `common.sh` with no follow-up | `set +u` placed **after** `source common.sh` |

Added comment at the new location:

```bash
set +u # common.sh enables nounset; TARGETS may be empty when no impl repos exist
```

**Why this works:** After sourcing shared helpers, nounset is disabled again so the `repos.md` generation loop can run with zero targets and produce a valid empty registry:

```yaml
repos:
```

### 2. `bin/setup-project`

| Before | After |
| --- | --- |
| `if [[ "$SPEC_ONLY" != "true" ]]; then` before the impl-linking loop | `if [[ "$SPEC_ONLY" != "true" && ${#TARGETS[@]} -gt 0 ]]; then` |

**Why this works:** Skips the “Linking implementation repos…” section when there is nothing to link, avoiding the same `"${TARGETS[@]}"` nounset error on the parent script (which also runs with `set -euo pipefail`).

**Note:** `setup-project` already guarded passing targets into `create_or_sync_spec.sh`:

```bash
[[ ${#TARGETS[@]} -gt 0 ]] && SYNC_SPEC_ARGS+=("${TARGETS[@]}")
```

Only the downstream loops needed the same empty-array handling.

---

## Expected behaviour after fix

For a project parent with **no** git implementation repos (only the spec repo or an empty parent):

1. `setup-project` prints the existing warning:

   ```text
   WARN: no implementation repos discovered under <parent>
   ```

2. Spec repo is created or synced on GitHub (e.g. `roborew/offthechain-spec`).
3. Scaffold is copied from `templates/spec-repo`.
4. `docs/agents/repos.md` is written with an empty `repos:` list and committed.
5. Tooling sync runs; impl linking is **skipped** (no spurious “Linking implementation repos…” block).
6. Script exits successfully; user can add implementation repos later and re-run `setup-project` to populate the registry.

---

## Files modified in session

| File | Change |
| --- | --- |
| `bin/stack/create_or_sync_spec.sh` | Move `set +u` to after `common.sh` source |
| `bin/setup-project` | Guard impl-linking block on `${#TARGETS[@]} -gt 0` |

**Not modified:** `bin/stack/common.sh`, discovery logic (`stack_discover_targets`), spec scaffold templates, or GitHub CLI create/clone flow.

---

## Validation performed

During the session:

```bash
bash -c '
set -euo pipefail
source bin/stack/common.sh
set +u
TARGETS=()
for target in "${TARGETS[@]}"; do echo "$target"; done
echo OK
'
```

Exit code 0 — empty-array loop succeeds after the fix pattern.

**Not run in session:** Full end-to-end `setup-project` against `/Users/robo/05_Repos/01_PROJECTS/apps/offthechain` (requires GitHub access and project paths).

---

## Review checklist

- [ ] Confirm `bin/stack/create_or_sync_spec.sh` has `set +u` **after** `source common.sh`, not before
- [ ] Confirm `bin/setup-project` linking section requires `${#TARGETS[@]} -gt 0`
- [ ] Re-run `setup-project` from `/Users/robo/05_Repos/01_PROJECTS/apps/offthechain` and confirm spec repo bootstrap completes
- [ ] Confirm `docs/agents/repos.md` in the spec repo contains `repos:` with no entries when no impl repos exist
- [ ] After adding an implementation repo under the parent, re-run `setup-project` and confirm registry + linking populate correctly

---

## References

- Trigger command: `setup-project` (from project parent or with explicit path)
- Related scripts: `bin/stack/create_or_sync_spec.sh`, `bin/stack/common.sh`, `bin/setup-project`
- Related review doc (same day): [`2026-06-01-setup-project-cross-stack-scope.md`](2026-06-01-setup-project-cross-stack-scope.md)
