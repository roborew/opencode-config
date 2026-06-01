# 2026-05-19 — CRLF line endings and architect bash permissions (allow-by-default)

| Field | Value |
| --- | --- |
| **Cursor chat created** | **2026-05-19** (transcript dir birth `2026-05-19 18:23` local) |
| **Cursor chat ID** | `5d55ef77-4483-4b24-a602-48722ec6eb71` |
| **Transcript** | `~/.cursor/projects/Users-robo-config-opencode/agent-transcripts/5d55ef77-4483-4b24-a602-48722ec6eb71/5d55ef77-4483-4b24-a602-48722ec6eb71.jsonl` |
| **Config repo** | `~/.config/opencode` |
| **Work finalized in chat** | 2026-05-19 (implementation turns); TO REVIEW doc amended 2026-06-01 |
| **Filename date** | **`2026-05-19`** — matches **chat creation** date for `TO REVIEW/` sort order |

**Session scope:** Fix `env: bash\r: No such file or directory` when running spec-repo `bin/fanout` and related tooling; stop architect permission prompts (`△ Permission required`) for routine spec work (`yq`, `file`, `gh`, `bin/*`) while keeping strict deny rules for destructive or local-mutating shell.

**Status:** Implemented and finalized in chat `5d55ef77-…`. **Verify on disk before merge** — later sessions may have moved scripts (e.g. under `bin/stack/`), removed `permission.bash` from architect, or changed redirect rules (`*>*` → spaced patterns). Treat snippets below as the **authoritative target for this session**.

**Companion docs:**

- [`2026-05-19-crlf-line-endings-hardening.md`](2026-05-19-crlf-line-endings-hardening.md) — `feature-upgrade` wrapper, impl `strip_crlf`, extended sync loops
- [`2026-06-01-setup-project-workflow-and-deepseek-bash-fixes.md`](2026-06-01-setup-project-workflow-and-deepseek-bash-fixes.md) — **later**: `* > *` redirect denies; `validate-opencode-config.sh`
- [`2026-06-01-feature-pipeline-and-architect-front-door.md`](2026-06-01-feature-pipeline-and-architect-front-door.md) — **later**: PRD `prd_io.py`, architect menu

**Primary slug:** `downgrade-archival-recovery` (blocshed-spec fanout).

---

## Executive summary

| Area | Outcome |
| --- | --- |
| CRLF root cause | `\r\n` shebangs → `env: bash\r` on macOS/Linux |
| Repo hygiene | **112** files normalized to LF in OpenCode config |
| Prevention | `.gitattributes`, `check-crlf.sh`, `normalize-line-endings.py`, `strip_crlf` on spec sync |
| Architect UX | `permission.bash`: `"*": ask` + 70-line allowlist → **`"*": allow` + deny list** |
| Spec skills | **`fanout-issues`** added to architect `permission.skill` + routing bullet |
| Operator | New architect session after pull; re-sync stale spec repos |

---

## 1. Problems and symptoms

### 1.1 CRLF — `bin/fanout`

```bash
./bin/fanout downgrade-archival-recovery
```

```text
env: bash\r: No such file or directory
```

`\r` in the error means the shebang line is `#!/usr/bin/env bash\r` (CRLF), not LF.

### 1.2 Architect — permission prompts

```text
△ Permission required
# Check PRD file line endings
$ file docs/prd/downgrade-archival-recovery.md
```

Same root cause class: `agents/architect.md` had `"*": ask` under `permission.bash`; only explicitly listed commands ran without approval (`yq`, `file`, `bin/fanout`, etc. were **not** listed initially).

---

## 2. Recreation guide (ordered steps for another AI)

Apply in **`~/.config/opencode`** unless noted.

### Step A — Bulk LF normalize (one-shot)

1. Add `scripts/normalize-line-endings.py` (full file in §3.2).
2. Run:

```bash
cd ~/.config/opencode
python3 scripts/normalize-line-endings.py
chmod +x scripts/normalize-line-endings.py
```

Expected: `normalized 112 file(s):` (count may vary slightly).

### Step B — Git attributes

1. Write root `.gitattributes` (§3.3).

### Step C — CRLF CI gate

1. Add `scripts/check-crlf.sh` (§3.4).
2. `chmod +x scripts/check-crlf.sh`
3. Wire into `.github/workflows/config-integrity.yml` (§3.6).

### Step D — Spec sync strips CRLF on install

1. Patch `bin/stack/sync_spec_tooling.sh` sync section (§3.5) — use the **fixed** `strip_crlf` (compare `raw` once, not double `read_bytes`).

### Step E — Architect bash policy

1. In `agents/architect.md` frontmatter, replace entire `permission.bash` block from `"*": ask` … with §4.1 (**allow + deny**).
2. Update `permission.skill` line to include `fanout-issues`, `to-prd`, `setup-project`, `feature-complete`, etc. (§4.2).
3. Add Fanout routing bullet (§4.3); update Claude Context / Hard Rules text (§4.4).

### Step F — RUNBOOK

1. Patch `docs/RUNBOOK.md` paragraphs (§4.5).

### Step G — Spec repo operator

```bash
"$HOME/.config/opencode/bin/stack/sync_spec_tooling.sh" /path/to/APP-spec
file bin/fanout   # no CRLF
```

### Step H — Reload OpenCode

New **architect** session or `/reload` so frontmatter permissions apply.

---

## 3. CRLF implementation — full snippets

### 3.1 `scripts/normalize-line-endings.py` (create new file)

```python
#!/usr/bin/env python3
"""Convert CRLF to LF in repo text files. Skips binary files (NUL bytes)."""
from __future__ import annotations

import sys
from pathlib import Path

SKIP_DIRS = {".git", "__pycache__", "node_modules", ".venv", "venv"}
SKIP_SUFFIXES = {".pyc", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".woff", ".woff2"}


def should_skip(path: Path) -> bool:
    if any(part in SKIP_DIRS for part in path.parts):
        return True
    return path.suffix.lower() in SKIP_SUFFIXES


def normalize_file(path: Path) -> bool:
    data = path.read_bytes()
    if b"\x00" in data:
        return False
    if b"\r\n" not in data and b"\r" not in data:
        return False
    normalized = data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    if normalized != data:
        path.write_bytes(normalized)
        return True
    return False


def main() -> None:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
    changed: list[str] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or should_skip(path):
            continue
        if normalize_file(path):
            changed.append(str(path.relative_to(root)))
    if changed:
        print(f"normalized {len(changed)} file(s):")
        for name in changed:
            print(f"  {name}")
    else:
        print("no CRLF files to normalize")


if __name__ == "__main__":
    main()
```

### 3.2 Root `.gitattributes` (create or replace)

```gitattributes
# Normalize line endings on checkout and commit (critical for bin/* shebangs on macOS/Linux).
* text=auto eol=lf

*.sh text eol=lf
bin/** text eol=lf
scripts/** text eol=lf
templates/** text eol=lf
```

### 3.3 `scripts/check-crlf.sh` (create new file)

**Note:** Initial version used `shopt -s globstar` (fails on macOS Bash 3.2). Final version omits `globstar` and uses `find` only.

```bash
#!/usr/bin/env bash
# Fail if any tracked text file under bin/, scripts/, or templates/ uses CRLF.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

paths=(
  bin
  scripts
  templates
  .gitattributes
)

bad=()
for base in "${paths[@]}"; do
  [[ -e "$base" ]] || continue
  while IFS= read -r -d '' f; do
    [[ -f "$f" ]] || continue
    if grep -q $'\r' "$f" 2>/dev/null; then
      bad+=("$f")
    fi
  done < <(find "$base" -type f ! -path '*/__pycache__/*' ! -name '*.pyc' -print0 2>/dev/null)
done

if ((${#bad[@]} > 0)); then
  echo "ERROR: CRLF line endings (use LF for shell scripts and tooling):" >&2
  printf '  %s\n' "${bad[@]}" >&2
  echo "Fix: python3 scripts/normalize-line-endings.py" >&2
  exit 1
fi

echo "check-crlf: ok"
```

### 3.4 `bin/stack/sync_spec_tooling.sh` — replace sync install block

**Find** (approximate legacy block):

```bash
echo "==> Syncing spec tooling..."
install -m0755 "$TEMPLATE/bin/fanout" "$SPEC/bin/fanout"
install -m0755 "$TEMPLATE/bin/lib/validate_tickets.py" "$SPEC/bin/lib/validate_tickets.py"
install -m0755 "$TEMPLATE/bin/lib/toposort_tickets.py" "$SPEC/bin/lib/toposort_tickets.py"
[[ -f "$TEMPLATE/bin/status" ]] && install -m0755 "$TEMPLATE/bin/status" "$SPEC/bin/status"
[[ -f "$TEMPLATE/bin/new-prd" ]] && install -m0755 "$TEMPLATE/bin/new-prd" "$SPEC/bin/new-prd"
```

**Replace with:**

```bash
echo "==> Syncing spec tooling..."
# Ensure LF shebangs (CRLF breaks `env: bash\r` on macOS/Linux).
strip_crlf() {
  python3 -c "
import pathlib, sys
p = pathlib.Path(sys.argv[1])
raw = p.read_bytes()
data = raw.replace(b'\r\n', b'\n').replace(b'\r', b'\n')
if data != raw:
    p.write_bytes(data)
" "$1"
}
sync_bin() {
  install -m0755 "$1" "$2"
  strip_crlf "$2"
}
sync_bin "$TEMPLATE/bin/fanout" "$SPEC/bin/fanout"
sync_bin "$TEMPLATE/bin/lib/validate_tickets.py" "$SPEC/bin/lib/validate_tickets.py"
sync_bin "$TEMPLATE/bin/lib/toposort_tickets.py" "$SPEC/bin/lib/toposort_tickets.py"
[[ -f "$TEMPLATE/bin/status" ]] && sync_bin "$TEMPLATE/bin/status" "$SPEC/bin/status"
[[ -f "$TEMPLATE/bin/new-prd" ]] && sync_bin "$TEMPLATE/bin/new-prd" "$SPEC/bin/new-prd"
```

**Bug fix in same session:** Do **not** ship the first `strip_crlf` draft that called `p.read_bytes()` twice in the `if` — it never writes. Use `raw` + `data != raw` as above.

### 3.5 `.github/workflows/config-integrity.yml` — paths + step

**Extend `on.pull_request.paths` and `on.push.paths`** with:

```yaml
      - "bin/**"
      - "templates/**"
      - "scripts/**"
      - ".gitattributes"
```

**Add job step before validate:**

```yaml
      - name: Check shell script line endings (LF only)
        run: bash scripts/check-crlf.sh
      - name: Validate OpenCode config
        run: bash scripts/validate-opencode-config.sh
```

### 3.6 Files bulk-normalized (representative list)

Templates and bins (non-exhaustive; run normalize script for ground truth):

- `templates/spec-repo/bin/fanout`
- `templates/spec-repo/bin/lib/validate_tickets.py`
- `templates/spec-repo/bin/lib/toposort_tickets.py`
- `templates/spec-repo/bin/new-prd`, `bin/status`
- `bin/lib/oc-root.sh`, `bin/lib/migrate_repos_registry.py`
- All `agents/*.md`, most `skills/**/SKILL.md`, `scripts/*.sh`, many `docs/**` — **112 total** in session output

---

## 4. Architect permissions — full snippets

### 4.1 BEFORE (remove this pattern)

`agents/architect.md` used **ask-by-default** and a long allowlist. Minimal excerpt of the old model:

```yaml
permission:
  edit: deny
  bash:
    "*": ask
    "pwd": allow
    "ls": allow
    "ls *": allow
    # … rg, git diff, gh issue create, etc. (70+ lines)
    "rm *": deny
    "mv *": deny
    # …
```

**Intermediate (same session, superseded):** explicit allows were added for `yq *`, `file *`, `bin/fanout *`, `gh issue view *`, etc. User still hit prompts on unlisted commands → replaced by allow-by-default.

### 4.2 AFTER — full `permission.bash` block (paste into `agents/architect.md` frontmatter)

Keep `tools:` (`write: false`, `edit: false`, `bash: true`) and `edit: deny` unchanged. Replace **`bash:`** subtree with:

```yaml
  bash:
    # Allow-by-default for spec/planning work (yq, gh, bin/*, file, python, etc.).
    # Deny filesystem mutation, destructive git, shell redirects, and package installs.
    # Artifact/source writes stay on scribe (edit: deny on this agent).
    "*": allow
    "rm *": deny
    "rm -rf *": deny
    "mv *": deny
    "cp *": deny
    "mkdir *": deny
    "touch *": deny
    "chmod *": deny
    "chown *": deny
    "ln *": deny
    "truncate *": deny
    "sudo *": deny
    "doas *": deny
    "sed -i *": deny
    "sed -i'*": deny
    "perl -pi *": deny
    "git add *": deny
    "git commit *": deny
    "git push *": deny
    "git push * --force*": deny
    "git push * -f*": deny
    "git reset *": deny
    "git checkout *": deny
    "git restore *": deny
    "git clean *": deny
    "git apply *": deny
    "git merge *": deny
    "git rebase *": deny
    "git cherry-pick *": deny
    "git stash *": deny
    "git pull *": deny
    "git clone *": deny
    "git switch *": deny
    "git tag *": deny
    "npm install*": deny
    "npm i *": deny
    "pnpm install*": deny
    "yarn install*": deny
    "pip install *": deny
    "pip3 install *": deny
    "brew install *": deny
    "*>*": deny
    "*>>*": deny
    "*| tee *": deny
    "*|tee *": deny
```

**Important (later session note):** Broad `"*>*"` / `"*>>*"` denies also block `gh … 2>&1` and `ls … 2>/dev/null` on some OpenCode builds. If that regresses, see [`2026-06-01-setup-project-workflow-and-deepseek-bash-fixes.md`](2026-06-01-setup-project-workflow-and-deepseek-bash-fixes.md) for spaced redirect patterns (`"* > *"`, `"* 2> *"`).

### 4.3 `permission.skill` line (architect frontmatter)

```yaml
  skill: { "architect-plan": "allow", "architect-review": "allow", "fanout-issues": "allow", "github-issue-run": "allow", "grill-me": "allow", "handoff": "allow", "to-issues": "allow", "to-prd": "allow", "triage": "allow", "research": "allow", "improve-codebase-architecture": "allow", "zoom-out": "allow", "caveman": "allow", "setup-skills": "allow", "setup-project": "allow", "issue-expand": "allow", "feature-complete": "allow" }
```

(`fanout-issues` was **missing** before this session; template lives at `templates/spec-repo/skills/fanout-issues/SKILL.md` and is copied into spec repos on sync.)

### 4.4 Skill routing bullet (body of `agents/architect.md`)

Add after the **To PRD** bullet:

```markdown
- **Fanout:** User approved PRD and wants child issues in target repos → load **`fanout-issues`** and run `bin/fanout <slug>` (uses `yq` + `gh`).
```

### 4.5 Claude Context / Hard Rules text (replacements)

**Claude Context readiness gate** (shell fallback wording):

```markdown
- If `claude-context` is unavailable, errors, or indexing fails after retry, you may use shell for read-only discovery only (`rg`, `find`, `git diff`, `git status`, `file`, `yq`, `gh`, `bin/*`, etc.). Denied patterns in `permission.bash` still apply. Record `MCP_FALLBACK: claude-context unavailable or indexing failed — <error>` in the plan `Context` or `Gaps`.
- Never use shell to mutate the local tree (writes go to **scribe**). GitHub/issue tooling (`gh`, `bin/fanout`) is allowed when skills require it.
```

**Hard rule 12:**

```markdown
12. **Claude Context readiness.** Before any planning discovery, enforce the Claude Context readiness gate above. If MCP fails, use shell for read-only discovery only; respect `permission.bash` denials (no local file mutation via shell).
```

### 4.6 `docs/RUNBOOK.md` patches

**Overview bullet** — replace guarded-shell wording:

```markdown
- **Primary planning mode** (`architect`) — read-only with allow-by-default bash (explicit deny for destructive/mutating shell): exploration, reporting, drafting plans;
```

**Permission conventions paragraph:**

```markdown
Both primaries (`architect`, `orchestrate`) are non-writing (`edit: deny`). Architect bash is **allow-by-default** with an explicit **deny** list (no `rm`/`mv`/`cp`, destructive git, shell redirects, package installs); planning tooling (`yq`, `gh`, `bin/fanout`, `file`, `python3`, etc.) runs without prompts. Only `scribe` writes plan artifacts, docs, `README.md`, and `.env.example` in allowed paths.
```

### 4.7 Global `opencode.json` (context only — not changed this session)

At time of session, global bash was broadly allowed:

```json
    "bash": {
      "*": "allow",
      "rm -rf /*": "deny",
      ...
    }
```

Architect **frontmatter overrides** global for the architect agent. Orchestrate and other agents are unaffected by §4.2.

---

## 5. Security model (unchanged intent)

| Layer | Rule |
| --- | --- |
| Architect role | Read-only coordinator |
| `edit: deny` + `write: false` | No direct artifact/source writes |
| `bash: "*": allow` | Spec/planning/GitHub/bin tooling without prompts |
| Bash denies | No shell local mutation, destructive git, package installs, file redirects |
| Writes | **scribe** via Task; **developer** only where skills require `gh issue edit` |

---

## 6. Verification commands

```bash
# Config repo
cd ~/.config/opencode
bash scripts/check-crlf.sh
find . -type f ! -path '*/.git/*' -print0 | xargs -0 file 2>/dev/null | grep CRLF || echo "no CRLF"

# Spec repo
file bin/fanout
./bin/fanout downgrade-archival-recovery   # not bash\r

# Architect (new session)
yq --version
file docs/prd/downgrade-archival-recovery.md
```

---

## 7. Chat timeline

| # | Event |
| --- | --- |
| 1 | `./bin/fanout` → `env: bash\r`; CRLF diagnosis |
| 2 | `normalize-line-endings.py`, `.gitattributes`, `check-crlf.sh`, `strip_crlf` in sync, CI step; 112 files normalized |
| 3 | △ on `yq --version`; whitelist grows (`yq`, `gh`, `bin/fanout`, …) |
| 4 | △ on `file docs/prd/...` |
| 5 | User: allow all architect work within strict security → `"*": allow` + deny list |
| 6 | `fanout-issues` skill + routing; RUNBOOK updated |
| 7 | TO REVIEW doc created (filename corrected to chat-creation date **2026-05-19**) |

---

## 8. Out of scope / not done

- No git commit/push in chat.
- `bin/fanout downgrade-archival-recovery` not run to completion (blocked before fixes).
- Did not fix DeepSeek V4 / OpenRouter `reasoning_content` tool failures.
- Did not implement `feature-upgrade` always-sync wrapper (see hardening doc).

---

## 9. `TO REVIEW/` sort key

**Filename:** `2026-05-19-crlf-line-endings-and-architect-bash-permissions.md`  
Sorts with other **`2026-05-19-*`** entries by date prefix, then slug.

---

*End of session record for Cursor chat `5d55ef77-4483-4b24-a602-48722ec6eb71` (created 2026-05-19).*
