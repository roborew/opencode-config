# 2026-06-01 — Registry migration overwrite + scribe Write tool fixes

**Session scope:** Fix two OpenCode config issues discovered during blocshed `downgrade-archival-recovery` setup: (1) `migrate_repos_registry.py` clobbering partially filled `docs/agents/repos.md` on every `feature-upgrade` sync, and (2) scribe using `edit`/`apply_patch` instead of Write for full-file overwrites.

**Status:** Implemented and verified in chat (9 unit tests passing). Verify on disk before merge — workspace may have diverged since this session.

---

## Background

During setup for the **downgrade-archival-recovery** feature in the blocshed stack:

1. Capability/owner checks on `docs/agents/repos.md` were passing after manual edits.
2. Remaining `FAIL` lines from tooling were expected — they indicated tickets still needed `issue-expand` (next step: architect option 1 in blocshed-web).
3. Two config bugs blocked reliable registry editing and sync:
   - **`feature-upgrade`** re-sync overwrote user-set registry fields.
   - **Scribe** repeatedly used patch/edit instead of Write when asked to overwrite `repos.md`, causing silent no-ops or corrupted content (including appended prompt text on one attempt).

---

## Problem 1 — Registry migration overwrites partial edits

### Trigger path

```text
bin/feature-upgrade
  → bin/stack/sync_spec_tooling.sh
    → python3 bin/lib/migrate_repos_registry.py docs/agents/repos.md
```

### Root cause

In `bin/lib/migrate_repos_registry.py`, the write gate conflated **schema migration** with **registry completeness**:

```python
needs_migration = any("name" in r and "repo" not in r for r in repos) or any(
    not is_complete(normalize_entry(r)) for r in repos
)
```

The second clause treated **any remaining TBD placeholder** as a migration trigger. Every `feature-upgrade` sync therefore rewrote `repos.md` until every repo was fully complete — even when the user was still filling in fields incrementally.

Additional fragility:

- **TBD values counted as “present”** in `normalize_entry()` (`raw[key] not in (None, "", [])`), so stale placeholder strings were never upgraded field-by-field.
- **Rewrite side effects:** each migration replaced the rich template header with a short hardcoded `HEADER` constant and dumped YAML as a bare list (no `repos:` key), making parse/write round-trips fragile — especially after scribe left malformed YAML via partial patches.

### Intended behaviour after fix

| Condition | Action |
| --- | --- |
| Legacy schema (`name:` without `repo:`, `role: target` without `application_role`) | Normalize and rewrite file |
| Partially filled registry (some repos/fields still TBD) | **Do not rewrite**; print `INCOMPLETE: …` and exit 3 |
| Fully complete registry | Print `ok` (check-only) or `no migration needed`; exit 0 |

---

## Problem 2 — Scribe prefers patch over Write

### Root cause

[`agents/scribe.md`](../agents/scribe.md) had both `write: true` and `edit: true`. In OpenCode, `edit` maps to patch/diff tooling (`apply_patch`). The scribe model (GPT-5-nano) reliably preferred patch for “update file” tasks even when parents supplied full `content` bodies.

Agent and skill text said “write **or** edit tool”, giving the model permission to pick patch — unreliable for full-file overwrites like `docs/agents/repos.md`.

---

## Changes implemented

### 1. `bin/lib/migrate_repos_registry.py`

#### 1a. Split schema migration from completeness check

Added `needs_schema_migration(repos)` — true **only** for structural changes:

- legacy `name:` without `repo:`
- legacy `role: target` without `application_role`
- missing `repo` / `name` key entirely

Removed `not is_complete(...)` from the write gate. `is_complete()` remains for `--check-only` and final exit 3 reporting only.

#### 1b. TBD-aware field merge

Added helpers:

| Helper | Purpose |
| --- | --- |
| `is_empty_or_tbd(value)` | Scalar missing, blank, or contains `"TBD"` |
| `clean_capabilities(caps)` | Drop list items containing `"TBD"`; empty list if nothing remains |
| `dedupe_repos(repos)` | Deduplicate normalized entries by `repo` key |

Updated `normalize_entry()` merge rules:

| Field | Rule |
| --- | --- |
| `application_role`, `agent_owner` | Keep raw if non-TBD; else fill from `infer_defaults(repo)` |
| `capabilities` | Keep cleaned non-TBD list; only if empty after cleaning, use defaults |
| `non_goals`, optional lists | Keep raw if non-empty; else `[]` |

Never replace the whole entry when another field still has TBD.

#### 1c. Safer `write_registry()`

- **`registry_content(header, repos)`** — preserves existing markdown header prose from the file; only replaces the YAML `repos:` block.
- **`format_registry_yaml(repos)`** — emits canonical `repos:\n` + indented list (matches template schema).
- **Write gate** — only when `needs_schema_migration()` is true **and** normalized content differs from on-disk content.

#### 1d. `main()` flow (after fix)

```text
split_registry(path)
  → normalize + dedupe
  → if --check-only: report incomplete repos, exit 3 or 0
  → if needs_schema_migration and content changed: backup (.bak), write_registry, print "migrated"
  → else: print "no migration needed"
  → if any repo incomplete: print INCOMPLETE, exit 3
```

---

### 2. Scribe — enforce Write for full-file persistence

#### Files changed

- [`agents/scribe.md`](../agents/scribe.md)
- [`skills/scribe/SKILL.md`](../skills/scribe/SKILL.md)

#### Agent frontmatter

```yaml
tools:
  write: true
  edit: false   # was true — prevents apply_patch for markdown writes
  bash: true
  skill: true
```

Removed the broad `permission.edit` wildcard block (scribe no longer uses edit). Kept bash allow for `archive_plan` `mv` only.

#### Instruction updates

Replaced ambiguous “write **or** edit” language with:

- **Normal create/update:** MUST use the **Write** tool with parent-supplied full `content`. Never use edit/patch.
- **Updates are full rewrites:** even `mode: update`, Write the entire file body.
- **Failure reporting:** if Write fails, `SCRIBE_FAILED` — do not fall back to patch.
- Explicit callout for **`docs/agents/repos.md`** and other `docs/agents/*` paths.

---

### 3. Regression tests

Added [`bin/lib/test_migrate_repos_registry.py`](../bin/lib/test_migrate_repos_registry.py) (stdlib `unittest`, 9 cases):

| Test | Asserts |
| --- | --- |
| Partial fill preserved | Real `application_role` + capabilities kept when another repo has TBD |
| TBD capabilities replaced, role kept | Filled `application_role` preserved; TBD capabilities get defaults |
| Mixed capabilities | TBD items dropped; real capability items kept |
| Legacy name → repo | `normalize_entry({"name": …, "role": "target"})` produces `repo` key |
| `needs_schema_migration` | True for legacy `name:`; false for partial TBD on modern schema |
| Incomplete does not rewrite | `main()` on partial registry: file bytes unchanged, exit 3, `no migration needed` |
| Legacy name migrates | `name:` entries rewritten to `repo:` with defaults filled |
| Partial fill after mixed legacy | Filled fields preserved when one entry still uses legacy `name:` |

Wired into [`scripts/validate-opencode-config.sh`](../scripts/validate-opencode-config.sh):

- Run `python3 -m unittest bin/lib/test_migrate_repos_registry.py -q`
- Skip edit-permission ordering checks for agents with `edit: false` in frontmatter (scribe)

---

## Verification performed in chat

```bash
# Unit tests
python3 -m unittest bin/lib/test_migrate_repos_registry.py -v
# → 9 tests OK

# Partial registry smoke
python3 bin/lib/migrate_repos_registry.py /tmp/partial-repos.md
# → "no migration needed" + "INCOMPLETE: …" + exit 3, file unchanged

# Config lint (migrate test step passed; pre-existing architect bash guard failures unrelated)
scripts/validate-opencode-config.sh
```

---

## Files touched (summary)

| File | Change |
| --- | --- |
| `bin/lib/migrate_repos_registry.py` | Schema/completeness split, TBD-aware merge, header-preserving write |
| `bin/lib/test_migrate_repos_registry.py` | New — 9 regression tests |
| `agents/scribe.md` | `edit: false`, Write-only instructions, permission.edit removed |
| `skills/scribe/SKILL.md` | Write mandatory; explicit repos.md callout |
| `scripts/validate-opencode-config.sh` | Unittest step; skip edit checks when `edit: false` |

---

## Out of scope (not implemented)

| Item | Notes |
| --- | --- |
| **`create_or_sync_spec.sh` registry overwrite** | `setup-project` still **always** overwrites `docs/agents/repos.md` with bare `name/role` list (lines 116–130). Separate footgun; not on the `feature-upgrade` path. See [`2026-05-20-setup-project-cross-stack-scope.md`](2026-05-20-setup-project-cross-stack-scope.md). |
| **Operational next step** | Open blocshed-web → architect → option 1 → slug `downgrade-archival-recovery` → `issue-expand` on each ticket, then orchestrate execution. Unblocked by these config fixes. |

---

## Operator notes

### When `feature-upgrade` reports INCOMPLETE

Expected while `docs/agents/repos.md` still has TBD placeholders. The registry file is **no longer rewritten** on each sync — only reported as incomplete (exit 3). Fill remaining fields via scribe (Write) or manual edit, then re-run.

### When scribe updates `repos.md`

Parent must pass full file `content`. Scribe should show **Write tool evidence** in its report, not `apply_patch`. If `SCRIBE_FAILED`, re-invoke with same content.

### Re-verify after merge

If the workspace has diverged (e.g. `bin/` tree absent, scribe permissions refactored), re-run:

```bash
python3 -m unittest bin/lib/test_migrate_repos_registry.py -v
scripts/validate-opencode-config.sh
```

And smoke-test a partial `repos.md` through `feature-upgrade` before relying on registry sync behaviour.

---

## Related documents

| Date | Document |
| --- | --- |
| 2026-05-20 | [setup-project cross-stack scope investigation](2026-05-20-setup-project-cross-stack-scope.md) |
| 2026-05-20 | [setup-project empty TARGETS fix](2026-05-20-setup-project-empty-targets-fix.md) |
