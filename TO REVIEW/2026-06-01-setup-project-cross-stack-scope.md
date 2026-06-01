# 2026-06-01 — setup-project Cross-Stack Scope Investigation

**Session scope:** Diagnose why running `setup-project` for a new project appeared to modify or wire unrelated projects.

**Status:** Investigation and operator guidance finalized in chat. **No code changes were implemented or committed in this session.** Optional hardening (app-prefix filtering) was suggested but not built.

---

## Problem reported

Running stack bootstrap (`setup-project`) for a **new** project caused setup to run against **other projects** as well — linking impl repos, rewriting registry files, syncing tooling, and seeding labels outside the intended stack.

---

## Root cause

`setup-project` scopes work to a **project parent directory**, not to “the repo you have open” or a GitHub org-wide project name.

### How parent directory is chosen

From `bin/setup-project`:

- Default: **`$(pwd)`** — whatever directory the shell is in when the command runs.
- Override: pass an explicit path as the last argument, e.g. `setup-project --org OWNER ~/code/myapp`.

All sibling discovery, registry generation, linking, and label seeding happen **only under that parent path**.

### How implementation repos are discovered

`stack_discover_targets` in `bin/stack/common.sh` scans **every immediate child** of the parent that:

1. Has a `.git` directory, and
2. Is **not** classified as a spec repo (`*-spec` folder with `docs/prd/` or `docs/agents/repos.md`).

There is **no filter** by app slug prefix (e.g. only `myapp-web`, `myapp-api`). Any other git clone under the same parent is treated as part of the same stack.

### What happens to discovered repos

When targets are found (or over-discovered), `bin/stack/create_or_sync_spec.sh`:

1. **Overwrites** `docs/agents/repos.md` in the spec repo with the discovered list (comment in file: *“rerunning replaces the repo list below”*).
2. **Commits and pushes** that registry sync.
3. **Seeds GitHub labels** on the spec repo and on every repo listed in `repos.md` (when `yq` + `jq` are available).
4. Calls `link_impl_repo.sh` per target, which writes `docs/agents/issue-tracker.md` with `SPEC_REPO:` and runs `sync_impl_tooling.sh`.

So a single run from the wrong parent can re-point multiple unrelated impl repos at one spec repo and refresh OpenCode scaffolding across them.

---

## Intended layout (documented design)

The README and `setup-project` header assume a **per-project container folder** with no git root at the container level:

```text
~/code/myapp/              ← run setup-project FROM HERE
  myapp-spec/
  myapp-web/
  myapp-api/
```

- Parent folder name → default app slug (`myapp`).
- Siblings are `APP-spec` and `APP-*` implementation repos only.

See: `README.md` § Setup, `bin/setup-project` usage block, `skills/setup-project/SKILL.md` preconditions.

---

## Failure modes that match the reported behaviour

### 1. Running from too high a directory

Example — flat layout under `~/code/`:

```text
~/code/                    ← setup run from here
  myapp-spec/
  myapp-web/
  blocshed-spec/
  blocshed-web/
  other-api/
```

Setup treats **all** non-spec git siblings as targets for the stack being bootstrapped (app slug derived from parent basename `code`, or from whichever spec repo resolves on disk).

### 2. Multiple stacks sharing one parent

Any folder containing clones from more than one product without an isolating container will cause cross-stack bleed. Spec folders (`*-spec`) are skipped as targets, but **impl repos from other products are not**.

### 3. OpenCode skill follows a bad registry

After a bad shell bootstrap, the **setup-project skill** (architect, in spec repo) reads `docs/agents/repos.md` and sibling paths under `../`. A corrupted registry causes the agent phase to fan out across the same wrong repo set.

---

## Relevant code paths (reference)

| Location | Role |
| --- | --- |
| `bin/setup-project` | Entry point; resolves `PARENT`, `APP`, `SPEC_REPO`; calls create/sync, tooling sync, impl linking |
| `bin/stack/common.sh` → `stack_discover_targets` | Broad sibling scan (no app-prefix filter) |
| `bin/stack/common.sh` → `stack_resolve_spec_dir` | Resolves spec path; may match any `*-spec` under parent if canonical `{app}-spec` missing |
| `bin/stack/create_or_sync_spec.sh` | Regenerates `docs/agents/repos.md`, commit/push, label seeding |
| `bin/stack/link_impl_repo.sh` | Writes `issue-tracker.md`, runs `sync_impl_tooling.sh` |
| `bin/stack/check_impl_wiring.sh` | `--check-only` wiring validation using same discovery |
| `skills/setup-project/SKILL.md` | Agent orchestration after shell bootstrap |

### Discovery logic (authoritative snippet)

```bash
# bin/stack/common.sh — stack_discover_targets
for dir in "${parent_dir}"/*/; do
  [[ -d "${parent_dir}/${dir}/.git" ]] || continue
  stack_dir_is_spec_repo ... && continue
  printf '%s\n' "$dir"   # every other git sibling → target
done
```

---

## Operator guidance finalized in chat

### Before running setup again

```bash
cd /path/to/project-parent    # must contain ONLY this stack’s siblings
pwd
ls -d */
```

Dry run:

```bash
export GH_ORG=your-org
setup-project --check-only /path/to/project-parent
```

If the check lists repos from other products, the parent path is wrong.

### Correct bootstrap command

```bash
mkdir -p ~/code/myapp && cd ~/code/myapp
# clone only myapp-spec, myapp-web, myapp-api here
export GH_ORG=OWNER
setup-project
# or: setup-project --keep-branch
```

### Remediation after a bad run

1. **Other projects’ impl repos** — inspect `docs/agents/issue-tracker.md` for wrong `SPEC_REPO:`; revert or fix via git history.
2. **Spec registries** — inspect `docs/agents/repos.md` for unrelated `repos:` entries; revert commits or edit registry manually.
3. **Re-bootstrap** from the correct isolated parent once layout is fixed.

---

## What was NOT done in this session

| Item | Status |
| --- | --- |
| Add `${APP}-*` prefix filter to `stack_discover_targets` | Suggested, not implemented |
| Warn when multiple `*-spec` repos exist under one parent | Suggested, not implemented |
| Revert collateral changes in user’s project repos | Not performed (no repo paths provided) |
| Commit or merge script changes | Not requested |

### Pre-existing uncommitted changes (not from this chat)

At conversation start, git status showed local modifications (not authored in this session):

- `bin/setup-project` — guard: skip impl linking when `TARGETS` is empty (`SPEC_ONLY` path unchanged).
- `bin/stack/create_or_sync_spec.sh` — `set +u` after sourcing `common.sh` when `TARGETS` may be empty.

Verify on disk whether these remain uncommitted or were merged separately.

---

## Optional hardening (future work)

If flat layouts under a shared parent must be supported safely:

1. **Filter discovery** to directories matching `${APP}-*` (case-insensitive), excluding `${APP}-spec`.
2. **Fail or prompt** when more than one `*-spec` repo exists under the parent.
3. **Document loudly** in `setup-project` stdout when parent contains repos that do not match the app slug.

---

## Review checklist

- [ ] Confirm project layout uses one container folder per stack (`~/code/APP/` not `~/code/`).
- [ ] Run `setup-project --check-only` from the intended parent and verify target list.
- [ ] Audit impl repos that were touched incorrectly (`issue-tracker.md`, synced `bin/*`).
- [ ] Audit spec `docs/agents/repos.md` for stray entries; revert if needed.
- [ ] Decide whether to implement app-prefix filtering in `stack_discover_targets`.
- [ ] Re-run shell bootstrap from correct parent, then architect **setup-project** skill in spec if needed.

---

## References

- `README.md` — Setup § project layout and `setup-project` usage
- `bin/setup-project` — script header and usage
- `bin/stack/common.sh` — `stack_discover_targets`, `stack_resolve_spec_dir`
- `bin/stack/create_or_sync_spec.sh` — registry generation and label seeding
- `skills/setup-project/SKILL.md` — post-shell agent bootstrap
- `docs/RUNBOOK.md` — stack bootstrap runbook (if present on disk)
