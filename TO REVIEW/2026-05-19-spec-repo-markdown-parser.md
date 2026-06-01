# 2026-05-19 — SPEC_REPO Markdown Parsing Fix

**Chat created:** 2026-05-19 (Cursor transcript birth date; transcript ID `b7aa272b-b3bb-4ea3-b431-44d0091991f3`).

**Work completed:** 2026-05-19 — same session as chat creation.

**Session scope:** Fix `bin/issue-expand-bundle` (and related impl-repo tooling) so `SPEC_REPO` is read correctly from markdown-formatted `docs/agents/issue-tracker.md` in implementation repos such as `blocshed-web`.

**Status:** Implemented and finalized in this chat. Re-sync implementation repos after confirming these files exist under `~/.config/opencode`.

**Plan reference:** Cursor plan `spec_repo_markdown_parser_7e0cd0c0` (user chose not to edit the plan file after execution).

---

## Executive summary

| Area | Outcome |
| --- | --- |
| **Trigger** | `bin/issue-expand-bundle downgrade-archival-recovery` in `blocshed-web` exited 2 despite `docs/agents/issue-tracker.md` containing `- SPEC_REPO: roborew/blocshed-spec` |
| **Root cause** | Line-anchored `grep ^[[:space:]]*SPEC_REPO:` does not match markdown list lines starting with `- ` |
| **Fix** | New shared parser `bin/lib/read_spec_repo.sh` + wire into impl bins and wiring check |
| **Templates** | **Unchanged** — `link-spec-repo` still writes `- **SPEC_REPO:** owner/name` |
| **Tests** | `bin/lib/test_read_spec_repo.sh` — 5 cases, all passed at implementation time |
| **Rollout** | Re-run `sync_impl_tooling.sh` per impl repo; no edit to existing `issue-tracker.md` required |

---

## Problem reported (verbatim intent)

From implementation repo root (`blocshed-web`):

```bash
bin/issue-expand-bundle downgrade-archival-recovery
```

Failed with:

```text
ERROR: docs/agents/issue-tracker.md must define SPEC_REPO. Run link-spec-repo / setup-project.
```

Operator investigation showed `docs/agents/issue-tracker.md` **did** define the spec repo, but the script could not parse the line format.

---

## Investigation timeline (this chat)

1. **Initial hypothesis:** `issue-tracker.md` uses `- **SPEC_REPO:** roborew/blocshed-spec` (bold markdown from `link_impl_repo.sh` template) and the script expects plain `SPEC_REPO:`.
2. **`xxd` confirmation (user):** Hex at offset `0xdf` shows the actual line has **no bold**:

   ```text
   2d 20 5350 4543 5f52 4550 4f3a 20   →  "- SPEC_REPO: roborew/blocshed-spec"
   ```

3. **Refined root cause:** The list prefix `- ` is not matched by `^[[:space:]]*` (dash is not whitespace). Grep returns nothing → `SPEC_REPO` empty → exit 2.
4. **Design choice (user):** Keep human-readable markdown in templates; harden parsers to strip list/bold/backticks before validating `owner/name`.
5. **Implementation:** Shared lib + tests + doc touch-ups; all todos completed same session.

---

## Root cause (technical)

### What `issue-tracker.md` contained (blocshed-web)

```markdown
- SPEC_REPO: roborew/blocshed-spec
```

### What the scripts did (before fix)

```bash
grep -E '^[[:space:]]*(SPEC_REPO|spec_repo|Spec repo|spec repository):' docs/agents/issue-tracker.md \
  | head -1 | sed -E 's/^[^:]*:[[:space:]]*//' | tr -d '\r'
```

| Line in file | Old `grep` matches? | Old `sed` value (if grep matched) |
| --- | --- | --- |
| `SPEC_REPO: owner/name` | Yes | `owner/name` |
| `- SPEC_REPO: owner/name` | **No** (blocshed) | — |
| `- **SPEC_REPO:** owner/name` | **No** (link-spec-repo template) | would be `** owner/name` |

### Secondary failure: wiring check

`bin/stack/check_impl_wiring.sh` used:

```bash
grep -q '^SPEC_REPO:' "$impl/docs/agents/issue-tracker.md"
```

Correctly wired repos could falsely report `INCOMPLETE: SPEC_REPO line`.

### What generates `issue-tracker.md` (unchanged by this fix)

`bin/stack/link_impl_repo.sh` (called by `bin/link-spec-repo`) writes:

```bash
cat > docs/agents/issue-tracker.md <<'EOF'
# Issue tracker
...
- **SPEC_REPO:** __SPEC_REPO__
...
EOF
sed -i '' "s|__SPEC_REPO__|${SPEC_REPO}|g" docs/agents/issue-tracker.md
```

The parser must tolerate **both** plain list lines and bold template lines.

---

## Architecture (data flow)

```text
impl repo: docs/agents/issue-tracker.md
  "- SPEC_REPO: owner/app-spec"  OR  "- **SPEC_REPO:** owner/app-spec"
              │
              ▼
  read_spec_repo_from_file()   ← bin/lib/read_spec_repo.sh (OpenCode config)
              │
              ├── templates/bin/issue-expand-bundle  → tmp/issue-expand-bundle.md
              ├── templates/bin/feature-context      → tmp/feature-context.md
              └── bin/stack/check_impl_wiring.sh     → OK / INCOMPLETE

OpenCode config path resolved via:
  OC_ROOT="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
  # or for stack scripts:
  ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
```

Impl bins are **copied** into target repos by `bin/stack/sync_impl_tooling.sh` from `templates/bin/`; the **parser lib stays** in the OpenCode config checkout and is sourced at runtime.

---

## Files to create or modify (recreate checklist)

| # | Path | Action |
| --- | --- | --- |
| 1 | `bin/lib/read_spec_repo.sh` | **Create** (full file below) |
| 2 | `bin/lib/test_read_spec_repo.sh` | **Create** (full file below); `chmod +x` |
| 3 | `templates/bin/issue-expand-bundle` | **Replace** SPEC_REPO block (diff below) |
| 4 | `templates/bin/feature-context` | **Replace** header + SPEC_REPO block (diff below) |
| 5 | `bin/stack/check_impl_wiring.sh` | **Add** source + replace grep (diff below) |
| 6 | `docs/skills/feature-context.md` | **One sentence** in Requirements |
| 7 | `skills/setup-skills/templates/issue-tracker.md` | **One sentence** at bottom of Spec section |

**Do not change:** `bin/stack/link_impl_repo.sh` heredoc format.

---

## 1. CREATE `bin/lib/read_spec_repo.sh` (full file)

```bash
# shellcheck shell=bash
# Parse SPEC_REPO from docs/agents/issue-tracker.md (markdown list/bold tolerated).
# Usage: read_spec_repo_from_file [path]
read_spec_repo_from_file() {
  local file="${1:-docs/agents/issue-tracker.md}"
  [[ -f "$file" ]] || return 1

  local line
  line=$(grep -iE '(SPEC_REPO|spec_repo|Spec repo|spec repository)[[:space:]]*:' "$file" | head -1) || return 1
  [[ -n "$line" ]] || return 1

  line=$(sed -E 's/.*(SPEC_REPO|spec_repo|Spec repo|spec repository)[[:space:]]*:[[:space:]]*//I' <<<"$line")
  line=$(sed -E 's/^[[:space:]]*\**//' <<<"$line")
  line=$(tr -d '\r`' <<<"$line")
  line=$(sed -E 's/[[:space:]]+$//' <<<"$line")
  line=$(sed -E 's/\*+$//' <<<"$line")
  line=$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<<"$line")

  [[ "$line" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || return 1
  printf '%s\n' "$line"
}
```

**Parser steps:**

| Step | Command / rule |
| --- | --- |
| Find line | First line anywhere containing `SPEC_REPO:` (case variants) |
| Strip label | `sed` through label colon (case-insensitive `I` flag) |
| Strip markdown | Leading `*` / whitespace; remove `\r` and backticks; trailing `*` |
| Validate | `owner/name` regex; rejects `<owner>/<app>-spec>`, `__SPEC_REPO__` |

Safe to source under `set -euo pipefail`; returns exit 1 on missing/invalid input.

---

## 2. CREATE `bin/lib/test_read_spec_repo.sh` (full file)

```bash
#!/usr/bin/env bash
# Tests for read_spec_repo.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=read_spec_repo.sh disable=SC1091
source "${ROOT}/bin/lib/read_spec_repo.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $name — expected '$expected', got '$actual'" >&2
    exit 1
  fi
  echo "ok: $name"
}

assert_fail() {
  local name="$1"
  local file="$2"
  if read_spec_repo_from_file "$file" 2>/dev/null; then
    echo "FAIL: $name — expected failure, got success" >&2
    exit 1
  fi
  echo "ok: $name"
}

write_tracker() {
  local file="$tmpdir/issue-tracker.md"
  printf '%s\n' "$1" >"$file"
  printf '%s' "$file"
}

f=$(write_tracker '- SPEC_REPO: roborew/blocshed-spec')
assert_eq 'list plain' 'roborew/blocshed-spec' "$(read_spec_repo_from_file "$f")"

f=$(write_tracker '- **SPEC_REPO:** roborew/blocshed-spec')
assert_eq 'list bold' 'roborew/blocshed-spec' "$(read_spec_repo_from_file "$f")"

f=$(write_tracker 'SPEC_REPO: plain/value')
assert_eq 'bare line' 'plain/value' "$(read_spec_repo_from_file "$f")"

f=$(write_tracker '- **SPEC_REPO:** <owner>/<app>-spec>')
assert_fail 'placeholder rejected' "$f"

assert_fail 'missing file' "$tmpdir/missing.md"

echo "All read_spec_repo tests passed."
```

**Run after create:**

```bash
chmod +x ~/.config/opencode/bin/lib/test_read_spec_repo.sh
bash ~/.config/opencode/bin/lib/test_read_spec_repo.sh
```

Expected output:

```text
ok: list plain
ok: list bold
ok: bare line
ok: placeholder rejected
ok: missing file
All read_spec_repo tests passed.
```

---

## 3. MODIFY `templates/bin/issue-expand-bundle`

**Context:** File already sets `OC_ROOT="${OPENCODE_CONFIG:-$HOME/.config/opencode}"` near top (line ~6). Replace the SPEC_REPO extraction block only.

**REMOVE (before):**

```bash
IMPL_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
SPEC_REPO=""
if [[ -f docs/agents/issue-tracker.md ]]; then
  SPEC_REPO=$(grep -E '^[[:space:]]*(SPEC_REPO|spec_repo|Spec repo|spec repository):' docs/agents/issue-tracker.md \
    | head -1 | sed -E 's/^[^:]*:[[:space:]]*//' | tr -d '\r' || true)
fi
[[ -n "$SPEC_REPO" ]] || {
  echo "ERROR: docs/agents/issue-tracker.md must define SPEC_REPO. Run link-spec-repo / setup-project." >&2
  exit 2
}
```

**ADD (after):**

```bash
IMPL_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
# shellcheck source=read_spec_repo.sh disable=SC1091
source "${OC_ROOT}/bin/lib/read_spec_repo.sh"
SPEC_REPO=""
[[ -f docs/agents/issue-tracker.md ]] && SPEC_REPO=$(read_spec_repo_from_file docs/agents/issue-tracker.md || true)
[[ -n "$SPEC_REPO" ]] || {
  echo "ERROR: docs/agents/issue-tracker.md must define SPEC_REPO. Run link-spec-repo / setup-project." >&2
  exit 2
}
```

**Leave unchanged:** error message, PRD fetch logic, bundle output, `INCLUDE_CLOSED` flag handling.

---

## 4. MODIFY `templates/bin/feature-context`

**REMOVE (before):**

```bash
#!/usr/bin/env bash
# Hydrate tmp/feature-context.md from GitHub issue + parent PRD (spec repo from docs/agents/issue-tracker.md).
set -euo pipefail
ISSUE="${1:?issue number required}"
OUT="tmp/feature-context.md"
mkdir -p tmp

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
ISSUE_JSON=$(gh issue view "$ISSUE" --repo "$REPO" --json title,body,labels,url,number)

SPEC_REPO=""
if [[ -f docs/agents/issue-tracker.md ]]; then
  SPEC_REPO=$(grep -E '^[[:space:]]*(SPEC_REPO|spec_repo|Spec repo|spec repository):' docs/agents/issue-tracker.md | head -1 | sed -E 's/^[^:]*:[[:space:]]*//' | tr -d '\r' || true)
fi
if [[ -z "$SPEC_REPO" ]]; then
  echo "WARN: docs/agents/issue-tracker.md missing or no SPEC_REPO line — parent PRD fetch may fail. Run bin/link-spec-repo <owner/name>-spec" >&2
fi
```

**ADD (after):**

```bash
#!/usr/bin/env bash
# Hydrate tmp/feature-context.md from GitHub issue + parent PRD (spec repo from docs/agents/issue-tracker.md).
set -euo pipefail
ISSUE="${1:?issue number required}"
OC_ROOT="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
OUT="tmp/feature-context.md"
mkdir -p tmp

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
ISSUE_JSON=$(gh issue view "$ISSUE" --repo "$REPO" --json title,body,labels,url,number)

# shellcheck source=read_spec_repo.sh disable=SC1091
source "${OC_ROOT}/bin/lib/read_spec_repo.sh"
SPEC_REPO=""
[[ -f docs/agents/issue-tracker.md ]] && SPEC_REPO=$(read_spec_repo_from_file docs/agents/issue-tracker.md || true)
if [[ -z "$SPEC_REPO" ]]; then
  echo "WARN: docs/agents/issue-tracker.md missing or no SPEC_REPO line — parent PRD fetch may fail. Run bin/link-spec-repo <owner/name>-spec" >&2
fi
```

**Note:** `feature-context` warns instead of hard-failing (unlike `issue-expand-bundle`).

---

## 5. MODIFY `bin/stack/check_impl_wiring.sh`

**After existing `source common.sh` block, ADD:**

```bash
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=read_spec_repo.sh disable=SC1091
source "${ROOT}/bin/lib/read_spec_repo.sh"
```

**REPLACE inside the impl loop:**

```bash
# before:
grep -q '^SPEC_REPO:' "$impl/docs/agents/issue-tracker.md" 2>/dev/null || missing+=("SPEC_REPO line")

# after:
read_spec_repo_from_file "$impl/docs/agents/issue-tracker.md" &>/dev/null || missing+=("SPEC_REPO line")
```

---

## 6. MODIFY `docs/skills/feature-context.md`

In **Requirements**, replace:

```markdown
- **`docs/agents/issue-tracker.md`** must define `SPEC_REPO: owner/name` (use `bin/link-spec-repo` from the OpenCode config repo).
```

With:

```markdown
- **`docs/agents/issue-tracker.md`** must define `SPEC_REPO` as `owner/name` (markdown list lines like `- SPEC_REPO: …` or `- **SPEC_REPO:** …` are fine; use `bin/link-spec-repo` from the OpenCode config repo).
```

---

## 7. MODIFY `skills/setup-skills/templates/issue-tracker.md`

Replace:

```markdown
`bin/feature-context` reads **SPEC_REPO** from this file (first line matching `SPEC_REPO:`).
```

With:

```markdown
`bin/feature-context` reads **SPEC_REPO** from this file (first line containing `SPEC_REPO:`; markdown list/bold formatting is stripped).
```

---

## How impl bins get the fix (sync path)

`bin/stack/sync_impl_tooling.sh` copies these scripts from OpenCode config into each impl repo:

```bash
for script in feature-context issue-expand-bundle orchestrate-readiness-check feature-check; do
  install -m0755 "${OC}/templates/bin/${script}" "$IMPL/bin/${script}"
done
```

The **parser lib is not copied** — impl bins source it from `OC_ROOT` at runtime. Therefore:

1. OpenCode config must contain `bin/lib/read_spec_repo.sh`.
2. Impl repos must be re-synced to pick up updated `templates/bin/*` copies.

---

## Rollout (operator)

```bash
# 1. Verify parser in OpenCode config
bash ~/.config/opencode/bin/lib/test_read_spec_repo.sh

# 2. Re-sync impl tooling (example: blocshed-web)
~/.config/opencode/bin/stack/sync_impl_tooling.sh \
  /Users/robo/05_Repos/01_PROJECTS/apps/blocshed/blocshed-web

# 3. Re-run from impl repo root
cd /Users/robo/05_Repos/01_PROJECTS/apps/blocshed/blocshed-web
bin/issue-expand-bundle downgrade-archival-recovery
```

No edit required to `docs/agents/issue-tracker.md` if it already has `- SPEC_REPO: roborew/blocshed-spec`.

---

## Out of scope (explicit)

- Patching impl repos' `issue-tracker.md` to bare `SPEC_REPO:` at column 0.
- Changing markdown aesthetics in `link_impl_repo.sh`.
- Copying `read_spec_repo.sh` into impl repos (runtime source from OpenCode config only).

---

## Verification checklist

- [ ] `bin/lib/read_spec_repo.sh` exists with full content above
- [ ] `bin/lib/test_read_spec_repo.sh` is executable and passes
- [ ] `templates/bin/issue-expand-bundle` sources lib (no line-anchored `grep ^SPEC_REPO`)
- [ ] `templates/bin/feature-context` has `OC_ROOT` and sources lib
- [ ] `bin/stack/check_impl_wiring.sh` uses `read_spec_repo_from_file`
- [ ] Doc updates in `docs/skills/feature-context.md` and `skills/setup-skills/templates/issue-tracker.md`
- [ ] Target impl repo re-synced via `sync_impl_tooling.sh`
- [ ] `bin/issue-expand-bundle <slug>` succeeds with list-formatted `issue-tracker.md`

---

## Quick manual test (without full issue-expand-bundle)

From any directory, with a temp `issue-tracker.md`:

```bash
source ~/.config/opencode/bin/lib/read_spec_repo.sh
printf '%s\n' '- SPEC_REPO: roborew/blocshed-spec' > /tmp/issue-tracker.md
read_spec_repo_from_file /tmp/issue-tracker.md
# expected: roborew/blocshed-spec
```
