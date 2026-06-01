# 2026-05-19 — PRD YAML frontmatter validation and downgrade-archival-recovery fix

**Session scope:** Diagnose why `docs/prd/downgrade-archival-recovery.md` failed YAML parsing; fix the PRD; add validation so architect/scribe-generated ticket frontmatter cannot break `bin/fanout` again.

**Status:** Implemented and finalized in this chat. PRD validates on disk in **blocshed-spec**; run fanout when ready.

---

## Problem reported

While working in **blocshed-spec** (architect spec mode), parsing PRD tickets failed:

```bash
python3 -c "import yaml; f=open('docs/prd/downgrade-archival-recovery.md'); c=f.read(); parts=c.split('---'); fm=yaml.safe_load(parts[1]); tickets=fm.get('tickets',[]); print(len(tickets)); [print(t.get('id'), t.get('capability','MISSING')) for t in tickets]"
```

Traceback at `yaml.safe_load(parts[1])` — PyYAML could not parse the frontmatter.

`bin/fanout downgrade-archival-recovery` would fail the same way (via `yq` / frontmatter extraction).

### Misdiagnoses ruled out

| Hypothesis | Verdict |
| --- | --- |
| Architect bash **permission** deny rules (`*>*` redirects) | **Not the cause.** The Python one-liner has no redirects or pipes; it ran and failed on file content. |
| Naive `split('---')` breaking on horizontal rules in the markdown body | **Not the cause.** Split produced three parts (empty, frontmatter, body) correctly. |
| Unquoted `commit_message` colons only | **Partially true** in git HEAD; on disk at investigation time there was also **dedented** `commit_message` lines. Both break YAML. |

---

## Root cause (confirmed)

Three separate generator bugs in the PRD frontmatter for **`downgrade-archival-recovery`**:

### 1. Unquoted Conventional Commit subjects

Git HEAD had correctly indented but **unquoted** values:

```yaml
commit_message: fix(billing): correct at-limit route and count active-only org quota
#                          ^ YAML treats this as a new mapping key
```

PyYAML error:

```text
ScannerError: mapping values are not allowed here
  in line 13, column 33
```

**Fix:** Always double-quote `commit_message` when the value contains `:` (all Conventional Commits do).

### 2. Dedented `commit_message` (broken “repair” pass)

Working copy on disk had quoted messages but **`commit_message` at column 0** instead of under the ticket item:

```yaml
  - id: web-fix-billing-route
    repo: roborew/blocshed-web
    depends_on: []
commit_message: "fix(billing): ..."
    acceptance:
```

PyYAML error:

```text
ParserError: expected <block end>, but found '<block mapping start>'
  in line 14, column 5: acceptance:
```

**Fix:** Every ticket field (`repo`, `capability`, `commit_message`, `acceptance`, etc.) must stay at the **same 4-space indent** under its `- id:` line.

### 3. Missing `capability` on every ticket

The `to-prd` workflow requires `capability` per ticket (must match `docs/agents/repos.md`). Omission does not always fail YAML parse but **blocks `bin/fanout`** via `validate_tickets.py`.

---

## Who generates the bad YAML

| Agent | Role |
| --- | --- |
| **Architect** | Composes PRD markdown + frontmatter (via `to-prd` skill). |
| **Scribe** | Writes byte-for-byte what architect sends — **does not validate YAML**. |

Bad structure is an **architect authoring** problem, not scribe corruption or bash permissions.

---

## What was implemented

### 1. PRD repaired — `blocshed-spec/docs/prd/downgrade-archival-recovery.md`

| Change | Detail |
| --- | --- |
| Indentation | All `commit_message` lines indented under their ticket |
| Quoting | All `commit_message` values double-quoted |
| `capability` | Added on all 7 tickets from `docs/agents/repos.md` |
| Acceptance strings | Plain list items (colons in text quoted where needed) |

**Capability mapping applied:**

| Ticket id | capability |
| --- | --- |
| `web-fix-billing-route` | Subscription/billing (Stripe) |
| `web-stale-index-content` | Organisation/workspace/publication management |
| `web-archive-lifecycle` | Organisation/workspace/publication management |
| `web-downgrade-orchestration` | Subscription/billing (Stripe) |
| `web-billing-ui-panel` | Subscription/billing (Stripe) |
| `web-billing-unarchive` | Subscription/billing (Stripe) |
| `web-admin-purge` | Admin UI and marketing pages |

**Verification (passes on disk):**

```bash
cd /path/to/blocshed-spec
python3 bin/lib/validate_prd_frontmatter.py docs/prd/downgrade-archival-recovery.md
# ok (7 tickets)

python3 -c "import yaml; c=open('docs/prd/downgrade-archival-recovery.md').read(); fm=yaml.safe_load(c.split('---')[1]); print(len(fm['tickets']))"
# 7
```

### 2. New validator — `bin/lib/validate_prd_frontmatter.py`

Present in **blocshed-spec** (and intended for OpenCode `templates/spec-repo` sync).

| Check | Behavior |
| --- | --- |
| Frontmatter delimiters | File must start with `---`; extracts block before second `---` |
| YAML parse | `yaml.safe_load` on frontmatter only |
| `tickets` | Non-empty list |
| Required fields per ticket | `repo`, `capability`, `title`, `owner`, `commit_message`, `acceptance`, `test_commands` |
| Unquoted `commit_message` | Warns when source line has unquoted value containing `:` |

Usage:

```bash
python3 bin/lib/validate_prd_frontmatter.py docs/prd/<slug>.md
```

Exit 0 = safe to fanout; non-zero prints errors to stderr.

### 3. `bin/fanout` gate

**blocshed-spec** `bin/fanout` now requires the validator before creating issues:

```bash
[[ -f "$VALIDATE_PRD" ]] || { echo "missing $VALIDATE_PRD" >&2; exit 8; }
python3 "$VALIDATE_PRD" "$PRD_PATH"
```

Also wired in **blocshed-spec**: `bin/feature-check`, `bin/sync-fanout-bodies`.

### 4. PRD template documentation

**blocshed-spec** `docs/prd/_template.md` updated to document:

- Ticket field indentation under `- id:`
- Run `validate_prd_frontmatter.py` before fanout

*(Note: blocshed-spec template has since evolved — some fields like `commit_message` may be marked deprecated at spec phase in favour of `issue-expand`; the downgrade PRD retains them from the original slice.)*

### 5. OpenCode config changes (session intent)

During the chat, these were also edited under `~/.config/opencode` for upstream sync:

| Path | Change |
| --- | --- |
| `skills/to-prd/SKILL.md` | YAML frontmatter rules: 4-space indent, quote `commit_message`, validate before scribe |
| `templates/spec-repo/docs/prd/_template.md` | Quoting requirement + validation note |
| `templates/spec-repo/bin/fanout` | Call `validate_prd_frontmatter.py` before fanout |
| `templates/spec-repo/bin/lib/validate_prd_frontmatter.py` | New file |
| `bin/stack/sync_spec_tooling.sh` | Sync validator into spec repos |

**Verify on disk** before assuming OpenCode template tree matches — workspace layout may differ from a live spec repo after local evolution.

---

## Related issues (other sessions / docs)

These came up in the same planning episode but are **documented separately**:

| Topic | TO REVIEW doc |
| --- | --- |
| CRLF / `env: bash\r` on spec `bin/*` | `2026-05-19-crlf-line-endings-hardening.md` |
| Architect bash allow-by-default vs permission prompts | `2026-06-01-setup-project-workflow-and-deepseek-bash-fixes.md` (and architect agent changes) |
| Duplicate fanout tickets | Prior fanout rerun without dedupe — separate operational issue; fanout skips existing issues by title/`task_id` on re-run |
| `SPEC_REPO` markdown list parsing | `2026-06-01-spec-repo-markdown-parser.md` |

---

## Operator rollout

From **blocshed-spec** root:

```bash
# 1. Confirm PRD parses
python3 bin/lib/validate_prd_frontmatter.py docs/prd/downgrade-archival-recovery.md

# 2. Create child issues (skips any already created)
bin/fanout downgrade-archival-recovery
```

If OpenCode template tooling was updated separately, re-sync into other spec repos:

```bash
~/.config/opencode/bin/stack/sync_spec_tooling.sh /path/to/spec-repo
```

---

## YAML authoring rules (for architect / to-prd)

Copy-paste checklist for ticket frontmatter:

```yaml
tickets:
  - id: web-example
    repo: owner/repo
    capability: Exact string from docs/agents/repos.md
    title: "Quote title when it contains :"
    owner: developer
    mode: afk
    depends_on: []
    commit_message: "feat(scope): always quote conventional commits"
    acceptance:
      - "Quote criteria that contain colons: like this"
    test_commands:
      - bin/rails test test/models/example_test.rb
    body: |
      Optional multiline description.
```

**Never** put `commit_message` at column 0. **Never** leave Conventional Commit subjects unquoted.

---

## Files touched (summary)

### blocshed-spec (verified on disk)

| File | Change |
| --- | --- |
| `docs/prd/downgrade-archival-recovery.md` | Fixed YAML; added `capability` on 7 tickets |
| `bin/lib/validate_prd_frontmatter.py` | **Added** |
| `bin/fanout` | Validates PRD before fanout |
| `docs/prd/_template.md` | YAML authoring notes |
| `bin/feature-check`, `bin/sync-fanout-bodies` | Reference validator |

### OpenCode config (session edits — verify before merge)

| File | Change |
| --- | --- |
| `templates/spec-repo/bin/lib/validate_prd_frontmatter.py` | **Added** |
| `templates/spec-repo/bin/fanout` | PRD validation gate |
| `templates/spec-repo/docs/prd/_template.md` | Quoting + validation |
| `skills/to-prd/SKILL.md` | YAML rules + validate-before-scribe |
| `bin/stack/sync_spec_tooling.sh` | Sync validator |

---

## Review checklist

- [ ] `python3 bin/lib/validate_prd_frontmatter.py docs/prd/downgrade-archival-recovery.md` → `ok (7 tickets)`
- [ ] Python YAML one-liner prints 7 ticket ids with capabilities (no `MISSING`)
- [ ] `bin/fanout downgrade-archival-recovery` runs without frontmatter parse errors
- [ ] New PRDs from architect follow indent + quote rules; validator run before scribe/fanout
- [ ] OpenCode `templates/spec-repo` synced to spec repos if using central template tree

---

## Out of scope

- Rewriting historical GitHub issues from an earlier partial/duplicate fanout
- Changing scribe to validate YAML (validation belongs in architect compose step + fanout gate)
- Migrating all existing PRDs in all spec repos (fix per slug as needed; validator catches regressions)
