# 2026-05-19 — PRD YAML frontmatter validation and downgrade-archival-recovery fix

**Cursor chat created:** 2026-05-19 18:31:07 (local)  
**Chat transcript ID:** `9abcbc8d-824c-4138-a692-e31a1cc4612d`  
**Filename date (`2026-05-19`):** Matches **Cursor chat creation date**, not the calendar day documentation was last edited.

**Session scope:** Diagnose why `docs/prd/downgrade-archival-recovery.md` failed YAML parsing; fix the PRD in **blocshed-spec**; add `validate_prd_frontmatter.py` and wire it into fanout so architect-generated ticket frontmatter cannot break `bin/fanout` again.

**Status:** Implemented and finalized in this chat. PRD validates on disk; run fanout when ready.

**Primary repos/paths:**

| Location | Path |
| --- | --- |
| Spec repo (fixed PRD + tooling) | `/Users/robo/05_Repos/01_PROJECTS/apps/blocshed/blocshed-spec` |
| OpenCode config (template/skill edits — verify on disk) | `~/.config/opencode` |

---

## Problem reported

While working in **blocshed-spec** (architect spec mode), parsing PRD tickets failed:

```bash
python3 -c "import yaml; f=open('docs/prd/downgrade-archival-recovery.md'); c=f.read(); parts=c.split('---'); fm=yaml.safe_load(parts[1]); tickets=fm.get('tickets',[]); print(len(tickets)); [print(t.get('id'), t.get('capability','MISSING')) for t in tickets]"
```

Traceback at `yaml.safe_load(parts[1])` — PyYAML could not parse the frontmatter.

`bin/fanout downgrade-archival-recovery` would fail the same way (via frontmatter extraction / `yq` / `prd_io.py`).

### Reproduction commands (for another AI)

```bash
cd /Users/robo/05_Repos/01_PROJECTS/apps/blocshed/blocshed-spec

# Should print "ok (7 tickets)" after fix
python3 bin/lib/validate_prd_frontmatter.py docs/prd/downgrade-archival-recovery.md

# Quick parse check
python3 -c "
import yaml
c = open('docs/prd/downgrade-archival-recovery.md').read()
fm = yaml.safe_load(c.split('---')[1])
for t in fm['tickets']:
    print(t['id'], t.get('capability', 'MISSING'))
"

# Fanout gate (does not create issues if you stop after validation)
head -25 bin/fanout   # confirm VALIDATE_PRD + python3 call before PARENT_URL
```

### Misdiagnoses ruled out

| Hypothesis | Verdict |
| --- | --- |
| Architect bash **permission** deny rules (`*>*` redirects) | **Not the cause.** The Python one-liner has no redirects or pipes; it ran and failed on file content. |
| Naive `split('---')` breaking on horizontal rules in the markdown body | **Not the cause.** Split produced three parts (empty, frontmatter, body) correctly. |
| Unquoted `commit_message` colons only | **True in git commit `7f71cef`.** On disk at investigation time there was **also** dedented `commit_message` at column 0 from a bad repair pass. |

---

## Root cause (confirmed)

Three generator bugs in PRD frontmatter for **`downgrade-archival-recovery`**:

### 1. Unquoted Conventional Commit subjects (git `7f71cef`)

**Before (broken — from `git show 7f71cef:docs/prd/downgrade-archival-recovery.md`):**

```yaml
  - id: web-fix-billing-route
    repo: roborew/blocshed-web
    title: Fix billing route helper + active-only org quota
    owner: developer
    mode: afk
    depends_on: []
    commit_message: fix(billing): correct at-limit route and count active-only org quota
    acceptance:
      - Billing route helper renders correct path at publication limit
```

PyYAML error:

```text
ScannerError: mapping values are not allowed here
  in line 13, column 33
```

**After (fixed):**

```yaml
  - id: web-fix-billing-route
    repo: roborew/blocshed-web
    capability: Subscription/billing (Stripe)
    title: Fix billing route helper + active-only org quota
    owner: developer
    mode: afk
    depends_on: []
    commit_message: "fix(billing): correct at-limit route and count active-only org quota"
    acceptance:
      - Billing route helper renders correct path at publication limit
```

### 2. Dedented `commit_message` (broken repair pass on working copy)

**Before (broken — observed on disk during chat):**

```yaml
  - id: web-fix-billing-route
    repo: roborew/blocshed-web
    depends_on: []
commit_message: "fix(billing): correct at-limit route and count active-only org quota"
    acceptance:
```

PyYAML error:

```text
ParserError: expected <block end>, but found '<block mapping start>'
  in line 14, column 5: acceptance:
```

**Fix:** Re-indent with regex `^commit_message:` → `    commit_message:` inside frontmatter only.

### 3. Missing `capability` on every ticket

Required by `to-prd` / `validate_tickets.py` / fanout. Does not always fail YAML parse but blocks registry validation.

**Capability mapping applied (from `docs/agents/repos.md`):**

```python
CAPS = {
    "web-fix-billing-route": "Subscription/billing (Stripe)",
    "web-stale-index-content": "Organisation/workspace/publication management",
    "web-archive-lifecycle": "Organisation/workspace/publication management",
    "web-downgrade-orchestration": "Subscription/billing (Stripe)",
    "web-billing-ui-panel": "Subscription/billing (Stripe)",
    "web-billing-unarchive": "Subscription/billing (Stripe)",
    "web-admin-purge": "Admin UI and marketing pages",
}
```

### Who generates the bad YAML

| Agent | Role |
| --- | --- |
| **Architect** | Composes PRD markdown + frontmatter (via `to-prd` skill). |
| **Scribe** | Writes byte-for-byte what architect sends — **does not validate YAML**. |

---

## Implementation guide (recreate all changes)

### Step 1 — Repair existing PRD (`docs/prd/downgrade-archival-recovery.md`)

Run from spec repo root. This script was used in the chat to rebuild frontmatter from git + apply fixes:

```python
#!/usr/bin/env python3
"""One-shot repair for downgrade-archival-recovery PRD frontmatter."""
import re
import subprocess
import yaml
from pathlib import Path

path = Path("docs/prd/downgrade-archival-recovery.md")

# Optional: start from last known broken git revision
text = subprocess.check_output(
    ["git", "show", "7f71cef:docs/prd/downgrade-archival-recovery.md"],
    text=True,
)

body_start = text.index("---", 3)
fm = text[3:body_start]
body = text[body_start + 3 :]

# Quote unquoted commit_message lines
fm = re.sub(
    r"(?m)^(\s*commit_message:\s*)(.+)$",
    lambda m: (
        m.group(1) + '"' + m.group(2).strip().strip('"').strip("'") + '"'
        if ":" in m.group(2) and not m.group(2).strip().startswith(('"', "'"))
        else m.group(0)
    ),
    fm,
)

data = yaml.safe_load(fm)

CAPS = {
    "web-fix-billing-route": "Subscription/billing (Stripe)",
    "web-stale-index-content": "Organisation/workspace/publication management",
    "web-archive-lifecycle": "Organisation/workspace/publication management",
    "web-downgrade-orchestration": "Subscription/billing (Stripe)",
    "web-billing-ui-panel": "Subscription/billing (Stripe)",
    "web-billing-unarchive": "Subscription/billing (Stripe)",
    "web-admin-purge": "Admin UI and marketing pages",
}

for t in data["tickets"]:
    t["capability"] = CAPS[t["id"]]

lines = ["---"]
lines.append(f"slug: {data['slug']}")
lines.append(f'parent_issue: "{data["parent_issue"]}"')
lines.append("target_repos:")
for r in data["target_repos"]:
    lines.append(f"  - {r}")
lines.append("tickets:")

for t in data["tickets"]:
    lines.append(f"  - id: {t['id']}")
    lines.append(f"    repo: {t['repo']}")
    lines.append(f"    capability: {t['capability']}")
    title = t["title"]
    if ":" in title and not title.startswith("'"):
        title = f"'{title}'"
    lines.append(f"    title: {title}")
    lines.append(f"    owner: {t['owner']}")
    lines.append(f"    mode: {t['mode']}")
    dep = t["depends_on"]
    lines.append(f"    depends_on: [{', '.join(dep)}]" if dep else "    depends_on: []")
    lines.append(f'    commit_message: "{t["commit_message"]}"')
    lines.append("    acceptance:")
    for a in t["acceptance"]:
        # Quote acceptance lines that contain colons
        if isinstance(a, str) and ":" in a and not (a.startswith('"') or a.startswith("'")):
            lines.append(f'      - "{a}"')
        else:
            lines.append(f"      - {a}")
    lines.append("    test_commands:")
    for tc in t["test_commands"]:
        lines.append(f"      - {tc}")
    lines.append("    body: |")
    for bl in t["body"].strip().splitlines():
        lines.append(f"      {bl}")

lines.append("---")
path.write_text("\n".join(lines) + body, encoding="utf-8")
print("wrote", path)
```

**Important:** Do **not** use `yaml.dump()` for the whole frontmatter — it mangles `body: |` blocks and can corrupt acceptance list items containing colons.

**Acceptance lines manually fixed in chat** (if yaml.dump produced dicts):

```yaml
# Wrong (from broken yaml round-trip):
- {'Free tier': 'locked-down view-only with Upgrade CTA'}

# Correct:
- "Free tier: locked-down view-only with Upgrade CTA"
- "Paid tier: shows unarchive controls when allowance remains"
- "Success: publication reappears; quota updated"
```

### Step 2 — Add `bin/lib/validate_prd_frontmatter.py`

Create executable (`chmod +x`). Full file as deployed in **blocshed-spec**:

```python
#!/usr/bin/env python3
"""Validate PRD markdown frontmatter before fanout.

Usage: validate_prd_frontmatter.py <docs/prd/slug.md>
Exits 0 when frontmatter YAML parses and required ticket fields are present.
"""
from __future__ import annotations

import re
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


def main() -> None:
    if len(sys.argv) < 2:
        print("usage: validate_prd_frontmatter.py <prd.md>", file=sys.stderr)
        sys.exit(1)
    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"missing: {path}", file=sys.stderr)
        sys.exit(2)

    text = path.read_text(encoding="utf-8")
    try:
        block = extract_frontmatter(text)
    except ValueError as e:
        print(str(e), file=sys.stderr)
        sys.exit(3)

    if yaml is None:
        print("PyYAML required", file=sys.stderr)
        sys.exit(4)

    try:
        data = yaml.safe_load(block) or {}
    except yaml.YAMLError as e:
        print(f"invalid YAML frontmatter: {e}", file=sys.stderr)
        sys.exit(5)

    tickets = data.get("tickets") or []
    if not isinstance(tickets, list) or not tickets:
        print("tickets: must be a non-empty list", file=sys.stderr)
        sys.exit(6)

    errors: list[str] = []
    for t in tickets:
        tid = t.get("id") or "<unknown>"
        for field in ("repo", "capability", "title", "owner", "acceptance"):
            val = t.get(field)
            if not val:
                errors.append(f"ticket {tid}: missing {field}")
            elif field == "acceptance" and isinstance(val, list) and len(val) == 0:
                errors.append(f"ticket {tid}: acceptance must be non-empty")
        cm = str(t.get("commit_message") or "")
        if cm and ":" in cm:
            pattern = rf"(?m)^\s*commit_message:\s*{re.escape(cm)}\s*$"
            if re.search(pattern, block) and not re.search(
                rf'(?m)^\s*commit_message:\s*["\']{re.escape(cm)}["\']\s*$', block
            ):
                errors.append(
                    f"ticket {tid}: commit_message must be quoted (contains ':'): {cm!r}"
                )

    if errors:
        for e in errors:
            print(e, file=sys.stderr)
        sys.exit(7)

    print(f"ok ({len(tickets)} tickets)")


if __name__ == "__main__":
    main()
```

**Exit codes:** 1 usage, 2 missing file, 3 bad delimiters, 4 no PyYAML, 5 YAML parse error, 6 empty tickets, 7 field validation errors, 0 ok.

### Step 3 — Wire validator into `bin/fanout`

Add near top of fanout (after path setup, **before** reading `parent_issue`):

```bash
VALIDATE_PRD="${BIN_DIR}/lib/validate_prd_frontmatter.py"
[[ -f "$VALIDATE_PRD" ]] || { echo "missing $VALIDATE_PRD" >&2; exit 8; }
python3 "$VALIDATE_PRD" "$PRD_PATH"
```

**blocshed-spec** fanout header as currently on disk (includes later `prd_io.py` refactor):

```bash
#!/usr/bin/env bash
set -euo pipefail
SLUG="${1:?slug required}"
BIN_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$BIN_DIR/.." && pwd)"
source "${BIN_DIR}/lib/build_issue_body.sh"
source "${BIN_DIR}/lib/task_map.sh"
PRD_PATH="${ROOT}/docs/prd/${SLUG}.md"
TOPOSORT="${BIN_DIR}/lib/toposort_tickets.py"
VALIDATE="${BIN_DIR}/lib/validate_tickets.py"
VALIDATE_PRD="${BIN_DIR}/lib/validate_prd_frontmatter.py"
REGISTRY_PATH="${ROOT}/docs/agents/repos.md"
[[ -f "$PRD_PATH" ]] || { echo "missing $PRD_PATH" >&2; exit 2; }
[[ -f "$VALIDATE_PRD" ]] || { echo "missing $VALIDATE_PRD" >&2; exit 8; }
PRD_IO="${BIN_DIR}/lib/prd_io.py"
[[ -f "$PRD_IO" ]] || { echo "missing $PRD_IO" >&2; exit 8; }
python3 "$VALIDATE_PRD" "$PRD_PATH"
PARENT_URL=$(python3 "$PRD_IO" get "$PRD_PATH" parent_issue)
[[ -n "$PARENT_URL" ]] || { echo "parent_issue empty in frontmatter" >&2; exit 3; }
```

Also reference `VALIDATE_PRD` in:

- `bin/feature-check` — line 28: `python3 "$VALIDATE_PRD" "$PRD_PATH" || exit 6`
- `bin/sync-fanout-bodies` — same variable path pattern

### Step 4 — Update `docs/prd/_template.md`

Append under the ticket example section:

```markdown
**YAML authoring:** Every ticket field must be indented under its `- id:` line. Run `python3 bin/lib/validate_prd_frontmatter.py docs/prd/<slug>.md` before fanout.
```

For `commit_message` in template table (OpenCode session edit):

```markdown
| `commit_message` | yes | One-line Conventional Commit subject. **Must be double-quoted in YAML** (value contains `:`). |
```

*(blocshed-spec template may later mark `commit_message` / `test_commands` deprecated at spec phase — downgrade PRD retains them from original slice.)*

### Step 5 — Update `skills/fanout-issues/SKILL.md`

Add precondition:

```markdown
2. `python3 bin/lib/validate_prd_frontmatter.py docs/prd/<slug>.md` passes.
```

### Step 6 — OpenCode `skills/to-prd/SKILL.md` (architect prevention)

Insert **before** scribe invoke step:

```markdown
5. **YAML frontmatter rules (mandatory before scribe):** Ticket fields under `tickets:` must stay **indented 4 spaces** under each `- id:` item (`repo`, `capability`, `commit_message`, etc. at the same level). **`commit_message` values that contain `:` must be double-quoted** (Conventional Commits always do). Quote `title` when it contains `:`. After composing, validate with `python3 bin/lib/validate_prd_frontmatter.py docs/prd/<slug>.md` — do not invoke scribe until it exits 0.
6. **Invoke `scribe`** to write `docs/prd/<slug>.md` ...
```

Renumber subsequent steps (Create GitHub issue → 7, Stop → 8).

### Step 7 — OpenCode `bin/stack/sync_spec_tooling.sh`

In the `sync_bin` loop, add:

```bash
sync_bin "$TEMPLATE/bin/lib/validate_prd_frontmatter.py" "$SPEC/bin/lib/validate_prd_frontmatter.py"
```

Place immediately after `validate_tickets.py` sync line.

Also copy into OpenCode template tree:

```
templates/spec-repo/bin/lib/validate_prd_frontmatter.py
templates/spec-repo/bin/fanout          # with validation gate
templates/spec-repo/docs/prd/_template.md
```

---

## Correct ticket frontmatter reference (copy-paste)

```yaml
tickets:
  - id: web-example
    repo: roborew/blocshed-web
    capability: Subscription/billing (Stripe)
    title: "Quote title when it contains :"
    owner: developer
    mode: afk
    depends_on: []
    commit_message: "feat(scope): always quote conventional commits"
    acceptance:
      - Plain outcome without colon
      - "Quote criteria that contain colons: like this"
    test_commands:
      - bin/rails test test/models/example_test.rb
    body: |
      Optional multiline description.
```

**Never** put `commit_message` at column 0. **Never** leave Conventional Commit subjects unquoted.

---

## First ticket after fix (actual on-disk excerpt)

```yaml
  - id: web-fix-billing-route
    repo: roborew/blocshed-web
    capability: Subscription/billing (Stripe)
    title: Fix billing route helper + active-only org quota
    owner: developer
    mode: afk
    depends_on: []
    commit_message: "fix(billing): correct at-limit route and count active-only org quota"
    acceptance:
      - Billing route helper renders correct path at publication limit
      - Organisation quota counts active publications only (archived_at IS NULL)
      - Existing tests pass
    test_commands:
      - bin/rails test test/models/organisation_test.rb
      - bin/rails test test/controllers/publications_controller_test.rb
    body: |
      Replace upgrade_workspace_subscriptions_path with manage_billing_organisation_subscriptions_path in _form.html.erb. Change Organisation#publication_count_across_workspaces to count archived_at IS NULL only.
```

---

## Files touched (summary)

### blocshed-spec (verified on disk)

| File | Change |
| --- | --- |
| `docs/prd/downgrade-archival-recovery.md` | Fixed YAML; added `capability` on 7 tickets |
| `bin/lib/validate_prd_frontmatter.py` | **Added** (full source above) |
| `bin/fanout` | `python3 "$VALIDATE_PRD" "$PRD_PATH"` before fanout |
| `bin/feature-check` | PRD validation gate |
| `bin/sync-fanout-bodies` | References `VALIDATE_PRD` |
| `docs/prd/_template.md` | YAML authoring note |
| `skills/fanout-issues/SKILL.md` | Validator precondition |

### OpenCode config (session edits — verify before merge)

| File | Change |
| --- | --- |
| `templates/spec-repo/bin/lib/validate_prd_frontmatter.py` | **Added** |
| `templates/spec-repo/bin/fanout` | PRD validation gate |
| `templates/spec-repo/docs/prd/_template.md` | Quoting + validation |
| `skills/to-prd/SKILL.md` | YAML rules + validate-before-scribe |
| `bin/stack/sync_spec_tooling.sh` | Sync validator |

---

## Operator rollout

```bash
cd /Users/robo/05_Repos/01_PROJECTS/apps/blocshed/blocshed-spec

python3 bin/lib/validate_prd_frontmatter.py docs/prd/downgrade-archival-recovery.md
bin/fanout downgrade-archival-recovery
```

Re-sync other spec repos from OpenCode templates if needed:

```bash
~/.config/opencode/bin/stack/sync_spec_tooling.sh /path/to/spec-repo
```

---

## Related issues (other sessions / docs)

| Topic | TO REVIEW doc |
| --- | --- |
| CRLF / `env: bash\r` on spec `bin/*` | `2026-05-19-crlf-line-endings-hardening.md` |
| Issue-backed orchestrate handoff | `2026-05-19-issue-backed-workflow-orchestrate-handoff.md` |
| Architect bash allow-by-default | `2026-06-01-setup-project-workflow-and-deepseek-bash-fixes.md` |
| Duplicate fanout tickets | Operational — fanout skips existing by title/`task_id` |
| `SPEC_REPO` markdown list parsing | `2026-06-01-spec-repo-markdown-parser.md` |
| Spec vs impl issue workflow split | `2026-05-19-spec-impl-issue-workflow-split.md` |

---

## Review checklist

- [ ] Chat date / filename: `2026-05-19` matches transcript `9abcbc8d-824c-4138-a692-e31a1cc4612d` creation time
- [ ] `python3 bin/lib/validate_prd_frontmatter.py docs/prd/downgrade-archival-recovery.md` → `ok (7 tickets)`
- [ ] Python YAML one-liner prints 7 ids with capabilities (no `MISSING`)
- [ ] `bin/fanout downgrade-archival-recovery` passes validation gate
- [ ] `validate_prd_frontmatter.py` present in spec repo + OpenCode template tree
- [ ] `to-prd` skill documents indent + quote rules

---

## Out of scope

- Rewriting historical GitHub issues from partial/duplicate fanout
- Scribe YAML validation (belongs in architect compose + fanout gate)
- Bulk migration of all PRDs in all spec repos
