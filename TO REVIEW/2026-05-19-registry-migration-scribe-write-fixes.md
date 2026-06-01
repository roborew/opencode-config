# 2026-05-19 — Registry migration overwrite + scribe Write tool fixes

**Cursor chat created:** 2026-05-19 (Tuesday) — date prefix matches when this Cursor session started.

**Work completed:** 2026-05-19 — implementation and unit tests finalized in the same chat before follow-up review notes.

**Session scope:** Fix two OpenCode config issues discovered during blocshed `downgrade-archival-recovery` setup: (1) `migrate_repos_registry.py` clobbering partially filled `docs/agents/repos.md` on every `feature-upgrade` sync, and (2) scribe using `edit`/`apply_patch` instead of Write for full-file overwrites.

**Status:** Implemented and verified in chat (9 unit tests passing). Verify on disk before merge — workspace may have diverged since this session.

**Plan reference:** Cursor plan `registry_and_scribe_fixes_c20db938` (user chose not to edit the plan file).

---

## Executive summary

| Area | Outcome |
| --- | --- |
| **`migrate_repos_registry.py`** | Split schema migration from completeness check; TBD-aware per-field merge; preserve markdown header on write; canonical `repos:` YAML block |
| **`test_migrate_repos_registry.py`** | New — 9 stdlib unittest cases |
| **`agents/scribe.md`** | `edit: false`; Write-only instructions; removed broad `permission.edit` block |
| **`skills/scribe/SKILL.md`** | Write mandatory; explicit `docs/agents/repos.md` callout |
| **`scripts/validate-opencode-config.sh`** | Run migrate unittest; skip edit-permission checks when `edit: false` |

---

## Background

During setup for the **downgrade-archival-recovery** feature in the blocshed stack:

1. Capability/owner checks on `docs/agents/repos.md` were passing after manual edits.
2. Remaining `FAIL` lines from tooling were expected — they indicated tickets still needed `issue-expand` (next step: architect option 1 in blocshed-web).
3. Two config bugs blocked reliable registry editing and sync:
   - **`feature-upgrade`** re-sync overwrote user-set registry fields.
   - **Scribe** repeatedly used patch/edit instead of Write when asked to overwrite `repos.md`, causing silent no-ops or corrupted content (including appended prompt text on one attempt).

### Trigger path (Problem 1)

```text
bin/feature-upgrade
  → bin/stack/sync_spec_tooling.sh
    → python3 bin/lib/migrate_repos_registry.py docs/agents/repos.md
```

`sync_spec_tooling.sh` invokes migrate unconditionally on every sync (line ~96):

```bash
REGISTRY="$SPEC/docs/agents/repos.md"
# ...
python3 "$MIGRATE" "$REGISTRY" || REGISTRY_INCOMPLETE=true
```

---

## Problem 1 — Registry migration overwrites partial edits

### Root cause (before)

The write gate conflated **schema migration** with **registry completeness**:

```python
# BEFORE — bin/lib/migrate_repos_registry.py (main(), ~lines 211–213)
needs_migration = any("name" in r and "repo" not in r for r in repos) or any(
    not is_complete(normalize_entry(r)) for r in repos
)
```

The second clause treated **any remaining TBD placeholder** as a migration trigger. Every `feature-upgrade` sync therefore rewrote `repos.md` until every repo was fully complete.

Additional fragility in the old `normalize_entry()`:

```python
# BEFORE — field merge treated TBD strings as "present"
for key in ("application_role", "agent_owner", "capabilities", ...):
    if key in raw and raw[key] not in (None, "", []):
        out[key] = raw[key]   # keeps "TBD — …" placeholders forever
    elif key in defaults:
        out[key] = defaults[key]
```

Old `write_registry()` replaced the rich template header with a short hardcoded `HEADER` and dumped YAML as a bare list (no `repos:` key):

```python
# BEFORE
yaml_body = yaml.safe_dump(repos, sort_keys=False, allow_unicode=True).rstrip()
path.write_text(HEADER + yaml_body + "\n", encoding="utf-8")
# Produced: HEADER + "- repo: ...\n  application_role: ..."  (no repos: wrapper)
```

### Intended behaviour (after)

| Condition | Action |
| --- | --- |
| Legacy schema (`name:` without `repo:`, `role: target` without `application_role`) | Normalize and rewrite file |
| Partially filled registry (some repos/fields still TBD) | **Do not rewrite**; print `INCOMPLETE: …` and exit 3 |
| Fully complete registry | Print `ok` (check-only) or `no migration needed`; exit 0 |

---

## Problem 2 — Scribe prefers patch over Write

### Root cause (before)

[`agents/scribe.md`](../agents/scribe.md) had both `write: true` and `edit: true`. In OpenCode, `edit` maps to patch/diff tooling (`apply_patch`). GPT-5-nano preferred patch for “update file” tasks even when parents supplied full `content` bodies.

Agent and skill text said “write **or** edit tool”, giving the model permission to pick patch — unreliable for full-file overwrites like `docs/agents/repos.md`.

**Before — agent frontmatter:**

```yaml
tools:
  write: true
  edit: true
  bash: true
  skill: true
permission:
  bash:
    "*": allow
  skill: { "scribe": "allow" }
  edit:
    "~/.config/opencode/**": deny
    "*": allow
```

**Before — agent body (representative):**

```markdown
- **You MUST invoke the write or edit tool to persist the file.**
```

**Before — skill (`skills/scribe/SKILL.md`):**

```markdown
**Write contract (mandatory):** ... You MUST invoke the write/edit tool to persist the file to disk.
...
5. Create or update the file using the provided content exactly. **You must invoke the write or edit tool.**
```

---

## Changes implemented — full recreation guide

### File 1: `bin/lib/migrate_repos_registry.py`

**Action:** Replace/add the following functions. Keep existing `split_registry`, `_parse_repos_minimal`, `infer_defaults`, `is_complete`, and `HEADER` unless noted.

#### New helpers (insert after `infer_defaults`)

```python
def is_empty_or_tbd(value: object) -> bool:
    if value is None:
        return True
    if isinstance(value, str):
        return not value.strip() or "TBD" in value
    if isinstance(value, list):
        return len(value) == 0
    return False


def clean_capabilities(caps: object) -> list:
    if not isinstance(caps, list):
        return []
    return [c for c in caps if c and "TBD" not in str(c)]


def needs_schema_migration(repos: list[dict]) -> bool:
    for r in repos:
        if not r.get("repo") and not r.get("name"):
            return True
        if "name" in r and "repo" not in r:
            return True
        if r.get("role") == "target" and "application_role" not in r:
            return True
    return False
```

#### Replace `normalize_entry` entirely

```python
def normalize_entry(raw: dict) -> dict:
    repo = raw.get("repo") or raw.get("name") or ""
    if not repo:
        return raw
    out: dict = {"repo": repo}
    defaults = infer_defaults(repo)

    role = raw.get("application_role")
    if not is_empty_or_tbd(role):
        out["application_role"] = role
    else:
        out["application_role"] = defaults["application_role"]

    owner = raw.get("agent_owner")
    if not is_empty_or_tbd(owner):
        out["agent_owner"] = owner
    else:
        out["agent_owner"] = defaults["agent_owner"]

    caps = clean_capabilities(raw.get("capabilities"))
    if caps:
        out["capabilities"] = caps
    else:
        out["capabilities"] = defaults["capabilities"]

    for key in ("non_goals", "integration_contracts", "default_test_commands"):
        val = raw.get(key)
        if val not in (None, "", []):
            out[key] = val
        elif key == "non_goals":
            out["non_goals"] = []

    return out
```

#### New serialization helpers (replace old `write_registry` body logic)

```python
def dedupe_repos(repos: list[dict]) -> list[dict]:
    seen: set[str] = set()
    unique: list[dict] = []
    for r in repos:
        repo = r.get("repo")
        if not repo or repo in seen:
            continue
        seen.add(repo)
        unique.append(r)
    return unique


def format_registry_yaml(repos: list[dict]) -> str:
    if yaml is not None:
        body = yaml.safe_dump(repos, sort_keys=False, allow_unicode=True).rstrip()
        indented = "\n".join(f"  {line}" if line else line for line in body.splitlines())
        return f"repos:\n{indented}"
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
    return "\n".join(lines)


def registry_content(header: str, repos: list[dict]) -> str:
    h = header.rstrip() if header.strip() else HEADER.rstrip()
    return f"{h}\n\n{format_registry_yaml(repos)}\n"


def write_registry(path: Path, repos: list[dict], header: str | None = None) -> None:
    h = header if header is not None else HEADER
    path.write_text(registry_content(h, repos), encoding="utf-8")
```

#### Replace `main()` entirely

```python
def main() -> None:
    if len(sys.argv) < 2:
        print("usage: migrate_repos_registry.py <repos.md> [--check-only]", file=sys.stderr)
        sys.exit(2)
    path = Path(sys.argv[1])
    check_only = "--check-only" in sys.argv[2:]
    if not path.is_file():
        print(f"missing {path}", file=sys.stderr)
        sys.exit(1)

    header, repos = split_registry(path)
    if not repos:
        print("INCOMPLETE: repos list is empty")
        sys.exit(3)

    normalized = dedupe_repos([normalize_entry(r) for r in repos])

    if check_only:
        incomplete = [r.get("repo") or r.get("name") for r in repos if not is_complete(normalize_entry(r))]
        if incomplete:
            print("INCOMPLETE: " + ", ".join(str(x) for x in incomplete if x))
            sys.exit(3)
        print("ok")
        sys.exit(0)

    schema_migration = needs_schema_migration(repos)
    if schema_migration:
        old_content = path.read_text(encoding="utf-8")
        new_content = registry_content(header, normalized)
        if new_content != old_content:
            backup = path.with_suffix(path.suffix + ".bak")
            if not backup.exists():
                backup.write_text(old_content, encoding="utf-8")
            write_registry(path, normalized, header)
            print(f"migrated {path} ({len(normalized)} repos)")
        else:
            print(f"no migration needed for {path}")
    else:
        print(f"no migration needed for {path}")

    incomplete = [r["repo"] for r in normalized if not is_complete(r)]
    if incomplete:
        print("INCOMPLETE: " + ", ".join(incomplete))
        sys.exit(3)


if __name__ == "__main__":
    main()
```

**Key behavioural change in `main()`:** Remove the old block:

```python
# DELETE — do not keep this
needs_migration = any("name" in r and "repo" not in r for r in repos) or any(
    not is_complete(normalize_entry(r)) for r in repos
)
if needs_migration or path.read_text(...) != HEADER + yaml.safe_dump(...):
    write_registry(path, unique)  # always rewrote on TBD
```

---

### File 2: `bin/lib/test_migrate_repos_registry.py` (new file)

Create this file in full:

```python
#!/usr/bin/env python3
"""Tests for migrate_repos_registry.py."""
from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

LIB = Path(__file__).resolve().parent
sys.path.insert(0, str(LIB))

import migrate_repos_registry as m  # noqa: E402


PARTIAL_REGISTRY = """# Spec repo registry

Custom header preserved by migration.

---

repos:
  - repo: myorg/my-web
    application_role: User-facing web application
    agent_owner: frontend-dev
    capabilities:
      - billing UI
      - admin surfaces
  - repo: myorg/my-api
    application_role: TBD — service/API role (confirm — not necessarily generic backend)
    agent_owner: developer
    capabilities:
      - TBD — add capabilities in setup-skills
"""

LEGACY_REGISTRY = """# Legacy registry

---

repos:
  - name: myorg/my-web
    role: target
  - name: myorg/my-api
    role: target
"""


class NormalizeEntryTests(unittest.TestCase):
    def test_preserves_filled_fields_when_other_repo_has_tbd(self) -> None:
        normalize = m.normalize_entry(
            {
                "repo": "myorg/my-web",
                "application_role": "User-facing web application",
                "agent_owner": "frontend-dev",
                "capabilities": ["billing UI", "admin surfaces"],
            }
        )
        self.assertEqual(normalize["application_role"], "User-facing web application")
        self.assertEqual(normalize["capabilities"], ["billing UI", "admin surfaces"])

    def test_tbd_capabilities_replaced_non_tbd_role_kept(self) -> None:
        out = m.normalize_entry(
            {
                "repo": "myorg/my-web",
                "application_role": "User-facing web application",
                "agent_owner": "frontend-dev",
                "capabilities": ["TBD — add capabilities in setup-skills"],
            }
        )
        self.assertEqual(out["application_role"], "User-facing web application")
        self.assertTrue(any("TBD" in c for c in out["capabilities"]))

    def test_mixed_capabilities_drop_tbd_keep_real(self) -> None:
        out = m.normalize_entry(
            {
                "repo": "myorg/my-web",
                "application_role": "User-facing web application",
                "capabilities": ["billing UI", "TBD — add capabilities in setup-skills"],
            }
        )
        self.assertEqual(out["capabilities"], ["billing UI"])

    def test_legacy_name_migrated_to_repo(self) -> None:
        out = m.normalize_entry({"name": "myorg/my-web", "role": "target"})
        self.assertEqual(out["repo"], "myorg/my-web")
        self.assertIn("application_role", out)


class SchemaMigrationTests(unittest.TestCase):
    def test_needs_schema_migration_for_legacy_name(self) -> None:
        repos = [{"name": "myorg/my-web", "role": "target"}]
        self.assertTrue(m.needs_schema_migration(repos))

    def test_no_schema_migration_for_partial_tbd(self) -> None:
        repos = [
            {
                "repo": "myorg/my-web",
                "application_role": "User-facing web application",
                "capabilities": ["billing UI"],
            }
        ]
        self.assertFalse(m.needs_schema_migration(repos))


class MainIntegrationTests(unittest.TestCase):
    def _run_migrate(self, content: str) -> tuple[int, str, Path]:
        tmp = tempfile.NamedTemporaryFile(suffix=".md", delete=False)
        path = Path(tmp.name)
        path.write_text(content, encoding="utf-8")
        tmp.close()
        proc = subprocess.run(
            [sys.executable, str(LIB / "migrate_repos_registry.py"), str(path)],
            capture_output=True,
            text=True,
        )
        output = proc.stdout + proc.stderr
        return proc.returncode, output, path

    def test_incomplete_does_not_rewrite(self) -> None:
        code, output, path = self._run_migrate(PARTIAL_REGISTRY)
        self.assertEqual(path.read_text(encoding="utf-8"), PARTIAL_REGISTRY)
        self.assertIn("no migration needed", output)
        self.assertIn("INCOMPLETE", output)
        self.assertEqual(code, 3)
        path.unlink(missing_ok=True)

    def test_legacy_name_migrates_to_repo(self) -> None:
        code, output, path = self._run_migrate(LEGACY_REGISTRY)
        text = path.read_text(encoding="utf-8")
        self.assertIn("repo: myorg/my-web", text)
        self.assertNotIn("name: myorg/my-web", text)
        self.assertIn("migrated", output)
        self.assertEqual(code, 3)
        path.unlink(missing_ok=True)

    def test_partial_fill_preserved_after_legacy_migration(self) -> None:
        content = """# Registry

---

repos:
  - repo: myorg/my-web
    application_role: User-facing web application
    agent_owner: frontend-dev
    capabilities:
      - billing UI
  - name: myorg/my-api
    role: target
"""
        code, output, path = self._run_migrate(content)
        text = path.read_text(encoding="utf-8")
        self.assertIn("User-facing web application", text)
        self.assertIn("billing UI", text)
        self.assertIn("repo: myorg/my-api", text)
        self.assertIn("migrated", output)
        self.assertEqual(code, 3)
        path.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
```

---

### File 3: `agents/scribe.md`

**Action:** Change frontmatter and instruction lines as follows.

**After — frontmatter (replace `tools` and `permission` blocks):**

```yaml
---
description: Markdown artifact and docs writer
mode: subagent
model: openrouter/openai/gpt-5-nano
tools:
  write: true
  edit: false
  bash: true
  skill: true
permission:
  bash:
    "*": allow
  skill: { "scribe": "allow" }
---
```

Remove the entire `permission.edit` block (both the old wildcard `"*": allow` form and any later allow-list form). Scribe uses Write only; bash remains for `archive_plan` mv.

**After — replace these lines in the agent body:**

```markdown
- **You MUST invoke the Write tool to persist the file.** Never use edit/patch for normal writes — parents always supply full file `content`. Your only job is to write the file. Do not report success without having written it.
- For **`docs/agents/repos.md`** and other full-file updates, Write is mandatory; patch/edit tools are unavailable and must not be attempted.
- Return concise write report: target path, operation (create/update), short content summary, and Write tool call evidence that the file was written.
- If the Write tool fails or you did not invoke it: report `SCRIBE_FAILED: file not written` with target path and reason. Do not report success.
```

**After — Hard Rule 2:** Remove reference to `permission.edit` in allowed locations line; use plain path list.

**After — Hard Rule 7:**

```markdown
7. For normal writes: never report success without having invoked the Write tool and persisted the file. For `archive_plan`, never report success without `mv` evidence. Report `SCRIBE_FAILED` if the operation did not complete.
```

---

### File 4: `skills/scribe/SKILL.md`

**After — replace Write contract block:**

```markdown
**Write contract (mandatory):** Your only job is to write the file. You MUST invoke the **Write** tool with the parent-supplied full `content` to persist the file to disk. **Never** use edit/patch — it is disabled for scribe. Updates are always full-file rewrites even when `mode: update`. If you do not successfully write the file, you have failed the task. Do not report success without having written the file. If Write fails, report `SCRIBE_FAILED` — do not fall back to patch.

**`docs/agents/repos.md` and other `docs/agents/*` paths:** Write the entire file body with the Write tool only. Patch-based edits are unreliable for registry files.
```

**After — Workflow step 5–7:**

```markdown
5. Create or update the file using the provided content exactly. **You must invoke the Write tool** with the full `content` body. Do not skip this step. Do not modify, reformat, or summarize the content. Do not use edit/patch.
6. If the Write tool fails or you did not invoke it: report `SCRIBE_FAILED: file not written` with the target path and reason. Do not report success.
7. Return a concise write report with:
   - target path (resolved)
   - operation (`create`/`update`)
   - short content summary
   - confirmation that the file was written (Write tool call evidence)
```

---

### File 5: `scripts/validate-opencode-config.sh`

**Action:** Add two changes to the existing validator.

#### 5a. Skip edit-permission checks for write-only agents

Inside the `UNATTENDED_WRITER_AGENTS` loop, after extracting frontmatter `$fm`, add:

```bash
  if echo "$fm" | grep -qE '^[[:space:]]*edit:[[:space:]]*false'; then
    continue
  fi
```

This allows scribe with `edit: false` and no `permission.edit` block to pass validation.

#### 5b. Run migrate unit tests before final exit

Before the final `if [[ $ERR -ne 0 ]]` block, add:

```bash
echo "Checking migrate_repos_registry unit tests..."
if ! python3 -m unittest bin/lib/test_migrate_repos_registry.py -q; then
  echo "  FAILED: migrate_repos_registry tests"
  ERR=1
fi
```

---

## Verification commands

```bash
cd ~/.config/opencode

# Unit tests (expect 9 OK)
python3 -m unittest bin/lib/test_migrate_repos_registry.py -v

# Partial registry — file must NOT change; exit 3 with INCOMPLETE
python3 bin/lib/migrate_repos_registry.py /path/to/partial-repos.md
# Expected stdout:
#   no migration needed for /path/to/partial-repos.md
#   INCOMPLETE: myorg/my-api

# Legacy schema — file MUST migrate name→repo
python3 bin/lib/migrate_repos_registry.py /path/to/legacy-repos.md
# Expected stdout:
#   migrated /path/to/legacy-repos.md (N repos)
#   INCOMPLETE: ...

# Config lint (includes unittest step)
scripts/validate-opencode-config.sh
```

---

## Files touched (summary)

| File | Change |
| --- | --- |
| `bin/lib/migrate_repos_registry.py` | Schema/completeness split, TBD-aware merge, header-preserving write |
| `bin/lib/test_migrate_repos_registry.py` | **New** — 9 regression tests |
| `agents/scribe.md` | `edit: false`, Write-only instructions, `permission.edit` removed |
| `skills/scribe/SKILL.md` | Write mandatory; explicit repos.md callout |
| `scripts/validate-opencode-config.sh` | Unittest step; skip edit checks when `edit: false` |

---

## Out of scope (not implemented in this chat)

| Item | Notes |
| --- | --- |
| **`create_or_sync_spec.sh` registry overwrite** | `setup-project` still **always** overwrites `docs/agents/repos.md` with bare `name/role` list (lines 116–130). Separate footgun; not on the `feature-upgrade` path. See [`2026-05-20-setup-project-cross-stack-scope.md`](2026-05-20-setup-project-cross-stack-scope.md). |
| **Operational next step** | Open blocshed-web → architect → option 1 → slug `downgrade-archival-recovery` → `issue-expand` on each ticket, then orchestrate execution. |

---

## Operator notes

### When `feature-upgrade` reports INCOMPLETE

Expected while `docs/agents/repos.md` still has TBD placeholders. The registry file is **no longer rewritten** on each sync — only reported as incomplete (exit 3). Fill remaining fields via scribe (Write) or manual edit, then re-run.

### When scribe updates `repos.md`

Parent must pass full file `content`. Scribe should show **Write tool evidence** in its report, not `apply_patch`. If `SCRIBE_FAILED`, re-invoke with same content.

### Re-verify after merge

If the workspace has diverged (e.g. `bin/` tree absent, scribe permissions refactored to allow-list edit), diff against the snippets in this document and re-apply.

---

## Related documents

| Date | Document |
| --- | --- |
| 2026-05-20 | [setup-project cross-stack scope investigation](2026-05-20-setup-project-cross-stack-scope.md) |
| 2026-05-20 | [setup-project empty TARGETS fix](2026-05-20-setup-project-empty-targets-fix.md) |
