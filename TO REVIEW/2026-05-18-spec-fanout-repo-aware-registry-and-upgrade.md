# 2026-05-18 — Spec fanout repo-aware registry, duplicate fixes, and upgrade script

**Cursor chat created:** 2026-05-18 (Monday 18 May 2026 — first user message timestamp 19:03 UTC+1)  
**Cursor chat ID:** `1666232b-1bf3-4586-8e2b-56a323ec6d7b`  
**Transcript:** `~/.cursor/projects/Users-robo-config-opencode/agent-transcripts/1666232b-1bf3-4586-8e2b-56a323ec6d7b/1666232b-1bf3-4586-8e2b-56a323ec6d7b.jsonl`  
**Filename date (`YYYY-MM-DD` prefix):** **2026-05-18** — matches **chat creation date** for `TO REVIEW/` sort order (not the day this markdown was last edited).

**Session scope:** Diagnose architect mis-routing in spec mode (API repo treated as generic backend, web repo as frontend), implement repo-role registry and validation across PRD/fanout/agent skills, harden `bin/fanout` against duplicate issues, add operator upgrade path (`bin/upgrade-spec-repo`), and document operator guidance for resetting a fresh feature backlog.

**Status:** Implemented and finalized in the 2026-05-18 chat. Changes may exist only in transcript/tool writes unless later synced via `setup-project` / `bin/stack/sync_spec_tooling.sh`. **Follow-up:** `TO REVIEW/2026-05-19-registry-migration-scribe-write-fixes.md` fixes migration overwrite on repeated sync; `TO REVIEW/2026-05-19-spec-impl-issue-workflow-split.md` evolves issue bodies to yaml + slim spec fanout.

**Example stack:** `blocshed-spec` → `roborew/blocshed-web`, `roborew/blocshed-api` — feature `downgrade-archival-recovery` (duplicate issues #66–#70 reported in chat).

---

## Executive summary

| Area | Outcome |
| --- | --- |
| Root cause | No durable repo topology; `repos: []` or legacy `name`/`role: target`; architect inferred roles from repo names |
| Registry | `docs/agents/repos.md` with `application_role`, `agent_owner`, `capabilities`, `non_goals` |
| PRD tickets | Required `capability` per ticket + **Architecture confirmation** section |
| Fanout | Idempotent skip by title/task_id; duplicate ticket guard; `validate_tickets.py` before create |
| Skills | `to-prd`, `fanout-issues`, `setup-skills`, `to-issues`, `architect` updated |
| Operator | `bin/upgrade-spec-repo` + `bin/lib/migrate_repos_registry.py` |

---

## Problem reported (verbatim context)

Architect in spec mode created duplicate GitHub child issues on `roborew/blocshed-web`:

- Duplicate title: two **"Billing UI: archived content management panel"** (#66 / #67)
- Mis-scoping: treated **API = generic backend**, **web = generic frontend**
- Product intent: **API** = content formatting + distribution; **web** = user-facing app (billing UI, admin)

---

## Solution design

```text
CONTEXT.md           → product vocabulary (grill-me)
docs/agents/repos.md → repo topology (setup-skills / scribe)
docs/prd/<slug>.md   → tickets: repo + capability
bin/fanout           → validated, idempotent GitHub child issues
```

---

## Files created or modified (OpenCode config repo)

| Path | Action |
| --- | --- |
| `templates/spec-repo/docs/agents/repos.md` | Schema + example + `repos: []` |
| `skills/setup-skills/templates/repos.md` | Copy template for setup |
| `templates/spec-repo/docs/prd/_template.md` | `capability` required; architecture section |
| `templates/spec-repo/bin/lib/validate_tickets.py` | **New** |
| `templates/spec-repo/bin/fanout` | Dedupe + registry validation + capability in meta |
| `templates/spec-repo/skills/fanout-issues/SKILL.md` | Architecture gate |
| `skills/to-prd/SKILL.md` | Architecture gate |
| `skills/to-prd/templates/prd.md` | Registry link |
| `skills/to-prd/templates/prd-issue.md` | Registry summary |
| `skills/setup-skills/SKILL.md` | Step D repo registry |
| `skills/setup-skills/templates/domain.md` | Pointer to repos.md |
| `skills/setup-skills/templates/agents-block.md` | Repo registry section |
| `skills/to-issues/SKILL.md` | Duplicate guard |
| `agents/architect.md` | Architecture gate bullets |
| `templates/spec-repo/README.md` | Workflow bootstrap |
| `.gitattributes` | `templates/spec-repo/bin/* text eol=lf` |
| `bin/upgrade-spec-repo` | **New** |
| `bin/lib/migrate_repos_registry.py` | **New** |
| `README.md` | `upgrade-spec-repo` usage blurb |

---

## Operator procedures

```bash
~/.config/opencode/bin/upgrade-spec-repo /path/to/spec-repo
~/.config/opencode/bin/upgrade-spec-repo --check-only /path/to/spec-repo
cd /path/to/spec-repo && bin/fanout <slug>
```

If registry has TBD placeholders: OpenCode **architect** → `Run setup-skills — complete docs/agents/repos.md`.

Fresh backlog after bad fanout (no work started): close duplicate/wrong issues → fix PRD/registry → `bin/fanout <slug>` (skips existing matches).

---

## Verification in chat

- `bash -n templates/spec-repo/bin/fanout`
- `python3 -m py_compile` on validate/migrate/toposort scripts
- `validate_tickets.py` rejects `non_goal` capability and unknown repo
- `migrate_repos_registry.py` migrates `name`/`role: target` → new schema

---

## Related TO REVIEW documents

| Date | Document |
| --- | --- |
| 2026-05-19 | `2026-05-19-registry-migration-scribe-write-fixes.md` — migration must not clobber partial registry |
| 2026-05-19 | `2026-05-19-spec-impl-issue-workflow-split.md` — yaml issue bodies; slim fanout meta |
| 2026-06-01 | `2026-06-01-spec-fanout-bin-tooling-and-prerequisites.md` — operator FAQ for fanout install |

---

## Appendix A — Recreation order (another AI)

1. Add `.gitattributes` line for `templates/spec-repo/bin/*`.
2. Write `templates/spec-repo/docs/agents/repos.md` and `skills/setup-skills/templates/repos.md`.
3. Write `templates/spec-repo/bin/lib/validate_tickets.py`.
4. Write or patch `templates/spec-repo/bin/fanout` (Appendix B.4).
5. Update `templates/spec-repo/docs/prd/_template.md`, `skills/to-prd/*`, `templates/spec-repo/skills/fanout-issues/SKILL.md`.
6. Patch `skills/setup-skills/SKILL.md`, `agents/architect.md`, `skills/to-issues/SKILL.md`, `templates/spec-repo/README.md` (Appendix C).
7. Write `bin/lib/migrate_repos_registry.py` and `bin/upgrade-spec-repo` (Appendix B.5–B.6).
8. Sync into live spec repo: `upgrade-spec-repo` or `bin/stack/sync_spec_tooling.sh`.

---

## Appendix B — Full source files (from chat transcript)

### B.1 `templates/spec-repo/docs/agents/repos.md`

```markdown
# Application repo registry

Agents **must** read this file before authoring PRD `tickets:` or running `bin/fanout`. Do **not** infer backend/frontend from repo names (`api`, `web`, etc.). Use **`application_role`**, **`capabilities`**, and **`non_goals`** here; use **`CONTEXT.md`** for product vocabulary only.

## Schema

Each entry under `repos:` describes one implementation repository.

| Field | Required | Description |
|-------|----------|-------------|
| `repo` | yes | Full GitHub repo `owner/name`. |
| `application_role` | yes | One-line product role (not "backend" unless that is the actual product meaning). |
| `agent_owner` | yes | Default orchestrate agent: `developer` or `frontend-dev`. |
| `capabilities` | yes | List of responsibilities this repo **owns**. Tickets should map here. |
| `non_goals` | no | Responsibilities explicitly **not** owned here; fanout warns on mismatch. |
| `integration_contracts` | no | How this repo talks to siblings (APIs, events, shared data). |
| `default_test_commands` | no | Suggested verification commands when PRD tickets omit `test_commands`. |

## Example

```yaml
repos:
  - repo: myorg/my-web
    application_role: User-facing web application
    agent_owner: frontend-dev
    capabilities:
      - billing UI
      - admin surfaces
      - archived content management UI
    non_goals:
      - content formatting pipeline
      - distribution APIs
    integration_contracts:
      - Consumes formatting/distribution API from myorg/my-api
    default_test_commands:
      - pnpm test

  - repo: myorg/my-api
    application_role: Content formatting and distribution service
    agent_owner: developer
    capabilities:
      - content formatting
      - distribution APIs
      - archive lifecycle backend
    non_goals:
      - web UI
      - billing screens
    integration_contracts:
      - Exposes HTTP APIs consumed by myorg/my-web
    default_test_commands:
      - go test ./...
```

## Consumer rules

1. **Before PRD ticket slicing:** Confirm every target repo is listed with filled `application_role` and `capabilities`. If empty or stale, run **`setup-skills`** or update this file via scribe before fanout.
2. **Before fanout:** Present the registry summary to the human and ask: "Is this architecture correct for this feature?" Block fanout when `repos:` is empty or a ticket repo is unknown.
3. **Per ticket:** Set `capability` to one entry from the target repo's `capabilities` list. `bin/fanout` validates repo membership and capability fit.
4. **Domain glossary:** `CONTEXT.md` defines terms; this file defines **topology** (which repo owns what).

---

repos: []

```

### B.2 `skills/setup-skills/templates/repos.md`

```markdown
# Application repo registry

Agents **must** read this file before authoring PRD `tickets:` or running `bin/fanout`. Do **not** infer backend/frontend from repo names (`api`, `web`, etc.). Use **`application_role`**, **`capabilities`**, and **`non_goals`** here; use **`CONTEXT.md`** for product vocabulary only.

## Schema

Each entry under `repos:` describes one implementation repository.

| Field | Required | Description |
|-------|----------|-------------|
| `repo` | yes | Full GitHub repo `owner/name`. |
| `application_role` | yes | One-line product role (not "backend" unless that is the actual product meaning). |
| `agent_owner` | yes | Default orchestrate agent: `developer` or `frontend-dev`. |
| `capabilities` | yes | List of responsibilities this repo **owns**. Tickets should map here. |
| `non_goals` | no | Responsibilities explicitly **not** owned here; fanout warns on mismatch. |
| `integration_contracts` | no | How this repo talks to siblings (APIs, events, shared data). |
| `default_test_commands` | no | Suggested verification commands when PRD tickets omit `test_commands`. |

## Consumer rules

1. **Before PRD ticket slicing:** Confirm every target repo is listed with filled `application_role` and `capabilities`. If empty or stale, run **`setup-skills`** or update this file via scribe before fanout.
2. **Before fanout:** Present the registry summary to the human and ask: "Is this architecture correct for this feature?" Block fanout when `repos:` is empty or a ticket repo is unknown.
3. **Per ticket:** Set `capability` to one entry from the target repo's `capabilities` list. `bin/fanout` validates repo membership and capability fit.
4. **Domain glossary:** `CONTEXT.md` defines terms; this file defines **topology** (which repo owns what).

---

repos: []

```

### B.3 `templates/spec-repo/bin/lib/validate_tickets.py`

```python
#!/usr/bin/env python3
"""Validate PRD tickets against docs/agents/repos.md registry.

Reads ticket JSON array on stdin; registry YAML path as first arg.
Prints validation errors to stderr and exits non-zero on failure.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

try:
    import yaml  # type: ignore
except ImportError:
    yaml = None


def load_registry(path: Path) -> list[dict]:
    text = path.read_text(encoding="utf-8")
    if yaml is not None:
        data = yaml.safe_load(text) or {}
        repos = data.get("repos") or []
        if isinstance(repos, list):
            return [r for r in repos if isinstance(r, dict)]
        return []

    # Minimal fallback when PyYAML unavailable: parse `repos:` block lines only
    repos: list[dict] = []
    current: dict | None = None
    list_key: str | None = None
    for raw in text.splitlines():
        line = raw.rstrip()
        if line.strip().startswith("#") or not line.strip():
            continue
        if re.match(r"^repos:\s*\[\]\s*$", line):
            return []
        m_repo = re.match(r"^\s*-\s*repo:\s*(.+)$", line)
        if m_repo:
            if current:
                repos.append(current)
            current = {"repo": m_repo.group(1).strip().strip('"').strip("'"), "capabilities": [], "non_goals": []}
            list_key = None
            continue
        if current is None:
            continue
        m_kv = re.match(r"^\s{4}(\w+):\s*(.+)$", line)
        if m_kv:
            key, val = m_kv.group(1), m_kv.group(2).strip().strip('"').strip("'")
            if key in ("capabilities", "non_goals", "default_test_commands", "integration_contracts"):
                list_key = key
                current.setdefault(key, [])
            else:
                current[key] = val
                list_key = None
            continue
        m_item = re.match(r"^\s{6}-\s+(.+)$", line)
        if m_item and list_key:
            current.setdefault(list_key, []).append(m_item.group(1).strip().strip('"').strip("'"))
    if current:
        repos.append(current)
    return repos


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s.strip().lower())


def capability_mismatch(capability: str, repo_entry: dict) -> str | None:
    caps = [norm(c) for c in repo_entry.get("capabilities") or []]
    non = [norm(c) for c in repo_entry.get("non_goals") or []]
    cap_n = norm(capability)
    if not cap_n:
        return None
    if cap_n in non:
        return f"capability '{capability}' is listed as non_goal for {repo_entry.get('repo')}"
    if caps and not any(cap_n == c or cap_n in c or c in cap_n for c in caps):
        return (
            f"capability '{capability}' not in declared capabilities for {repo_entry.get('repo')}: "
            + ", ".join(repo_entry.get("capabilities") or [])
        )
    return None


def main() -> None:
    if len(sys.argv) < 2:
        print("usage: validate_tickets.py <registry.md>", file=sys.stderr)
        sys.exit(1)
    registry_path = Path(sys.argv[1])
    tickets = json.load(sys.stdin)
    if not isinstance(tickets, list):
        print("tickets must be a JSON array", file=sys.stderr)
        sys.exit(1)

    if not registry_path.is_file():
        print(f"missing registry: {registry_path}", file=sys.stderr)
        sys.exit(4)

    registry = load_registry(registry_path)
    if not registry:
        print(
            "repo registry is empty (docs/agents/repos.md). "
            "Fill application_role and capabilities for each target repo before fanout.",
            file=sys.stderr,
        )
        sys.exit(5)

    by_repo = {r.get("repo"): r for r in registry if r.get("repo")}
    errors: list[str] = []

    for t in tickets:
        tid = t.get("id") or "<unknown>"
        repo = t.get("repo") or ""
        if not repo:
            errors.append(f"ticket {tid}: missing repo")
            continue
        entry = by_repo.get(repo)
        if not entry:
            errors.append(
                f"ticket {tid}: repo '{repo}' not in docs/agents/repos.md "
                f"(known: {', '.join(sorted(by_repo))})"
            )
            continue
        capability = t.get("capability") or t.get("role") or ""
        if not capability:
            errors.append(
                f"ticket {tid}: missing capability (must map to a declared repo capability)"
            )
            continue
        msg = capability_mismatch(capability, entry)
        if msg:
            errors.append(f"ticket {tid}: {msg}")
        owner = t.get("owner") or ""
        expected = entry.get("agent_owner") or ""
        if owner and expected and owner != expected:
            errors.append(
                f"ticket {tid}: owner '{owner}' differs from registry agent_owner '{expected}' for {repo}"
            )

    if errors:
        for e in errors:
            print(e, file=sys.stderr)
        sys.exit(6)

    print("ok")


if __name__ == "__main__":
    main()

```

### B.4 `templates/spec-repo/bin/fanout` (complete file as implemented 2026-05-18)

```bash
#!/usr/bin/env bash
# Create child issues from PRD frontmatter (run inside spec repo).
# Prefers `tickets` (multiple issues per repo); falls back to legacy `slices`.
set -euo pipefail
SLUG="${1:?slug required}"
BIN_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$BIN_DIR/.." && pwd)"
PRD_PATH="${ROOT}/docs/prd/${SLUG}.md"
TOPOSORT="${BIN_DIR}/lib/toposort_tickets.py"
VALIDATE="${BIN_DIR}/lib/validate_tickets.py"
REGISTRY_PATH="${ROOT}/docs/agents/repos.md"
[[ -f "$PRD_PATH" ]] || { echo "missing $PRD_PATH" >&2; exit 2; }
PARENT_URL=$(yq -r '.parent_issue // ""' "$PRD_PATH")
[[ -n "$PARENT_URL" ]] || { echo "parent_issue empty in frontmatter" >&2; exit 3; }

validate_tickets_against_registry() {
  local tickets_json="$1"
  [[ -f "$VALIDATE" ]] || { echo "missing $VALIDATE" >&2; exit 8; }
  echo "$tickets_json" | python3 "$VALIDATE" "$REGISTRY_PATH"
}

existing_issue_number() {
  local repo="$1" title="$2" task_id="${3:-}"
  gh issue list \
    --repo "$repo" \
    --state all \
    --label "feature:${SLUG}" \
    --limit 200 \
    --json number,title,body 2>/dev/null \
    | jq -r --arg title "$title" --arg task_id "$task_id" '
        .[]
        | select(
            .title == $title
            or (
              $task_id != ""
              and ((.body // "") | contains("\"task_id\":\"" + $task_id + "\""))
            )
          )
        | .number
      ' \
    | sed -n '1p'
}

fanout_legacy_slices() {
  if [[ ! -s "$REGISTRY_PATH" ]] || yq -e '.repos | length == 0' "$REGISTRY_PATH" >/dev/null 2>&1; then
    echo "docs/agents/repos.md has no repo entries; fill application_role and capabilities before fanout" >&2
    exit 5
  fi
  while IFS= read -r KEY; do
    [[ -z "$KEY" ]] && continue
    if ! yq -e --arg r "$KEY" '.repos[] | select(.repo == $r)' "$REGISTRY_PATH" >/dev/null 2>&1; then
      echo "legacy slice repo '${KEY}' not in docs/agents/repos.md" >&2
      exit 9
    fi
    TITLE=$(yq -r ".slices[\"${KEY}\"].title // \"\"" "$PRD_PATH")
    BODY=$(yq -r ".slices[\"${KEY}\"].body // \"\"" "$PRD_PATH")
    [[ -n "$TITLE" ]] || { echo "missing title for slice ${KEY}" >&2; exit 4; }
    EXISTING=$(existing_issue_number "$KEY" "$TITLE")
    if [[ -n "$EXISTING" ]]; then
      echo "Skipping existing #${EXISTING} on ${KEY}"
      continue
    fi
    META_JSON=$(jq -nc \
      --arg tid "legacy-$(echo "$KEY" | tr '/' '-')" \
      --arg owner "developer" \
      --arg cm "chore: slice for ${SLUG}" \
      --argjson acc '["See issue body"]' \
      --argjson tc '["See repository README for test commands"]' \
      '{task_id:$tid,depends_on:[],owner:$owner,commit_message:$cm,acceptance:$acc,test_commands:$tc}')
    ISSUE_BODY="$(build_issue_body "$PARENT_URL" "$SLUG" "$META_JSON" "**Blocked by:** (none)" "$BODY")"
    gh issue create \
      --repo "$KEY" \
      --title "$TITLE" \
      --body "$ISSUE_BODY" \
      --label "feature:${SLUG},state:ready-for-agent,mode:afk,category:feature"
    echo "Created child on ${KEY}"
  done < <(yq -r '.slices | keys | .[]' "$PRD_PATH")
}

build_issue_body() {
  local parent="$1" slug="$2" meta_json="$3" blocked_line="$4" extra_md="$5"
  cat <<EOF
Parent PRD: ${parent}

## OpenCode task (machine-readable)
\`\`\`opencode-task-json
${meta_json}
\`\`\`

${blocked_line}

## Description

${extra_md}

---
Branch suggestion: feature/${slug}
EOF
}

fanout_tickets() {
  [[ -f "$TOPOSORT" ]] || { echo "missing $TOPOSORT" >&2; exit 6; }
  local TMP
  TMP=$(mktemp)
  yq -o=json '.tickets' "$PRD_PATH" >"$TMP"
  DUPES=$(jq -r '
    [
      (group_by(.id)[] | select(length > 1) | "duplicate ticket id: " + (.[0].id // "")),
      (group_by([.repo, .title])[] | select(length > 1) | "duplicate ticket title in repo " + (.[0].repo // "") + ": " + (.[0].title // ""))
    ]
    | .[]
  ' "$TMP")
  if [[ -n "$DUPES" ]]; then
    echo "$DUPES" >&2
    rm -f "$TMP"
    exit 7
  fi
  validate_tickets_against_registry "$(cat "$TMP")"
  declare -A TASK_TO_NUM=()
  while IFS= read -r TID; do
    [[ -z "$TID" ]] && continue
    REPO=$(jq -r --arg id "$TID" '.[] | select(.id==$id) | .repo' "$TMP")
    TITLE=$(jq -r --arg id "$TID" '.[] | select(.id==$id) | .title' "$TMP")
    CAPABILITY=$(jq -r --arg id "$TID" '.[] | select(.id==$id) | (.capability // .role // "")' "$TMP")
    OWNER=$(jq -r --arg id "$TID" '.[] | select(.id==$id) | .owner' "$TMP")
    MODE=$(jq -r --arg id "$TID" '.[] | select(.id==$id) | (.mode // "afk")' "$TMP")
    CM=$(jq -r --arg id "$TID" '.[] | select(.id==$id) | .commit_message' "$TMP")
    ACC=$(jq -c --arg id "$TID" '.[] | select(.id==$id) | (.acceptance // [])' "$TMP")
    TC=$(jq -c --arg id "$TID" '.[] | select(.id==$id) | (.test_commands // [])' "$TMP")
    EXTRA=$(jq -r --arg id "$TID" '.[] | select(.id==$id) | (.body // "")' "$TMP")
    DEPS=$(jq -c --arg id "$TID" '.[] | select(.id==$id) | (.depends_on // [])' "$TMP")

    local BLOCKED_LINE=""
    local DEP_ISSUES=()
    while IFS= read -r dep_id; do
      [[ -z "$dep_id" ]] && continue
      local n="${TASK_TO_NUM[$dep_id]:-}"
      if [[ -n "$n" ]]; then
        DEP_ISSUES+=("#$n")
      fi
    done < <(echo "$DEPS" | jq -r '.[]?')

    if [[ ${#DEP_ISSUES[@]} -gt 0 ]]; then
      BLOCKED_LINE="**Blocked by:** $(IFS=', '; echo "${DEP_ISSUES[*]}")"
    else
      BLOCKED_LINE="**Blocked by:** (none)"
    fi

    META_JSON=$(jq -nc \
      --arg tid "$TID" \
      --arg owner "$OWNER" \
      --arg capability "$CAPABILITY" \
      --arg cm "$CM" \
      --argjson acc "$ACC" \
      --argjson tc "$TC" \
      --argjson deps "$DEPS" \
      '{task_id:$tid,depends_on:$deps,owner:$owner,capability:$capability,commit_message:$cm,acceptance:$acc,test_commands:$tc}')

    ISSUE_BODY="$(build_issue_body "$PARENT_URL" "$SLUG" "$META_JSON" "$BLOCKED_LINE" "$EXTRA")"

    MODE_LABEL="mode:afk"
    [[ "${MODE}" == "hitl" ]] && MODE_LABEL="mode:hitl"

    EXISTING=$(existing_issue_number "$REPO" "$TITLE" "$TID")
    if [[ -n "$EXISTING" ]]; then
      TASK_TO_NUM["$TID"]="$EXISTING"
      echo "Skipping existing #${EXISTING} on $REPO ($TID)"
      continue
    fi

    URL=$(gh issue create \
      --repo "$REPO" \
      --title "$TITLE" \
      --body "$ISSUE_BODY" \
      --label "feature:${SLUG},state:ready-for-agent,${MODE_LABEL},category:feature" \
      --json url -q .url)
    NUM=$(echo "$URL" | sed -E 's#.*/issues/##')
    TASK_TO_NUM["$TID"]="$NUM"
    echo "Created #${NUM} on $REPO ($TID)"
  done < <(python3 "$TOPOSORT" <"$TMP")
  rm -f "$TMP"
}

TICKET_COUNT=$(yq '.tickets // [] | length' "$PRD_PATH")
if [[ "${TICKET_COUNT}" -gt 0 ]]; then
  fanout_tickets
else
  fanout_legacy_slices
fi

```

### B.5 `bin/lib/migrate_repos_registry.py` (initial version from 2026-05-18 chat)

> **Warning:** Later fixed in `2026-05-19-registry-migration-scribe-write-fixes.md` — do not rewrite registry on every sync when entries still contain `TBD`. Use the fixed version from that doc if present in tree.

```python
#!/usr/bin/env python3
"""Migrate docs/agents/repos.md to the repo-aware registry schema."""
from __future__ import annotations

import re
import sys
from pathlib import Path

try:
    import yaml  # type: ignore
except ImportError:
    yaml = None

HEADER = """# Application repo registry

Agents **must** read this file before authoring PRD `tickets:` or running `bin/fanout`. Do **not** infer backend/frontend from repo names (`api`, `web`, etc.). Use **`application_role`**, **`capabilities`**, and **`non_goals`** here; use **`CONTEXT.md`** for product vocabulary only.

## Schema

See the OpenCode config template `templates/spec-repo/docs/agents/repos.md` for field definitions.

## Consumer rules

1. **Before PRD ticket slicing:** Confirm every target repo is listed with filled `application_role` and `capabilities`.
2. **Before fanout:** Confirm this registry matches the feature. `bin/fanout` blocks when entries are incomplete.
3. **Per ticket:** Set `capability` to one entry from the target repo's `capabilities` list.
4. **Domain glossary:** `CONTEXT.md` defines terms; this file defines **topology**.

---

"""


def split_registry(path: Path) -> tuple[str, list[dict]]:
    text = path.read_text(encoding="utf-8")
    marker = "\nrepos:"
    idx = text.rfind(marker)
    if idx == -1:
        return text, []
    header = text[: idx + 1]
    body = text[idx + len(marker) :].lstrip()
    if yaml is None:
        return header, _parse_repos_minimal(body)
    data = yaml.safe_load(body) or []
    if isinstance(data, list):
        return header, [r for r in data if isinstance(r, dict)]
    return header, []


def _parse_repos_minimal(body: str) -> list[dict]:
    repos: list[dict] = []
    current: dict | None = None
    list_key: str | None = None
    for raw in body.splitlines():
        line = raw.rstrip()
        if not line.strip() or line.strip().startswith("#"):
            continue
        if re.match(r"^\[\]\s*$", line.strip()):
            return []
        m_repo = re.match(r"^\s*-\s*repo:\s*(.+)$", line)
        m_name = re.match(r"^\s*-\s*name:\s*(.+)$", line)
        if m_repo or m_name:
            if current:
                repos.append(current)
            key = "repo" if m_repo else "name"
            val = (m_repo or m_name).group(1).strip().strip('"').strip("'")
            current = {key: val}
            list_key = None
            continue
        if current is None:
            continue
        m_kv = re.match(r"^\s{4}(\w+):\s*(.+)$", line)
        if m_kv:
            key, val = m_kv.group(1), m_kv.group(2).strip().strip('"').strip("'")
            if key in ("capabilities", "non_goals", "default_test_commands", "integration_contracts"):
                list_key = key
                current.setdefault(key, [])
            else:
                current[key] = val
                list_key = None
            continue
        m_item = re.match(r"^\s{6}-\s+(.+)$", line)
        if m_item and list_key:
            current.setdefault(list_key, []).append(m_item.group(1).strip().strip('"').strip("'"))
    if current:
        repos.append(current)
    return repos


def infer_defaults(repo: str) -> dict:
    base = repo.split("/")[-1].lower()
    if any(x in base for x in ("web", "frontend", "ui", "app")):
        return {
            "application_role": "TBD — user-facing application (confirm in setup-skills)",
            "agent_owner": "frontend-dev",
            "capabilities": ["TBD — add capabilities in setup-skills"],
            "non_goals": [],
        }
    if any(x in base for x in ("api", "service", "worker", "backend", "server")):
        return {
            "application_role": "TBD — service/API role (confirm — not necessarily generic backend)",
            "agent_owner": "developer",
            "capabilities": ["TBD — add capabilities in setup-skills"],
            "non_goals": [],
        }
    return {
        "application_role": "TBD — describe this repo's product role in setup-skills",
        "agent_owner": "developer",
        "capabilities": ["TBD — add capabilities in setup-skills"],
        "non_goals": [],
    }


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


def normalize_entry(raw: dict) -> dict:
    repo = raw.get("repo") or raw.get("name") or ""
    if not repo:
        return raw
    out = {"repo": repo}
    defaults = infer_defaults(repo)
    for key in ("application_role", "agent_owner", "capabilities", "non_goals", "integration_contracts", "default_test_commands"):
        if key in raw and raw[key] not in (None, "", []):
            out[key] = raw[key]
        elif key in defaults:
            out[key] = defaults[key]
    if "role" in raw and raw["role"] == "target" and "application_role" not in out:
        out["application_role"] = defaults["application_role"]
    if "agent_owner" not in out:
        out["agent_owner"] = defaults["agent_owner"]
    if "capabilities" not in out or not out["capabilities"]:
        out["capabilities"] = defaults["capabilities"]
    if "non_goals" not in out:
        out["non_goals"] = []
    return out


def write_registry(path: Path, repos: list[dict]) -> None:
    if yaml is not None:
        yaml_body = yaml.safe_dump(repos, sort_keys=False, allow_unicode=True).rstrip()
    else:
        lines = ["repos:"]
        for r in repos:
            lines.append(f"  - repo: {r['repo']}")
            for key in ("application_role", "agent_owner"):
                if key in r:
                    lines.append(f"    {key}: {r[key]}")
            for list_key in ("capabilities", "non_goals", "integration_contracts", "default_test_commands"):
                if r.get(list_key):
                    lines.append(f"    {list_key}:")
                    for item in r[list_key]:
                        lines.append(f"      - {item}")
        yaml_body = "\n".join(lines)
    path.write_text(HEADER + yaml_body + "\n", encoding="utf-8")


def main() -> None:
    if len(sys.argv) < 2:
        print("usage: migrate_repos_registry.py <repos.md> [--check-only]", file=sys.stderr)
        sys.exit(2)
    path = Path(sys.argv[1])
    check_only = "--check-only" in sys.argv[2:]
    if not path.is_file():
        print(f"missing {path}", file=sys.stderr)
        sys.exit(1)

    _, repos = split_registry(path)
    if not repos:
        print("INCOMPLETE: repos list is empty")
        sys.exit(3)

    needs_migration = any("name" in r and "repo" not in r for r in repos) or any(
        not is_complete(normalize_entry(r)) for r in repos
    )

    if check_only:
        incomplete = [r.get("repo") or r.get("name") for r in repos if not is_complete(normalize_entry(r))]
        if incomplete:
            print("INCOMPLETE: " + ", ".join(str(x) for x in incomplete if x))
            sys.exit(3)
        print("ok")
        sys.exit(0)

    normalized = [normalize_entry(r) for r in repos]
    # Deduplicate by repo
    seen: set[str] = set()
    unique: list[dict] = []
    for r in normalized:
        repo = r.get("repo")
        if not repo or repo in seen:
            continue
        seen.add(repo)
        unique.append(r)

    if needs_migration or path.read_text(encoding="utf-8") != HEADER + (yaml.safe_dump(unique, sort_keys=False) if yaml else ""):
        backup = path.with_suffix(path.suffix + ".bak")
        if not backup.exists():
            backup.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
        write_registry(path, unique)
        print(f"migrated {path} ({len(unique)} repos)")
    else:
        print(f"no migration needed for {path}")

    incomplete = [r["repo"] for r in unique if not is_complete(r)]
    if incomplete:
        print("INCOMPLETE: " + ", ".join(incomplete))
        sys.exit(3)


if __name__ == "__main__":
    main()

```

### B.6 `bin/upgrade-spec-repo`

```bash
#!/usr/bin/env bash
# Sync repo-aware fanout tooling into an existing application spec repo.
#
# Usage:
#   upgrade-spec-repo [path-to-spec-repo]
#   upgrade-spec-repo --check-only [path-to-spec-repo]
#
# Defaults to the current directory when it looks like a spec repo.
# After the script runs, if the registry still has TBD placeholders, open
# OpenCode in the spec repo and tell architect: "Run setup-skills — complete docs/agents/repos.md."
set -euo pipefail

OC="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="${OC}/templates/spec-repo"
MIGRATE="${OC}/bin/lib/migrate_repos_registry.py"
CHECK_ONLY=false
SPEC=""

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --check-only) CHECK_ONLY=true; shift ;;
    -*) echo "unknown option: $1" >&2; usage 1 ;;
    *)
      SPEC="$1"
      shift
      ;;
  esac
done

if [[ -z "$SPEC" ]]; then
  SPEC="$(pwd)"
fi

SPEC="$(cd "$SPEC" && pwd)"

if [[ ! -d "$TEMPLATE" ]]; then
  echo "ERROR: missing OpenCode template at $TEMPLATE" >&2
  exit 1
fi

if [[ ! -d "$SPEC/docs/prd" && ! -f "$SPEC/docs/agents/repos.md" ]]; then
  echo "ERROR: $SPEC does not look like a spec repo (expected docs/prd/ or docs/agents/repos.md)" >&2
  exit 1
fi

echo "==> Spec repo: $SPEC"
echo "==> OpenCode config: $OC"

if [[ "$CHECK_ONLY" == "true" ]]; then
  REGISTRY="$SPEC/docs/agents/repos.md"
  [[ -f "$REGISTRY" ]] || { echo "INCOMPLETE: missing $REGISTRY"; exit 3; }
  python3 "$MIGRATE" "$REGISTRY" --check-only
  VALIDATE="$SPEC/bin/lib/validate_tickets.py"
  if [[ -f "$VALIDATE" ]]; then
    shopt -s nullglob
    for prd in "$SPEC"/docs/prd/*.md; do
      [[ "$(basename "$prd")" == "_template.md" ]] && continue
      count=$(yq '.tickets // [] | length' "$prd" 2>/dev/null || echo 0)
      [[ "${count:-0}" -gt 0 ]] || continue
      slug=$(yq -r '.slug // ""' "$prd" 2>/dev/null || basename "$prd" .md)
      echo "--> validating tickets in $slug"
      yq -o=json '.tickets' "$prd" | python3 "$VALIDATE" "$REGISTRY" || exit 6
    done
  fi
  echo "==> check-only: ok"
  exit 0
fi

mkdir -p "$SPEC/bin/lib" "$SPEC/skills/fanout-issues" "$SPEC/docs/agents" "$SPEC/docs/prd"

echo "==> Syncing tooling from template..."
install -m0755 "$TEMPLATE/bin/fanout" "$SPEC/bin/fanout"
install -m0755 "$TEMPLATE/bin/lib/validate_tickets.py" "$SPEC/bin/lib/validate_tickets.py"
install -m0755 "$TEMPLATE/bin/lib/toposort_tickets.py" "$SPEC/bin/lib/toposort_tickets.py"
[[ -f "$TEMPLATE/bin/status" ]] && install -m0755 "$TEMPLATE/bin/status" "$SPEC/bin/status"
[[ -f "$TEMPLATE/bin/new-prd" ]] && install -m0755 "$TEMPLATE/bin/new-prd" "$SPEC/bin/new-prd"
cp "$TEMPLATE/docs/prd/_template.md" "$SPEC/docs/prd/_template.md"
cp "$TEMPLATE/skills/fanout-issues/SKILL.md" "$SPEC/skills/fanout-issues/SKILL.md"

REGISTRY="$SPEC/docs/agents/repos.md"
if [[ ! -f "$REGISTRY" ]]; then
  cp "$TEMPLATE/docs/agents/repos.md" "$REGISTRY"
  echo "==> Created $REGISTRY from template"
fi

echo "==> Migrating repo registry (if needed)..."
python3 "$MIGRATE" "$REGISTRY" || REGISTRY_INCOMPLETE=true
REGISTRY_INCOMPLETE="${REGISTRY_INCOMPLETE:-false}"

echo "==> Validating PRD tickets (if any)..."
PRD_ERRORS=0
if command -v yq >/dev/null 2>&1; then
  shopt -s nullglob
  for prd in "$SPEC"/docs/prd/*.md; do
    base=$(basename "$prd")
    [[ "$base" == "_template.md" ]] && continue
    count=$(yq '.tickets // [] | length' "$prd" 2>/dev/null || echo 0)
    [[ "${count:-0}" -gt 0 ]] || continue
    slug=$(yq -r '.slug // ""' "$prd" 2>/dev/null)
    [[ -n "$slug" && "$slug" != "null" ]] || slug="${base%.md}"
    echo "    docs/prd/${slug}.md"
    if ! yq -o=json '.tickets' "$prd" | python3 "$SPEC/bin/lib/validate_tickets.py" "$REGISTRY"; then
      PRD_ERRORS=$((PRD_ERRORS + 1))
    fi
  done
else
  echo "WARN: yq not installed — skipped PRD ticket validation (brew install yq)" >&2
fi

echo ""
echo "========================================"
if [[ "$REGISTRY_INCOMPLETE" == "true" || "$PRD_ERRORS" -gt 0 ]]; then
  echo "Upgrade synced, but manual step required."
  echo ""
  if [[ "$REGISTRY_INCOMPLETE" == "true" ]]; then
    echo "1. Registry incomplete — fill docs/agents/repos.md (application_role + capabilities per repo)."
  fi
  if [[ "$PRD_ERRORS" -gt 0 ]]; then
    echo "2. Fix PRD tickets: each ticket needs repo + capability matching the registry."
  fi
  echo ""
  echo "OpenCode (recommended):"
  echo "  cd \"$SPEC\" && opencode"
  echo "  # In architect, say:"
  echo "  #   Run setup-skills — complete docs/agents/repos.md for each implementation repo."
  echo "  #   Do not infer backend/frontend from repo names."
  echo ""
  echo "Re-check when done:"
  echo "  \"$OC/bin/upgrade-spec-repo\" --check-only \"$SPEC\""
  exit 3
fi

echo "Upgrade complete — registry and PRD tickets validate."
echo ""
echo "Optional commit:"
echo "  cd \"$SPEC\" && git add bin/ docs/ skills/ && git status"
echo ""
echo "Fanout when ready:"
echo "  cd \"$SPEC\" && bin/fanout <slug>"

```

### B.7 `templates/spec-repo/docs/prd/_template.md`

```markdown
---
slug: example-feature
parent_issue: ""
# Repos touched by this PRD — must be subset of docs/agents/repos.md entries
target_repos: []
# Primary: ordered implementation tickets (multiple per repo allowed).
# Each ticket becomes one GitHub child issue with labels feature:<slug>, category:feature, mode:*, state:ready-for-agent.
tickets: []
# Legacy: one slice per repo (owner/repo key). Used only if `tickets` is empty.
slices: {}
---

# PRD: <feature name>

## Problem statement

## Proposed solution

## User stories

- As <role>, I want <capability>, so that <outcome>.

## Implementation decisions

## Testing decisions

## Out of scope

## Open questions

## Linked artifacts

- Research: `.research/<slug>.md`
- Prototype: `docs/prototypes/<slug>/` (optional design artifact)
- ADRs: `docs/adr/`
- CONTEXT: `CONTEXT.md`
- Repo registry: `docs/agents/repos.md`

## Architecture confirmation

Before fanout, confirm target repos and roles match `docs/agents/repos.md`. Do not slice tickets until the human approves the registry summary for this feature.

## Tickets (frontmatter)

Define work as **`tickets`** (recommended). `bin/fanout <slug>` creates **one GitHub issue per ticket**, in dependency order, and embeds machine-readable metadata for orchestrate.

Each ticket object:

| Field | Required | Description |
|-------|----------|-------------|
| `id` | yes | Stable unique id, e.g. `api-org-model` (used in `depends_on` and rerun dedupe). |
| `repo` | yes | Full GitHub repo `owner/name` (must match `docs/agents/repos.md`). |
| `capability` | yes | One responsibility from that repo's `capabilities` list in `docs/agents/repos.md`. |
| `title` | yes | Issue title. Must be unique within the target repo for this PRD. |
| `owner` | yes | `developer` or `frontend-dev` (should match registry `agent_owner` for the repo). |
| `mode` | no | `afk` or `hitl` → label `mode:afk` / `mode:hitl` (default `afk`). |
| `depends_on` | no | List of ticket `id` values that must be merged/closed before this ticket is runnable; fanout resolves them to **Blocked by: #n** lines. |
| `commit_message` | yes | One-line Conventional Commit subject for the single commit after this issue is done. |
| `acceptance` | yes | List of acceptance criteria strings. |
| `test_commands` | yes | List of shell commands to run for verification (e.g. `pnpm test path/to/file.test.ts`). |
| `body` | no | Extra markdown appended under **Description** in the issue body. |

Example (YAML under frontmatter `tickets:`):

```yaml
tickets:
  - id: api-format-pipeline
    repo: myorg/my-api
    capability: content formatting
    title: "Formatting: archive payload normalisation"
    owner: developer
    mode: afk
    depends_on: []
    commit_message: "feat(api): normalise archive payloads"
    acceptance:
      - Archive payloads are normalised before storage
    test_commands:
      - go test ./internal/format/...

  - id: web-billing-archive-panel
    repo: myorg/my-web
    capability: archived content management UI
    title: "Billing UI: archived content management panel"
    owner: frontend-dev
    mode: hitl
    depends_on: [api-format-pipeline]
    commit_message: "feat(ui): archived content panel"
    acceptance:
      - Admin can list archived items from the distribution API
    test_commands:
      - pnpm test src/features/archive-panel.test.tsx
```

If `tickets` is empty, fanout falls back to legacy **`slices`** (one issue per `owner/repo` key).

```

### B.8 `skills/to-prd/SKILL.md`

```markdown
---
name: to-prd
description: "Synthesise a PRD from grill-me / research context, write docs/prd/<slug>.md, publish a GitHub issue with prd + state:ready-for-agent + feature:<slug>. Halt after publish — do not invoke to-issues."
modelTier: "smart"
roleReminder: "Run after grill-me when the feature is understood. Scribe writes files; primary uses gh for the issue only if bash is allowed, else delegate."
---

# To PRD

Publish a **human-reviewable PRD** before vertical slicing. This closes the gap where `.plan` is internal-only.

## Preconditions

- `gh` CLI authenticated (`gh auth status`).
- Current repo is the **spec repo** or the repo where PRDs live (`docs/prd/` exists or will be created).
- **`docs/agents/repos.md`** must list every target implementation repo with `application_role`, `agent_owner`, and `capabilities`. If empty or incomplete, run **`setup-skills`** or update the registry via scribe **before** drafting PRD tickets.
- Optional: `.research/<slug>.md` from the `research` skill — load and cite in **Linked artifacts**.
- Optional: **`CONTEXT.md`** for product vocabulary (terms only — repo topology lives in `docs/agents/repos.md`).

## Behaviour

1. **Architecture gate:** Read `docs/agents/repos.md`. Present a summary table: repo, `application_role`, key `capabilities`, `non_goals`. Ask: **"Is this architecture correct for this feature?"** If `repos:` is empty or a needed repo is missing, stop and collect roles/capabilities from the user (via scribe update to `docs/agents/repos.md`) before continuing.
2. **Inputs:** feature name, kebab-case `<slug>`, and any user/stakeholder notes from the session.
3. **Compose** the PRD body using `skills/to-prd/templates/prd.md` — all sections must be present (use `TBD` only where the human must fill later; prefer concrete content from the session). Include **Architecture confirmation** referencing the registry.
4. **Draft tickets (when slicing in same session):** Each ticket must include `repo`, **`capability`** (from that repo's registry entry), `title`, `owner` (match registry `agent_owner` unless justified), plus acceptance and test commands. **Do not** assign work by inferring backend/frontend from repo names (`api` ≠ generic backend, `web` ≠ generic frontend).
5. **Invoke `scribe`** to write `docs/prd/<slug>.md` with the full markdown (verbatim template structure including frontmatter).
6. **Create GitHub issue** in `$(gh repo view --json nameWithOwner -q .nameWithOwner)`:
   - Title: `[PRD] <slug>: <one-line summary>`
   - Body: use `skills/to-prd/templates/prd-issue.md` filled with the same sections (or link to `docs/prd/<slug>.md` path in repo + paste summary).
   - Labels (create with `gh label create` if missing, then apply):
     - `prd`
     - `state:ready-for-agent` (if your org uses `state:ready` instead, match `docs/agents/triage-labels.md`)
     - `feature:<slug>`
7. **Stop.** Tell the user: "PRD published — **human review required**. Do not run fanout until you approve the PRD, ticket repo/capability mapping, and PRD issue body."

## Hard rules

- **Do not** invoke `to-issues`, `fanout`, or orchestrate from this skill.
- **Scribe** is the only writer for `docs/prd/*.md` and `docs/agents/repos.md`.
- **Do not** infer repo responsibilities from names or folder layout; use `docs/agents/repos.md`.
- If `docs/prd/` is missing, scribe creates the directory by writing the file path.

## Label fallbacks

If `state:ready-for-agent` does not exist, use the canonical state label from `docs/agents/triage-labels.md` for "AFK agent can pick up" and note the substitution in the reply.

```

### B.9 `templates/spec-repo/skills/fanout-issues/SKILL.md`

```markdown
---
name: fanout-issues
description: "Cross-repo companion to to-prd: after PRD frontmatter is filled, run bin/fanout <slug> from this spec repo to create child GitHub issues (one per ticket or legacy slice)."
modelTier: "fast"
roleReminder: "Operates in the application spec repo; uses gh + yq."
---

# Fanout issues

## When

`docs/prd/<slug>.md` has valid YAML frontmatter with **`tickets:`** (preferred) or legacy **`slices:`**, plus `parent_issue` and `target_repos` as defined in `docs/prd/_template.md`.

## Preconditions (architecture gate)

1. Read **`docs/agents/repos.md`**. Every ticket `repo` must appear in the registry with `application_role` and `capabilities`.
2. Present the registry summary to the human: repo, role, capabilities, non_goals.
3. Ask: **"Is this architecture correct for this feature?"** Do not run fanout until confirmed or the registry is updated.
4. Each ticket must include **`capability`** mapping to a declared capability for that repo. Do not infer backend/frontend from repo names.

## How

From this repo root:

```bash
bin/fanout <slug>
```

`bin/fanout` validates tickets against the registry (`bin/lib/validate_tickets.py`) before creating issues.

## Rules

### `tickets:` (preferred)

- Each ticket row becomes **one** child issue in the repo named by `repo` (full `owner/repo` matching `docs/agents/repos.md`).
- Each ticket must include **`capability`** (or legacy `role`) aligned with that repo's registry entry.
- Issues are created in **dependency order** (`depends_on` task ids).
- Labels include `feature:<slug>`, `state:ready-for-agent`, `mode:afk` or `mode:hitl`, and `category:feature`.
- The issue body embeds fenced **`opencode-task-json`** metadata (task id, capability, acceptance, `test_commands`, `commit_message`, etc.) plus human-readable sections.
- Fanout is idempotent: before creating an issue, `bin/fanout` checks all existing issues with `feature:<slug>` in the target repo and skips a match by exact title or embedded `task_id`.
- The PRD must not contain duplicate ticket ids or duplicate `(repo, title)` pairs; fix the PRD instead of publishing repeated child issues.
- Fanout **fails** when: registry is empty, ticket repo is unknown, capability is missing, capability matches a `non_goal`, or `owner` disagrees with registry `agent_owner`.

### Legacy `slices:`

- Each slice key must be a **full** `owner/repo` string matching `docs/agents/repos.md`.
- One broad issue per repo (same label set where applicable).

```

---

## Appendix C — Incremental patches (not full files)

### `agents/architect.md` — add after repos.md bullet (Default guidance)

```markdown
- **Spec repo architecture gate:** Before PRD ticket slicing or fanout, read `docs/agents/repos.md` for each target repo's `application_role`, `capabilities`, and `non_goals`. Present the summary and ask the human to confirm. **Never** infer backend/frontend from repo names (`api`, `web`, etc.). Use the registry first, `CONTEXT.md` for vocabulary second. If `repos:` is empty or incomplete, run **`setup-skills`** or update the registry via scribe before creating tickets.
```

### `agents/architect.md` — Product Feature line

Replace:

```markdown
- **Product Feature / PRD** (front-door option 1) → complete `grill-me`, then load `to-prd`. Human reviews the PRD before `fanout`.
```

With:

```markdown
- **Product Feature / PRD** (front-door option 1) → complete `grill-me`, then load `to-prd`. Confirm `docs/agents/repos.md` architecture before ticket slicing. Human reviews the PRD before `fanout`.
```


### `skills/to-issues/SKILL.md` — insert before "For each approved slice"

```markdown
Before publishing, run a duplicate guard:

- List existing issues for the same feature/plan slug in the target repo (`gh issue list --state all --label "feature:<slug>" --json number,title,body` when a feature label exists).
- Do not create a new issue if an existing issue has the same exact title or the same embedded task id / slice id.
- If the approved breakdown itself contains duplicate exact titles for the same repo, stop and ask the user whether to merge, rename, or split them before creating anything.
- If publishing is interrupted and resumed, repeat the duplicate guard before every `gh issue create`; never assume prior creates failed.
```


### `.gitattributes` (append line)

```gitattributes
*.sh text eol=lf
bin/* text eol=lf
templates/spec-repo/bin/* text eol=lf

```

### `README.md` (OpenCode config) — append after new-spec-repo section

```markdown
**Upgrade an existing spec repo** (repo-aware fanout + registry validation):

```bash
~/.config/opencode/bin/upgrade-spec-repo ~/code/APP/APP-spec
~/.config/opencode/bin/upgrade-spec-repo --check-only ~/code/APP/APP-spec
```
```

See transcript Write for full `templates/spec-repo/README.md` — adds bootstrap step 1 (setup-skills + grill-me), registry confirmation before fanout, step 5 validates capability mapping.


---

## Appendix D — `migrate_repos_registry.py` behaviour notes (2026-05-18)

- Parses `repos:` block from `docs/agents/repos.md` (PyYAML or minimal fallback).
- Migrates legacy `name:` + `role: target` → `repo:` + TBD `application_role` / `capabilities`.
- Infers `agent_owner`: `frontend-dev` if repo basename contains `web|frontend|ui|app`; `developer` if `api|service|backend|server`.
- `--check-only`: prints `ok` or `INCOMPLETE: repo1, repo2`.
- Exit 3 when incomplete after migration.

---

## Appendix E — Example filled registry (BlocShed)

```yaml
repos:
  - repo: roborew/blocshed-web
    application_role: User-facing web application
    agent_owner: frontend-dev
    capabilities:
      - billing UI
      - admin surfaces
      - archived content management UI
    non_goals:
      - content formatting pipeline
      - distribution APIs

  - repo: roborew/blocshed-api
    application_role: Content formatting and distribution service
    agent_owner: developer
    capabilities:
      - content formatting
      - distribution APIs
      - archive lifecycle backend
    non_goals:
      - web UI
      - billing screens
```
