# 2026-05-19 — CRLF line endings and architect bash permissions (allow-by-default)

**Session scope:** Fix `env: bash\r: No such file or directory` when running spec-repo `bin/fanout` and related tooling; stop architect permission prompts (`△ Permission required`) for routine spec work (`yq`, `file`, `gh`, `bin/*`) while keeping strict deny rules for destructive or local-mutating shell.

**Status:** Implemented and finalized in this chat. **Verify on disk before merge** — the workspace may have diverged since this session (e.g. later docs/commits may subsume or relocate the same files). **Companion docs (same or adjacent days):**

- [`2026-05-19-crlf-line-endings-hardening.md`](2026-05-19-crlf-line-endings-hardening.md) — deeper sync/`feature-upgrade`/`strip_crlf` hardening path
- [`2026-06-01-setup-project-workflow-and-deepseek-bash-fixes.md`](2026-06-01-setup-project-workflow-and-deepseek-bash-fixes.md) — narrowed redirect denies (`*>*` → spaced `* > *`); `validate-opencode-config.sh` profiles (later session)
- [`2026-06-01-feature-pipeline-and-architect-front-door.md`](2026-06-01-feature-pipeline-and-architect-front-door.md) — PRD parser / architect front door (later session)

**Primary slug referenced in chat:** `downgrade-archival-recovery` (blocshed-spec fanout path).

---

## Executive summary

| Area | Outcome |
| --- | --- |
| CRLF root cause | Windows-style `\r\n` on shell shebangs → `env: bash\r` on macOS/Linux |
| Repo hygiene | Bulk normalize **112** text files to LF in OpenCode config repo |
| Prevention | `.gitattributes`, `check-crlf.sh`, `normalize-line-endings.py`, `strip_crlf` on spec sync |
| Architect UX | Replaced **ask-by-default + long allowlist** with **allow-by-default + explicit deny list** |
| Spec skills | Added **`fanout-issues`** to architect skill allowlist and routing |
| Operator action | **New architect session** after config pull; **re-sync** stale spec repos |

---

## 1. Problem 1 — `bin/fanout` fails with `env: bash\r`

### Symptom

In a spec repo (e.g. during **downgrade-archival-recovery**):

```bash
./bin/fanout downgrade-archival-recovery
```

```text
env: bash\r: No such file or directory
```

The `\r` after `bash` in the error indicates a **CRLF shebang** (`#!/usr/bin/env bash\r`) or CRLF throughout copied `bin/*` scripts.

### Root cause

- Many files under `~/.config/opencode` (and copies in spec repos) had **CRLF** line endings.
- `.gitattributes` was incomplete and was itself CRLF, so Git did not enforce LF on checkout.
- `bin/stack/sync_spec_tooling.sh` copied templates into spec repos **without** normalizing line endings, so bad bytes persisted in `APP-spec/bin/`.

### Fix implemented (OpenCode config repo)

| Change | Purpose |
| --- | --- |
| **`scripts/normalize-line-endings.py`** | One-shot: walk repo tree, replace `\r\n` / lone `\r` with `\n` (skip binary via NUL check) |
| **Bulk run** | Normalized **112** files (agents, skills, `bin/`, `templates/spec-repo/bin/*`, `scripts/`, docs, etc.) |
| **Root `.gitattributes`** | `* text=auto eol=lf` plus `bin/**`, `scripts/**`, `templates/**` |
| **`scripts/check-crlf.sh`** | CI/local gate: fail if `\r` in `bin/`, `scripts/`, `templates/`, `.gitattributes` |
| **`bin/stack/sync_spec_tooling.sh`** | After each `install` into spec repo: **`strip_crlf`** (Python bytes normalize) via `sync_bin` helper |
| **`.github/workflows/config-integrity.yml`** | Added step: `bash scripts/check-crlf.sh` (paths trigger may need to include `bin/**` / `templates/**` if not already) |

### Operator recovery (spec repo)

Re-sync tooling from config (paths as installed on your machine):

```bash
"$HOME/.config/opencode/bin/stack/sync_spec_tooling.sh" /path/to/APP-spec
```

Or project-parent `setup-project` when that stack path is wired.

Verify:

```bash
file bin/fanout   # must NOT say "CRLF"
bin/fanout downgrade-archival-recovery   # expect "slug required" or real fanout, not bash\r
```

Optional one-shot in spec repo if sync is not enough:

```bash
python3 "$HOME/.config/opencode/scripts/normalize-line-endings.py" "$(pwd)"
```

---

## 2. Problem 2 — Architect △ Permission required on routine commands

### Symptom

Using **architect** in a **spec repo**, every unfamiliar bash command prompted approval, including:

- `yq --version`
- `file docs/prd/downgrade-archival-recovery.md`
- `bin/fanout <slug>`
- Other read-only diagnostics

This blocked PRD/fanout workflows and caused agents to stall or ask the human repeatedly.

### Root cause

`agents/architect.md` frontmatter used:

```yaml
permission:
  bash:
    "*": ask
    # … dozens of per-command "allow" lines …
```

Global `opencode.json` allows bash broadly, but **agent frontmatter overrides** global rules. Anything not explicitly `allow` matched `ask`.

Whitelisting (`yq`, `file`, `gh`, …) was **whack-a-mole**: each new command needed another line.

### Fix implemented — allow-by-default, deny dangerous

Replaced the long allowlist with:

```yaml
permission:
  bash:
    "*": allow
    # explicit denies: rm, mv, cp, mkdir, touch, chmod, ln, sudo,
    # destructive git (commit, push, reset, checkout, pull, clone, …),
    # in-place sed, package installs, shell file redirects, tee
```

**Still allowed without prompts (examples):** `yq`, `jq`, `file`, `xxd`, `gh` (issues/labels/PRs/search), `bin/fanout`, `bin/new-prd`, `bin/status`, `python3`, `rg`, `git diff`/`status`/`log`, discovery helpers.

**Still denied:** local tree mutation via shell (`rm`, `mv`, `cp`, `mkdir`, `git commit`, `git push`, `sed -i`, `* > *`, `* >> *`, `npm install`, etc.). **Markdown/PRD writes** remain **`edit: deny`** → **scribe** via Task.

### Related architect updates (same session)

| Item | Change |
| --- | --- |
| **`fanout-issues`** | Added to `permission.skill` allow map |
| **Skill routing** | Bullet: approved PRD → load `fanout-issues`, run `bin/fanout <slug>` |
| **Claude Context / Hard Rules** | Wording: shell fallback for discovery + GitHub/bin tooling; no local file mutation via shell |
| **`docs/RUNBOOK.md`** | Architect bash described as allow-by-default with deny list (not allowlist + ask) |

### Intermediate step (superseded in same chat)

Before allow-by-default, the session briefly added explicit allows for `yq`, `file`, `gh issue view`, `bin/fanout`, etc. That approach was **replaced** by `"*": allow` after user feedback (“every action architect needs … allowed”).

### Operator requirement

**Start a new architect session** (or `/reload` config) after pulling changes. Old sessions retain previous `permission.bash` rules.

---

## 3. Files touched (this chat)

| Path | Role |
| --- | --- |
| `scripts/normalize-line-endings.py` | Bulk CRLF → LF |
| `scripts/check-crlf.sh` | Guardrail script |
| `.gitattributes` (repo root) | Git LF normalization |
| `bin/stack/sync_spec_tooling.sh` | `strip_crlf` / `sync_bin` after install |
| `.github/workflows/config-integrity.yml` | `check-crlf.sh` in validate job |
| `agents/architect.md` | Bash `allow` + deny list; `fanout-issues` skill; routing/docs text |
| `docs/RUNBOOK.md` | Permission conventions paragraph |

**Templates / spec copies (content normalized in config repo):**

- `templates/spec-repo/bin/fanout`
- `templates/spec-repo/bin/lib/validate_tickets.py`
- `templates/spec-repo/bin/lib/toposort_tickets.py`
- `templates/spec-repo/bin/new-prd`, `bin/status`
- `bin/lib/oc-root.sh`, `bin/lib/migrate_repos_registry.py`
- Plus ~100 other CRLF text files across agents/skills/docs (see normalize script output in session)

---

## 4. Security model (unchanged intent)

| Layer | Rule |
| --- | --- |
| **Architect role** | Read-only coordinator; no direct source edits |
| **`edit: deny`** | No Write/Edit tools on architect |
| **Bash allow** | Planning/spec/GitHub tooling runs without prompts |
| **Bash deny** | No shell-based local file mutation, destructive git, installs, redirects to files |
| **Writes** | **scribe** (and delegated **developer** only where skills say GitHub comment/edit) |

---

## 5. Verification checklist

### OpenCode config repo

- [ ] `bash scripts/check-crlf.sh` → `check-crlf: ok`
- [ ] `find . -type f -path './bin/*' -print0 \| xargs -0 file \| grep CRLF` → empty
- [ ] `agents/architect.md` has `"*": allow` under `permission.bash` (not `"*": ask` with long allow list)
- [ ] `fanout-issues` in architect `permission.skill`
- [ ] `scripts/normalize-line-endings.py` and `scripts/check-crlf.sh` exist and are LF

### Spec repo (e.g. blocshed-spec)

- [ ] Re-run `sync_spec_tooling.sh` on spec path
- [ ] `file bin/fanout` → ASCII text, **no** CRLF
- [ ] `./bin/fanout <slug>` runs (may exit on validation, not on shebang)
- [ ] New **architect** session: `yq --version` and `file docs/prd/<slug>.md` run **without** △ prompt

### CI

- [ ] `config-integrity` workflow runs `check-crlf.sh` when `bin/`, `scripts/`, or `templates/` change (extend `paths:` if checks do not fire)

---

## 6. What this session did *not* do

- Did not commit or push (user rule: commit only on request).
- Did not run `bin/fanout downgrade-archival-recovery` to completion in chat (blocked earlier by CRLF/permissions; fixes were config-side).
- Did not replace **`2026-05-19-crlf-line-endings-hardening.md`** (wrapper `feature-upgrade`, impl sync, `.gitattributes` in spec template) — see that doc for the fuller hardening narrative.
- Did not fix DeepSeek V4 / OpenRouter `reasoning_content` tool loops — see **`2026-06-01-setup-project-workflow-and-deepseek-bash-fixes.md`** (later session).

---

## 7. Chat timeline (for auditors)

1. User hit `env: bash\r` on `./bin/fanout`; agent attempted CRLF convert via python (permission blocked in that turn).
2. Bulk `normalize-line-endings.py`, `.gitattributes`, `check-crlf.sh`, sync `strip_crlf`, CI hook.
3. User hit repeated △ on `yq`, then `file docs/prd/...`; expanded architect allowlist.
4. User requested no more prompts within strict security → architect bash flipped to **`"*": allow`** + deny list; RUNBOOK + `fanout-issues` routing updated.

---

*Document created for `TO REVIEW/` — filename prefix **`2026-05-19`** (date this chat completed its work). Sorts with other `2026-05-19-*` notes; before `2026-05-20-*` and later June sessions.*
