# 2026-05-19 — Feature Pipeline, Spec Tooling, and Architect Front Door

**Session scope:** Refine the spec-driven feature workflow (PRD → fanout → issue-expand → orchestrate), fix spec-repo tooling for real PRD markdown and macOS Bash 3.2, audit and sync `blocshed-spec` / `blocshed-web`, clarify operator paths vs `setup-project`, and rework the architect greeting menu so spec workflow and legacy planning are top-level choices.

**Status:** Implemented and finalized in this chat (session completion **2026-05-19**). Re-sync stacks with `setup-project` or `sync_spec_tooling.sh` / `sync_impl_tooling.sh` after pulling `~/.config/opencode`.

**Primary slug exercised:** `downgrade-archival-recovery` (`blocshed-spec` → `blocshed-web` issues **#77–#83**).

---

## Executive summary

| Area | Outcome |
| --- | --- |
| Workflow docs | Single canonical path in `docs/FEATURE-PIPELINE.md`; removed reactive “do not hardcode scripts” noise |
| Spec bins | PRD frontmatter parsed via `prd_io.py` (not `yq` on full `.md`); registry parsing fixed for `repos.md` |
| macOS Bash 3.2 | `declare -A` replaced with `task_map.sh`; `setup-project` empty-array crash fixed |
| BlocShed stack | Spec tooling synced; `feature-upgrade` PASS; impl gates PASS; `blocshed-api` impl bins synced |
| Architect UX | Implementation repo menu: **1 = spec workflow / issue-expand**, **2 = legacy `.plan`** (no A/B submenu) |
| Rejected | One-off Python ticket generators in app repos; duplicate `feature-upgrade` skill |

---

## Production workflow (final)

```text
spec:  grill-me → to-prd → approve → bin/fanout <slug>
       PRD edits → bin/feature-upgrade <slug>

impl:  architect option 1 (issue-expand) → orchestrate-readiness-check
       orchestrate → GitHub backlog feature:<slug>

close: architect Mode F → feature-complete (spec)
```

**Canonical doc:** `docs/FEATURE-PIPELINE.md`

**Key operator rule:** Updating existing GitHub issues from the PRD is **`bin/feature-upgrade <slug>`** in the spec repo — **not** closing issues and re-fanout, and **not** `setup-project` (unless refreshing installed bins after template changes).

---

## Documentation and skills cleaned

### Removed or merged

- **`skills/feature-upgrade/SKILL.md`** — deleted; redo/resync folded into **`skills/issue-expand/SKILL.md`** and `bin/feature-upgrade`
- Defensive callouts (“do not write one-off Python/shell with hardcoded issue numbers”) removed from skills and pipeline docs

### Updated

| File | Change |
| --- | --- |
| `docs/FEATURE-PIPELINE.md` | Tables-only flow and commands; PRD-edit path |
| `docs/RUNBOOK.md` | Shorter implementation-features pointer |
| `skills/issue-expand/SKILL.md` | PRD-change path via `feature-upgrade`; option 1 routing |
| `skills/setup-project/SKILL.md` | Migration table references `feature-upgrade` + `issue-expand` |
| `skills/fanout-issues/SKILL.md` | Rules section repaired; post-PRD `feature-upgrade` |
| `templates/spec-repo/README.md` | Pipeline summary |
| `bin/stack/print_next_steps.sh` | Pipeline one-liner |
| `README.md` | Daily use: architect **option 1** = issue-expand, **option 2** = legacy |

---

## OpenCode template / bin fixes

### 1. PRD frontmatter — `templates/spec-repo/bin/lib/prd_io.py`

**Problem:** `yq '.tickets'` on full PRD files (frontmatter + markdown body) failed at line ~138; `bin/feature-check`, `sync-fanout-bodies`, and `feature-upgrade` broke.

**Fix:** New helper reads YAML between `---` delimiters only. Commands: `tickets_json`, `tickets_count`, `get <field>`, `slices_json`.

**Wired in:** `bin/fanout`, `bin/sync-fanout-bodies`, `bin/feature-check`, `bin/feature-upgrade`, `bin/stack/sync_spec_tooling.sh` (check + sync loops).

### 2. Registry parsing — `validate_tickets.py` + `migrate_repos_registry.py`

**Problem:** `docs/agents/repos.md` used a bare YAML list after `---` without a top-level `repos:` key; `validate_tickets` saw an empty registry. `migrate_repos_registry.py` returned empty list for the same shape.

**Fix:**

- `validate_tickets.load_registry()` — parse `repos:` block, `---` + list tail, or line fallback; fix `_parse_repos_minimal` to use `body` not undefined `text`
- `agent_owner` validation accepts list (e.g. `[frontend-dev, developer]`)
- `migrate_repos_registry.split_registry()` — parse `---` followed by `- repo:` list

### 3. Bash 3.2 (macOS) — `templates/spec-repo/bin/lib/task_map.sh`

**Problem:** `sync-fanout-bodies` and `fanout` used `declare -A TASK_TO_NUM`; macOS `/bin/bash` 3.2 errors: `declare: -A: invalid option`.

**Fix:** Portable tab-delimited temp-file map (`task_map_init`, `task_map_set`, `task_map_get`, `task_map_cleanup`).

**Synced via:** `sync_spec_tooling.sh` (includes `task_map.sh` in lib install list).

### 4. `setup-project` empty-array crash

**Problem:** `CREATE_ARGS[@]` / `TARGETS[@]` with `set -u` and empty arrays on Bash 3.2 → `unbound variable` at line 148.

**Fix:** Build `SYNC_SPEC_ARGS` array; branch call when `CREATE_ARGS` non-empty.

### 5. Minor template tweaks

- `templates/spec-repo/bin/feature-check` — generic FAIL message pointing to FEATURE-PIPELINE
- `templates/spec-repo/bin/feature-upgrade` — header comment (sync PRD → issues, not “redo” drama)
- `bin/feature-upgrade` (project-parent wrapper) — same

---

## BlocShed stack — verified state

### Spec repo (`blocshed-spec`)

| Check | Result |
| --- | --- |
| PRD `downgrade-archival-recovery.md` | 7 tickets; parent issue #1 |
| `bin/feature-check --level fanout` | PASS on #77–#83 |
| `bin/feature-check --level orchestrate` | PASS (stages[], plans present) |
| `bin/feature-upgrade downgrade-archival-recovery` | Synced all 7 issues; STATUS PASS |
| PRD typo | `publication_spec.rb` → `publication_test.rb` |
| `docs/agents/repos.md` | Migrated to `repos:` schema via migrate script |

### Implementation repo (`blocshed-web`)

| Check | Result |
| --- | --- |
| `bin/orchestrate-readiness-check downgrade-archival-recovery` | PASS; next-runnable #77 |
| Open issues | #77–#83 (label `feature:downgrade-archival-recovery`) |

### Implementation repo (`blocshed-api`)

| Check | Result |
| --- | --- |
| `setup-project --check-only` (before fix) | INCOMPLETE — missing impl bins |
| `sync_impl_tooling.sh blocshed-api` | Synced `issue-expand-bundle`, `orchestrate-readiness-check`, `feature-check` |
| `setup-project --check-only` (after fix) | OK: blocshed-api, OK: blocshed-web |

### Explicitly rejected in app repos

- **`blocshed-web/tmp/scripts/build_expanded_issues.py`** — hardcoded issue numbers/bodies; deleted
- Project-local orchestrate-readiness scripts — logic lives in OpenCode templates only

---

## Architect front door (implementation repo)

**Problem:** On “hi”, architect showed an improvised shortened menu; spec workflow and legacy plan were merged into one line; A/B submenu was skipped; **issue-expand** was not discoverable.

**Fix in `agents/architect.md`:**

- **Two separate verbatim menus** — spec repo vs implementation repo
- **Implementation repo** (present on every greeting):

```text
1. Implementation feature (spec workflow) — issue-expand → orchestrate GitHub backlog
2. Legacy local plan — grill-me → .plan/feature.<slug>.md → orchestrate from file
3–8. Bug, refactor, review, domain/ADR, explore, setup-skills
```

- **Hard rule:** Present menu verbatim; no collapsing; no A/B submenu
- **Routing:** Option **1** → `issue-expand` (ask slug); Option **2** → `grill-me` + `architect-plan`
- **`skills/architect-plan/SKILL.md`** — defers greeting menu to architect agent; legacy = option 2 only

---

## Operator cheat sheet

| Goal | Where | Action |
| --- | --- | --- |
| Update GitHub issues from PRD | `blocshed-spec` | `bin/feature-upgrade <slug>` |
| Verify ticket format (spec) | `blocshed-spec` | `bin/feature-check <slug> --level orchestrate` |
| Enrich / verify tickets (OpenCode) | `blocshed-web` + **architect** | Reply **`1`**, slug → **issue-expand** skill |
| Run implementation | `blocshed-web` + **orchestrate** | GitHub backlog option B, slug |
| Check stack wiring only | project parent | `GH_ORG=roborew setup-project --check-only` |
| Refresh installed bins | project parent | `setup-project` (not required for each PRD sync) |

**Slug:** filename stem of `docs/prd/<slug>.md` (e.g. `downgrade-archival-recovery`).

---

## What orchestrate reads vs issue-expand

| Source | Used when |
| --- | --- |
| GitHub issue body (`opencode-task-json`, `stages[]`) | **Orchestrate** execution (primary) |
| Full PRD markdown | **issue-expand** / `issue-expand-bundle` / Mode F sign-off |
| Fanout-only tickets | Too thin for stage loop — **issue-expand required once** |

For `downgrade-archival-recovery`, issue-expand was already complete; orchestrate can run without another architect pass unless PRD or tickets change.

---

## Files touched (OpenCode config)

### New

- `templates/spec-repo/bin/lib/prd_io.py`
- `templates/spec-repo/bin/lib/task_map.sh`

### Modified (representative)

- `agents/architect.md`
- `bin/setup-project`
- `bin/feature-upgrade`
- `bin/stack/sync_spec_tooling.sh`
- `bin/lib/migrate_repos_registry.py`
- `templates/spec-repo/bin/{fanout,sync-fanout-bodies,feature-check,feature-upgrade}`
- `templates/spec-repo/bin/lib/validate_tickets.py`
- `skills/{issue-expand,architect-plan,setup-project,fanout-issues}/SKILL.md`
- `docs/{FEATURE-PIPELINE,RUNBOOK}.md`
- `README.md`
- `bin/stack/print_next_steps.sh`

### Deleted

- `skills/feature-upgrade/SKILL.md`

---

## Follow-up (optional, not done in chat)

- Commit/push OpenCode config changes and sync to sibling clones
- Commit `blocshed-api` new `bin/*` files
- Remove stale artifacts in spec: `.plan/prd.downgrade-archival-recovery.md`, `docs/agents/repos.md.bak`, `scripts/stack-bootstrap-blocshed-web.sh`
- Update `blocshed-spec/README.md` workflow section (still mentions legacy architect-plan path)
- Align `CONTEXT.md` archive window (2 months) with PRD admin purge (3 months)

---

## Related TO REVIEW docs

Same folder, date-prefixed for sort order:

- `2026-06-01-spec-repo-markdown-parser.md` — `SPEC_REPO` parsing in impl repos (separate session fix)
- `2026-06-01-setup-project-shell-bootstrap.md` — setup-project bootstrap behavior
- Other `2026-05-20-*` / `2026-06-01-*` setup-project investigations
