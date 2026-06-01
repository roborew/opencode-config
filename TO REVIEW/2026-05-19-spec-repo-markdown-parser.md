# 2026-05-19 — SPEC_REPO Markdown Parsing Fix

**Session scope:** Fix `bin/issue-expand-bundle` (and related impl-repo tooling) so `SPEC_REPO` is read correctly from markdown-formatted `docs/agents/issue-tracker.md`.

**Status:** Implemented and finalized in this chat. Re-sync implementation repos after pulling these changes into `~/.config/opencode`.

---

## Problem reported

Running from an implementation repo (e.g. `blocshed-web`):

```bash
bin/issue-expand-bundle downgrade-archival-recovery
```

Failed with:

```text
ERROR: docs/agents/issue-tracker.md must define SPEC_REPO. Run link-spec-repo / setup-project.
```

The file **did** define `SPEC_REPO`, but the script could not parse it.

---

## Root cause (confirmed by `xxd`)

`docs/agents/issue-tracker.md` contained a normal markdown list line:

```markdown
- SPEC_REPO: roborew/blocshed-spec
```

Hex at offset `0xdf`:

```text
2d 20 5350 4543 5f52 4550 4f3a 20   →  "- SPEC_REPO: roborew/blocshed-spec"
```

The scripts used a **line-anchored** grep:

```bash
grep -E '^[[:space:]]*(SPEC_REPO|spec_repo|Spec repo|spec repository):' docs/agents/issue-tracker.md
```

That pattern only allows optional whitespace before `SPEC_REPO:`. A list prefix `- ` is not whitespace, so the line never matched → `SPEC_REPO` stayed empty → exit 2.

| Line in file | Old grep matches? |
| --- | --- |
| `SPEC_REPO: owner/name` | Yes |
| `- SPEC_REPO: owner/name` | **No** (blocshed actual format) |
| `- **SPEC_REPO:** owner/name` | **No** (`link-spec-repo` template format) |

**Secondary issue:** `link_impl_repo.sh` generates `- **SPEC_REPO:** owner/name`. Even with a looser grep, the old `sed -E 's/^[^:]*:[[:space:]]*//'` would leave `** roborew/...` after the first colon for bold lines.

**Wiring check:** `bin/stack/check_impl_wiring.sh` used `grep -q '^SPEC_REPO:'`, so correctly wired repos could falsely report `INCOMPLETE: SPEC_REPO line`.

---

## Design decision

- **Keep** human-facing markdown in templates (`- **SPEC_REPO:** …` or `- SPEC_REPO: …`).
- **Harden parsers** to strip list markers, bold, and backticks before validating `owner/name`.
- **Do not** require hand-editing `issue-tracker.md` in existing impl repos.

---

## What was implemented

### 1. Shared parser — `bin/lib/read_spec_repo.sh`

New function `read_spec_repo_from_file [path]` (default path: `docs/agents/issue-tracker.md`):

| Step | Behavior |
| --- | --- |
| Find line | `grep -iE '(SPEC_REPO\|spec_repo\|Spec repo\|spec repository)[[:space:]]*:'` — first match anywhere on the line |
| Strip label | `sed` removes everything through the label colon (case-insensitive) |
| Strip markdown | Trim leading `*` / whitespace; `tr -d '\r\`'`; trim trailing `*` / whitespace |
| Validate | Require `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$` (rejects placeholders like `<owner>/<app>-spec>` and `__SPEC_REPO__`) |

Safe to source from scripts running under `set -euo pipefail`; returns 1 on missing/invalid input.

### 2. Impl-repo bins — `templates/bin/issue-expand-bundle`, `templates/bin/feature-context`

Replaced inline grep/sed with:

```bash
OC_ROOT="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
# shellcheck source=read_spec_repo.sh disable=SC1091
source "${OC_ROOT}/bin/lib/read_spec_repo.sh"
SPEC_REPO=""
[[ -f docs/agents/issue-tracker.md ]] && SPEC_REPO=$(read_spec_repo_from_file docs/agents/issue-tracker.md || true)
```

Existing error/warn messages unchanged (`issue-expand-bundle` hard-fails; `feature-context` warns).

Bins are installed into impl repos via `bin/stack/sync_impl_tooling.sh` (copies from `templates/bin/`).

### 3. Wiring check — `bin/stack/check_impl_wiring.sh`

Replaced:

```bash
grep -q '^SPEC_REPO:' "$impl/docs/agents/issue-tracker.md"
```

With:

```bash
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "${ROOT}/bin/lib/read_spec_repo.sh"
read_spec_repo_from_file "$impl/docs/agents/issue-tracker.md" &>/dev/null || missing+=("SPEC_REPO line")
```

### 4. Tests — `bin/lib/test_read_spec_repo.sh`

Shell test harness (run locally):

```bash
bash ~/.config/opencode/bin/lib/test_read_spec_repo.sh
```

Cases covered:

| Input line | Expected result |
| --- | --- |
| `- SPEC_REPO: roborew/blocshed-spec` | `roborew/blocshed-spec` |
| `- **SPEC_REPO:** roborew/blocshed-spec` | `roborew/blocshed-spec` |
| `SPEC_REPO: plain/value` | `plain/value` |
| `- **SPEC_REPO:** <owner>/<app>-spec>` | failure (invalid placeholder) |
| missing file | failure |

All tests passed when run at implementation time.

### 5. Documentation touch-ups

- `docs/skills/feature-context.md` — parsers accept markdown list/bold lines, not only bare `SPEC_REPO:` at column 0.
- `skills/setup-skills/templates/issue-tracker.md` — note that `bin/feature-context` reads the first line containing `SPEC_REPO:` and strips markdown formatting.

**Not changed:** `bin/stack/link_impl_repo.sh` heredoc format (still writes `- **SPEC_REPO:** __SPEC_REPO__`).

---

## Files touched (summary)

| File | Change |
| --- | --- |
| `bin/lib/read_spec_repo.sh` | **Added** — shared parser |
| `bin/lib/test_read_spec_repo.sh` | **Added** — unit tests |
| `templates/bin/issue-expand-bundle` | Source shared parser |
| `templates/bin/feature-context` | Source shared parser; add `OC_ROOT` |
| `bin/stack/check_impl_wiring.sh` | Use shared parser for SPEC_REPO check |
| `docs/skills/feature-context.md` | Doc: markdown list lines OK |
| `skills/setup-skills/templates/issue-tracker.md` | Doc: markdown stripping behavior |

---

## Rollout (operator)

After this OpenCode config is on disk:

1. Re-sync impl tooling into each target repo:

   ```bash
   ~/.config/opencode/bin/stack/sync_impl_tooling.sh /path/to/impl-repo
   ```

   Example for blocshed:

   ```bash
   ~/.config/opencode/bin/stack/sync_impl_tooling.sh \
     /Users/robo/05_Repos/01_PROJECTS/apps/blocshed/blocshed-web
   ```

2. Re-run the original command from the impl repo root:

   ```bash
   bin/issue-expand-bundle downgrade-archival-recovery
   ```

No edit required to `docs/agents/issue-tracker.md` if it already has `- SPEC_REPO: roborew/blocshed-spec` (or the link-spec-repo template line).

---

## Out of scope (explicit)

- Patching impl repos directly from the OpenCode config workspace.
- Changing markdown template aesthetics in `link_impl_repo.sh`.
- Migrating every repo’s `issue-tracker.md` to a plain `SPEC_REPO:` line at column 0.

---

## Review checklist

- [ ] `bin/lib/read_spec_repo.sh` exists and matches behavior above
- [ ] `templates/bin/issue-expand-bundle` and `templates/bin/feature-context` source the lib (no line-anchored `grep ^SPEC_REPO`)
- [ ] `bin/stack/check_impl_wiring.sh` uses `read_spec_repo_from_file`
- [ ] `bash bin/lib/test_read_spec_repo.sh` passes
- [ ] Target impl repo re-synced via `sync_impl_tooling.sh`
- [ ] `bin/issue-expand-bundle <slug>` succeeds with list-formatted `issue-tracker.md`
