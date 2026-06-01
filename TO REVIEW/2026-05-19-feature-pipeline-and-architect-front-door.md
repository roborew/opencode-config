# 2026-05-19 — Feature Pipeline, Spec Tooling, and Architect Front Door

**Filename date (`2026-05-19`):** Cursor chat **creation date** (transcript file birth time), not the date this review doc was last edited.

**Chat transcript:** [Feature pipeline & blocshed workflow](6c0d95db-56b8-40cb-9b3a-54a31b198f7c)

**Session scope:** Refine the spec-driven feature workflow (PRD → fanout → issue-expand → orchestrate); fix spec-repo tooling for real PRD markdown and macOS Bash 3.2; audit and sync `blocshed-spec` / `blocshed-web`; clarify operator paths vs `setup-project`; rework architect greeting menu so **spec workflow** and **legacy planning** are top-level options (not an A/B submenu).

**Status:** Implemented and finalized across this chat thread. **Verify on disk** before relying on paths — a later checkout may omit `bin/`, `templates/`, or individual skills; recover from git history on this repo or from the snippets below.

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

## 1. New file — `templates/spec-repo/bin/lib/prd_io.py`

**Problem:** `yq -o=json '.tickets' docs/prd/<slug>.md` fails when the PRD has markdown body after frontmatter (`yaml: line 138: did not find expected <document start>`). Broke `feature-check`, `sync-fanout-bodies`, `feature-upgrade`, and `sync_spec_tooling.sh` validation loops.

**Fix:** Parse only YAML between the first pair of `---` delimiters (same approach as `validate_prd_frontmatter.py`).

```python
#!/usr/bin/env python3
"""Read PRD markdown frontmatter (YAML between --- delimiters)."""
from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    import yaml  # type: ignore
except ImportError:
    yaml = None


def extract_frontmatter(text: str) -> str:
    if not text.startswith("---"):
        raise ValueError("PRD must start with --- frontmatter delimiter")
    end = text.index("---", 3)
    return text[3:end]


def load_prd(path: Path) -> dict:
    if yaml is None:
        raise RuntimeError("PyYAML required")
    text = path.read_text(encoding="utf-8")
    block = extract_frontmatter(text)
    data = yaml.safe_load(block) or {}
    if not isinstance(data, dict):
        raise ValueError("PRD frontmatter must be a YAML mapping")
    return data


def main() -> None:
    if len(sys.argv) < 3:
        print(
            "usage: prd_io.py <command> <prd.md>\n"
            "  commands: tickets_json, tickets_count, get <field>, slices_json",
            file=sys.stderr,
        )
        sys.exit(1)

    cmd = sys.argv[1]
    path = Path(sys.argv[2])
    if not path.is_file():
        print(f"missing: {path}", file=sys.stderr)
        sys.exit(2)

    try:
        data = load_prd(path)
    except (ValueError, RuntimeError) as e:
        print(str(e), file=sys.stderr)
        sys.exit(3)

    if cmd == "tickets_json":
        print(json.dumps(data.get("tickets") or []))
    elif cmd == "tickets_count":
        tickets = data.get("tickets") or []
        print(len(tickets) if isinstance(tickets, list) else 0)
    elif cmd == "get":
        field = sys.argv[3] if len(sys.argv) > 3 else ""
        if not field:
            print("usage: prd_io.py get <prd.md> <field>", file=sys.stderr)
            sys.exit(1)
        print(data.get(field) or "")
    elif cmd == "slices_json":
        print(json.dumps(data.get("slices") or {}))
    else:
        print(f"unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
```

**Install:** `chmod +x`; copy via `bin/stack/sync_spec_tooling.sh` lib loop.

---

## 2. Wire `prd_io.py` into spec bins

### `sync-fanout-bodies` — replace `yq` on PRD

**Before:**

```bash
PARENT_URL=$(yq -r '.parent_issue // ""' "$PRD_PATH")
TICKET_COUNT=$(yq '.tickets // [] | length' "$PRD_PATH")
yq -o=json '.tickets' "$PRD_PATH" >"$TMP"
declare -A TASK_TO_NUM=()
```

**After:**

```bash
PRD_IO="${BIN_DIR}/lib/prd_io.py"
[[ -f "$PRD_IO" ]] || { echo "missing $PRD_IO" >&2; exit 8; }

PARENT_URL=$(python3 "$PRD_IO" get "$PRD_PATH" parent_issue)
TICKET_COUNT=$(python3 "$PRD_IO" tickets_count "$PRD_PATH")
python3 "$PRD_IO" tickets_json "$PRD_PATH" >"$TMP"
# shellcheck source=lib/task_map.sh
source "${BIN_DIR}/lib/task_map.sh"
task_map_init
trap 'task_map_cleanup; rm -f "$TMP"' EXIT
# ... per ticket ...
task_map_set "$TID" "$NUM"
dn=$(task_map_get "$dep_id")
```

### `feature-check` — replace `yq`

```bash
PRD_IO="${BIN_DIR}/lib/prd_io.py"
python3 "$PRD_IO" tickets_json "$PRD_PATH" >"$TMP"
TICKET_COUNT=$(jq 'length' "$TMP")
```

### `fanout` — replace `yq` for tickets; registry via Python

```bash
PRD_IO="${BIN_DIR}/lib/prd_io.py"
PARENT_URL=$(python3 "$PRD_IO" get "$PRD_PATH" parent_issue)
python3 "$PRD_IO" tickets_json "$PRD_PATH" >"$TMP"
TICKET_COUNT=$(python3 "$PRD_IO" tickets_count "$PRD_PATH")

# Registry count (replaces yq on repos.md):
REGISTRY_COUNT=$(python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '${BIN_DIR}/lib')
from validate_tickets import load_registry
print(len(load_registry(Path('${REGISTRY_PATH}'))))
")
```

Legacy slices keys:

```bash
python3 "$PRD_IO" slices_json "$PRD_PATH" | jq -r 'keys[]'
```

### `feature-upgrade` — impl repo list

**Before:**

```bash
IMPL_REPOS=$(yq -o=json '.tickets[].repo' "${ROOT}/docs/prd/${SLUG}.md" | jq -r 'unique | .[]')
```

**After:**

```bash
IMPL_REPOS=$(python3 "${BIN_DIR}/lib/prd_io.py" tickets_json "${ROOT}/docs/prd/${SLUG}.md" | jq -r '.[].repo' | sort -u)
```

### `bin/stack/sync_spec_tooling.sh`

Add to lib install loop:

```bash
for lib in validate_tickets.py validate_prd_frontmatter.py prd_io.py toposort_tickets.py \
  build_issue_body.sh extract_issue_sections.py validate_issue_body.py task_map.sh; do
```

Replace PRD validation loop (`--check-only` and post-sync):

```bash
if [[ -f "$VALIDATE" ]] && [[ -f "$SPEC/bin/lib/prd_io.py" ]]; then
  for prd in "$SPEC"/docs/prd/*.md; do
    [[ "$(basename "$prd")" == "_template.md" ]] && continue
    count=$(python3 "$SPEC/bin/lib/prd_io.py" tickets_count "$prd" 2>/dev/null || echo 0)
    [[ "$count" =~ ^[0-9]+$ ]] && [[ "$count" -gt 0 ]] || continue
    python3 "$SPEC/bin/lib/prd_io.py" tickets_json "$prd" | python3 "$VALIDATE" "$REGISTRY" || exit 6
  done
fi
```

---

## 3. New file — `templates/spec-repo/bin/lib/task_map.sh`

**Problem:** macOS `/bin/bash` 3.2 — `declare -A TASK_TO_NUM=()` → `declare: -A: invalid option`.

**Fix:** Tab-delimited temp file map.

```bash
#!/usr/bin/env bash
# Portable task_id -> issue number map (bash 3.2+; no declare -A).
task_map_init() {
  TASK_MAP_FILE=$(mktemp)
  : >"$TASK_MAP_FILE"
}

task_map_set() {
  printf '%s\t%s\n' "$1" "$2" >>"$TASK_MAP_FILE"
}

task_map_get() {
  awk -F'\t' -v id="$1" '$1==id {print $2; exit}' "$TASK_MAP_FILE"
}

task_map_cleanup() {
  rm -f "${TASK_MAP_FILE:-}"
}
```

**Usage in `fanout` / `sync-fanout-bodies`:**

```bash
source "${BIN_DIR}/lib/task_map.sh"
task_map_init
# ... loop: task_map_set "$TID" "$NUM"; dn=$(task_map_get "$dep_id") ...
task_map_cleanup
```

Remove all `declare -A TASK_TO_NUM` and `${TASK_TO_NUM[$id]}` references.

---

## 4. `templates/spec-repo/bin/lib/validate_tickets.py`

### `load_registry()` — parse bare list after `---`

**Problem:** `yaml.safe_load(entire repos.md)` fails on markdown header; `data.get("repos")` empty for blocshed format:

```markdown
# Application repo registry
...
---

- repo: roborew/blocshed-web
  application_role: ...
```

**Replace `load_registry` with:**

```python
def load_registry(path: Path) -> list[dict]:
    text = path.read_text(encoding="utf-8")

    m = re.search(r"(?ms)^repos:\s*\n(.*)$", text)
    if m and yaml is not None:
        try:
            data = yaml.safe_load("repos:\n" + m.group(1))
            if isinstance(data, dict) and isinstance(data.get("repos"), list):
                return [r for r in data["repos"] if isinstance(r, dict)]
        except yaml.YAMLError:
            pass

    parts = text.split("---")
    if len(parts) >= 2:
        tail = parts[-1].strip()
        if re.match(r"^-\s*(repo|name):", tail):
            if yaml is not None:
                try:
                    loaded = yaml.safe_load(tail)
                    if isinstance(loaded, list):
                        return [r for r in loaded if isinstance(r, dict)]
                except yaml.YAMLError:
                    pass
            return _parse_repos_minimal(tail)

    if yaml is not None:
        try:
            data = yaml.safe_load(text) or {}
            repos = data.get("repos") or []
            if isinstance(repos, list) and repos:
                return [r for r in repos if isinstance(r, dict)]
        except yaml.YAMLError:
            pass

    return _parse_repos_minimal(text)


def _parse_repos_minimal(body: str) -> list[dict]:
    repos: list[dict] = []
    current: dict | None = None
    list_key: str | None = None
    for raw in body.splitlines():
        # ... existing line parser (must use `body`, not undefined `text`) ...
```

### `agent_owner` validation — allow list

**Before:**

```python
if owner and expected and owner != expected:
    errors.append(...)
```

**After:**

```python
if owner and expected:
    allowed = expected if isinstance(expected, list) else [expected]
    if owner not in allowed:
        errors.append(
            f"ticket {tid}: owner '{owner}' not in registry agent_owner {allowed} for {repo}"
        )
```

---

## 5. `bin/lib/migrate_repos_registry.py` — `split_registry()`

When no `repos:` marker, parse list after final `---`:

```python
    elif idx == -1:
        parts = text.split("---")
        if len(parts) >= 2:
            tail = parts[-1].strip()
            if re.match(r"^-\s*(repo|name):", tail):
                header = parts[0].rstrip() + "\n\n"
                if yaml is not None:
                    try:
                        loaded = yaml.safe_load(tail)
                        if isinstance(loaded, list):
                            return header, [r for r in loaded if isinstance(r, dict)]
                    except yaml.YAMLError:
                        pass
                return header, _parse_repos_minimal(tail)
        return text, []
```

Running migrate on spec repo rewrites `docs/agents/repos.md` to canonical `repos:` block (creates `.bak` once).

---

## 6. `bin/setup-project` — Bash 3.2 empty-array fix

**Problem:** line ~148 — `"${CREATE_ARGS[@]}"` with empty array + `set -u` → `unbound variable`.

**Before:**

```bash
CREATE_ARGS=()
[[ "$KEEP_BRANCH" == "true" ]] && CREATE_ARGS+=(--keep-branch)
SPEC_PATH="$("${STACK}/create_or_sync_spec.sh" "${CREATE_ARGS[@]}" "$PARENT" "$APP" "$ORG" "${TARGETS[@]}")"
```

**After:**

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

Requires `GH_ORG` or `--org` for any run.

---

## 7. Architect front door — `agents/architect.md`

**Problem:** On “hi”, model improvised a shortened menu; merged issue-backed + legacy into one line; never showed A/B fork; **issue-expand** not discoverable.

**Fix:** Two verbatim menus; options **1** and **2** are top-level (no submenu).

### Implementation repo menu (present on every greeting)

```text
What are we planning?

1. Implementation feature (spec workflow) — PRD and child GitHub issues already exist (label feature:<slug> from spec fanout). Load issue-expand: pull PRD + tickets, verify and enrich each issue (user stories, implementation plan, TDD stages[] in opencode-task-json), run readiness gates, then prompt: switch to orchestrate → GitHub backlog for that slug.
2. Legacy local plan — grill-me → architect-plan → scribe writes .plan/feature.<slug>.md → orchestrate from file (no GitHub ticket queue).
3. Bug / debug investigation — reproduce, rank hypotheses, plan fix + regression test.
4. Refactor / technical cleanup — behavior-preserving plan with characterization tests.
5. Review / sign-off / remediation — inspect completed work, follow-up fixes, or GitHub feature sign-off (feature:<slug> vs PRD) after issue-backed orchestration.
6. Domain language or ADR — update CONTEXT.md terms or document a durable architecture decision.
7. Explore / understand repo — read-only map before deciding what to change.
8. Setup skills — bootstrap this repo's agent context (issue-tracker, triage labels, domain docs).
```

**Hard rules to add:**

```markdown
When the user greets you or gives an underspecified request, detect repo role and present **exactly one** menu below **verbatim** (same numbering, no collapsing options, no A/B submenus). **Do not** invent a shortened menu.

- **Option 1** → ask for **feature slug** if missing → load **`issue-expand`** immediately. Do **not** load `architect-plan`.
- **Option 2** → **`grill-me`** when required → **`architect-plan`** + scribe → `.plan/`.
```

### Spec repo menu (abbreviated)

```text
1. Product feature / PRD — grill-me → to-prd → approve → bin/fanout
2. Resync PRD to existing issues — bin/feature-upgrade <slug>
3. Feature complete — feature-complete
...
7. Setup / bootstrap stack — setup-project
```

### Skill routing line

```markdown
- **Issue expand:** Implementation repo front-door **option 1** → load **`issue-expand`**
```

### `skills/architect-plan/SKILL.md`

Remove duplicate greeting menu; defer to architect agent:

```markdown
- If greeting only: **do not invent a menu** — architect agent presents repo-specific front door.
- **Legacy local plan** (implementation repo option 2) → this skill after grill-me.
- **Spec workflow** (option 1) → **`issue-expand`**, not this skill.
```

### `skills/issue-expand/SKILL.md`

```markdown
## When

- User chose **implementation repo front-door option 1** (spec workflow / issue-expand).
```

### `README.md` daily use

```markdown
1. **architect** in impl repo → **option 1** (spec workflow / issue-expand)
**Legacy path:** architect **option 2** (legacy local plan)
```

---

## 8. Documentation cleanup

### Deleted

- `skills/feature-upgrade/SKILL.md` — merged into `issue-expand` + `bin/feature-upgrade`

### `docs/FEATURE-PIPELINE.md` (structure)

```markdown
| 3 | impl | bin/issue-expand-bundle → architect issue-expand |
| PRD edits | bin/feature-upgrade <slug> |
Levels: fanout | orchestrate
```

### `bin/stack/print_next_steps.sh`

```bash
echo "Pipeline: docs/FEATURE-PIPELINE.md"
echo "  grill-me → to-prd → bin/fanout → issue-expand → orchestrate → feature-complete"
echo "  PRD edits: bin/feature-upgrade <slug> (spec) or feature-upgrade <slug> (project parent)"
```

### Removed pattern (do not re-add)

Defensive paragraphs like “Do not write one-off Python with hardcoded issue numbers” — workflow is positive: use `bin/feature-upgrade`, `issue-expand`, templates only.

---

## 9. BlocShed verification (commands run in chat)

### Spec — sync + upgrade

```bash
~/.config/opencode/bin/stack/sync_spec_tooling.sh ~/05_Repos/.../blocshed-spec
cd blocshed-spec
bin/feature-upgrade downgrade-archival-recovery
# Synced #77–#83; STATUS: PASS — ready for orchestrate
```

### Spec — checks

```bash
bin/feature-check downgrade-archival-recovery --level fanout
bin/feature-check downgrade-archival-recovery --level orchestrate
```

### Impl web

```bash
cd blocshed-web
bin/orchestrate-readiness-check downgrade-archival-recovery
# PASS: ready for orchestrate option B; next-runnable #77
```

### Impl api — wiring gap fixed

```bash
~/.config/opencode/bin/stack/sync_impl_tooling.sh ~/05_Repos/.../blocshed-api
export GH_ORG=roborew
setup-project --check-only ~/05_Repos/.../apps/blocshed
# OK: blocshed-api; OK: blocshed-web; All checks passed
```

### PRD typo (blocshed-spec)

```yaml
    test_commands:
      - bin/rails test test/models/publication_test.rb   # was publication_spec.rb
```

### Rejected / deleted in app repos

- `blocshed-web/tmp/scripts/build_expanded_issues.py` — hardcoded #77–#83 bodies
- Per-project orchestrate-readiness shell duplicates

---

## 10. Operator cheat sheet

| Goal | Where | OpenCode / shell |
| --- | --- | --- |
| Update issues from PRD | spec | `bin/feature-upgrade <slug>` |
| Enrich tickets before orchestrate | web + **architect** | Menu **1** + slug → **issue-expand** (architect runs bins) |
| Run implementation | web + **orchestrate** | GitHub backlog **option B**, slug |
| Check stack wiring | project parent | `GH_ORG=… setup-project --check-only` |
| Refresh installed bins | project parent | `setup-project` (not per PRD sync) |

**Slug:** `docs/prd/<slug>.md` basename (e.g. `downgrade-archival-recovery`).

---

## 11. Context model (why issue-expand exists)

| Layer | Holds |
| --- | --- |
| Spec PRD | Narrative, user stories, `tickets[]` acceptance/tests |
| Fanout issues | Thin bodies + `opencode-task-json` placeholders |
| **issue-expand** | `stages[]`, Implementation plan, User stories covered on each GitHub issue |
| **Orchestrate** | Reads **issue body only** (`opencode_meta`, `stages[]`) — not full PRD unless developer explores |
| Mode F | Architect compares closed issues vs PRD via `SPEC_REPO` |

Fanout alone is **not** enough for stage loop. Option **1** in impl architect is the mandatory enrich/verify step (once per feature, or again after PRD changes + `feature-upgrade`).

---

## 12. Files touched (checklist for another AI)

### New under `templates/spec-repo/bin/lib/`

- [ ] `prd_io.py`
- [ ] `task_map.sh`

### Modified templates

- [ ] `templates/spec-repo/bin/fanout`
- [ ] `templates/spec-repo/bin/sync-fanout-bodies`
- [ ] `templates/spec-repo/bin/feature-check`
- [ ] `templates/spec-repo/bin/feature-upgrade`
- [ ] `templates/spec-repo/bin/lib/validate_tickets.py`

### Modified OpenCode root

- [ ] `bin/setup-project` (empty-array fix)
- [ ] `bin/lib/migrate_repos_registry.py`
- [ ] `bin/stack/sync_spec_tooling.sh`
- [ ] `bin/stack/print_next_steps.sh`
- [ ] `bin/feature-upgrade` (wrapper comment)
- [ ] `agents/architect.md` (front door)
- [ ] `skills/issue-expand/SKILL.md`
- [ ] `skills/architect-plan/SKILL.md`
- [ ] `skills/setup-project/SKILL.md`
- [ ] `skills/fanout-issues/SKILL.md`
- [ ] `docs/FEATURE-PIPELINE.md`
- [ ] `docs/RUNBOOK.md`
- [ ] `README.md`

### Deleted

- [ ] `skills/feature-upgrade/SKILL.md`

### App repo (BlocShed, optional commit)

- [ ] `blocshed-spec/docs/prd/downgrade-archival-recovery.md` (test path typo)
- [ ] `blocshed-spec/docs/agents/repos.md` (migrated)
- [ ] `blocshed-api/bin/{issue-expand-bundle,orchestrate-readiness-check,feature-check}` (synced)

---

## 13. Related TO REVIEW docs (same chat era)

| File | Topic |
| --- | --- |
| `2026-05-19-spec-central-stack-workflow-implementation.md` | Broader spec-central stack plan |
| `2026-05-19-spec-impl-issue-workflow-split.md` | Spec vs impl responsibilities |
| `2026-05-19-prd-yaml-frontmatter-validation.md` | PRD YAML validation |
| `2026-05-19-registry-migration-scribe-write-fixes.md` | Registry migration |
| `2026-05-20-setup-project-empty-targets-fix.md` | Related setup-project fixes |
| `2026-06-01-issue-backed-workflow-orchestrate-handoff.md` | ready-for-agent vs orchestrate handoff (investigation only) |

---

## 14. Follow-up (optional, not done in chat)

- Commit/push OpenCode config; re-run `sync_spec_tooling.sh` / `sync_impl_tooling.sh` on clones
- Remove stale spec artifacts: `.plan/prd.downgrade-archival-recovery.md`, `repos.md.bak`, `scripts/stack-bootstrap-blocshed-web.sh`
- Update `blocshed-spec/README.md` workflow section
- Align `CONTEXT.md` archive window (2 months) vs PRD admin purge (3 months)
