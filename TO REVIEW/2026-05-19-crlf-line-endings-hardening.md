# 2026-05-19 — CRLF line endings hardening

**Session scope:** Diagnose and design out `env: bash\r: No such file or directory` failures in spec-repo `bin/*` scripts; resync blocshed-spec; harden sync and wrapper paths; document agent recovery.

**Session completed:** 2026-05-19 — when this chat finished implementing the CRLF hardening plan (P0–P4), not the later date the review doc was written.

**Status:** Finalized in chat. Verify on disk before merge — workspace may have diverged since this session.

---

## Objective

Prevent spec-repo shell scripts from failing on macOS/Linux due to **CRLF** (`\r\n`) line endings, especially the bootstrap failure where `./bin/feature-upgrade` cannot run its own tooling sync because bash never starts.

---

## Problem reported

While resyncing PRD tooling for **downgrade-archival-recovery** in **blocshed-spec**, running:

```bash
./bin/feature-upgrade downgrade-archival-recovery
```

failed immediately with:

```text
env: bash\r: No such file or directory
```

Investigation showed CRLF on the shebang line:

```text
#!/usr/bin/env bash\r
```

The same class of failure affects any `./bin/*` script (fanout, feature-check, sync-fanout-bodies, etc.).

An agent session initially attempted `sed -i`, `dos2unix`, and shell redirects (blocked by sandbox rules), then fixed files with inline Python before the upgrade could run. After CRLF was cleared, `feature-upgrade` proceeded and surfaced **unrelated** registry/ticket validation errors (`INCOMPLETE`, capability/owner mismatches).

---

## Root cause

### Technical mechanism

On Unix, the kernel reads the script’s first line as the interpreter path. CRLF appends `\r` to `bash`, so `/usr/bin/env` searches for a non-existent binary `bash\r`.

### Why copy is involved but not the primary bug today

Scripts reach spec repos via:

```text
OpenCode templates (LF) → install → strip_crlf → spec bin/* (LF)
```

OpenCode **templates** were already LF. [`strip_crlf`](bin/stack/sync_spec_tooling.sh) (added in commit `d257744`) normalizes every synced file. A **fresh sync** should not leave CRLF behind.

CRLF in **blocshed-spec** came from one or more of:

| Source | Mechanism |
| --- | --- |
| **Stale install** | Scripts copied before `strip_crlf` existed; never re-synced |
| **Post-sync corruption** | Editor or Git reintroduced CRLF; spec repo had no `.gitattributes` |
| **Manual edit** | Direct edits to `bin/*` outside the sync path |

### Bootstrap gap (chicken-and-egg)

[`templates/spec-repo/bin/feature-upgrade`](templates/spec-repo/bin/feature-upgrade) calls `sync_spec_tooling.sh` on each run — but **only after bash starts**. A CRLF shebang prevents that self-heal path.

The OpenCode **project-parent wrapper** [`bin/feature-upgrade`](bin/feature-upgrade) previously synced tooling only when the target script was **missing**, so it would `exec` a broken CRLF copy if the file already existed and was executable.

---

## Design decision: design out, don’t agent-fix

| Approach | Role |
| --- | --- |
| **Designed (already present)** | `strip_crlf` on sync; `.gitattributes` + `check-crlf.sh` in OpenCode config CI |
| **Designed (implemented this session)** | Wrapper always syncs before `exec`; ship `.gitattributes` to spec repos; agent docs |
| **Acceptable fallback** | `bash bin/script` or direct `sync_spec_tooling.sh` when `./bin/script` fails |
| **Avoid** | Agents looping `bin/*` with ad-hoc Python/sed per file |

---

## Changes implemented

### P0 — One-time heal: blocshed-spec

Ran from OpenCode config:

```bash
"$HOME/.config/opencode/bin/stack/sync_spec_tooling.sh" \
  /Users/robo/05_Repos/01_PROJECTS/apps/blocshed/blocshed-spec
```

**Result:**

- `bin/feature-upgrade` and `bin/feature-check` reported LF (no CRLF) via `file`.
- Sync exited **3** due to existing registry/ticket validation gaps — **not** a line-ending issue.
- `.gitattributes` installed in spec repo after P2 (see below).

### P1 — Wrapper always syncs before exec

**File:** [`bin/feature-upgrade`](bin/feature-upgrade)

**Before:** Sync ran only when `"${SPEC_PATH}/bin/feature-upgrade"` was not executable.

**After:** Always call `sync_spec_tooling.sh` when the OpenCode stack script exists, then `exec` the spec-repo script (mirrors in-spec template behaviour):

```bash
if [[ -x "${OC}/bin/stack/sync_spec_tooling.sh" ]]; then
  echo "==> Syncing spec tooling from OpenCode templates..."
  "${OC}/bin/stack/sync_spec_tooling.sh" "$SPEC_PATH" || true
fi

exec "${SPEC_PATH}/bin/feature-upgrade" "$SLUG"
```

**Why:** Project-parent invocations heal stale/CRLF copies even when scripts already exist.

### P2 — Propagate `.gitattributes` to spec repos

**New file:** [`templates/spec-repo/.gitattributes`](templates/spec-repo/.gitattributes)

```gitattributes
# Normalize line endings (CRLF breaks bin/* shebangs on macOS/Linux).
* text=auto eol=lf

*.sh text eol=lf
bin/** text eol=lf
```

**File:** [`bin/stack/sync_spec_tooling.sh`](bin/stack/sync_spec_tooling.sh)

Added after PRD/skill template copies:

```bash
if [[ -f "$TEMPLATE/.gitattributes" ]]; then
  cp "$TEMPLATE/.gitattributes" "$SPEC/.gitattributes"
fi
```

**Why:** Git and editors on Windows/mixed environments keep `bin/**` as LF in spec repos after sync.

### P3 — Agent and operator documentation

**File:** [`docs/RUNBOOK.md`](docs/RUNBOOK.md)

New section **Troubleshooting: CRLF / `env: bash\r`** covering:

- Symptom and cause
- Recovery: `bash bin/...`, `sync_spec_tooling.sh`, project-parent `feature-upgrade`
- Prevention via synced `.gitattributes`

**File:** [`skills/setup-project/SKILL.md`](skills/setup-project/SKILL.md)

New section **CRLF / broken `bin/*` shebangs** with delegated-bash recovery commands and pointer to RUNBOOK.

**Agent rule (documented):** Run OpenCode sync — never hand-edit line endings file-by-file.

### P4 — Template hygiene (`__pycache__`)

**Removed:** `templates/spec-repo/bin/lib/__pycache__/` (contained `.pyc` files that had shown CRLF in scans).

**New file:** [`templates/spec-repo/.gitignore`](templates/spec-repo/.gitignore)

```gitignore
# Python
__pycache__/
*.py[cod]
```

**Note:** `.gitignore` is for the template tree in OpenCode config; only `.gitattributes` is copied to spec repos by sync (per plan P2).

---

## Defences already in OpenCode config (pre-session, commit `d257744`)

These were **not** reimplemented in this session but are part of the full picture:

| Asset | Purpose |
| --- | --- |
| [`.gitattributes`](.gitattributes) | LF enforcement for `bin/`, `templates/`, `scripts/` in OpenCode config repo |
| [`scripts/check-crlf.sh`](scripts/check-crlf.sh) | CI gate — fails if tracked tooling contains `\r` |
| [`scripts/normalize-line-endings.py`](scripts/normalize-line-endings.py) | Bulk CRLF → LF for repo trees |
| [`strip_crlf` in `sync_spec_tooling.sh` / `sync_impl_tooling.sh`](bin/stack/sync_impl_tooling.sh) | Normalize after every `install` into spec/impl repos |
| [`.github/workflows/config-integrity.yml`](.github/workflows/config-integrity.yml) | Runs `check-crlf.sh` on PR/push |

---

## Recovery commands (reference)

From **spec repo** when `./bin/*` fails:

```bash
# Bypass shebang (no file mutation)
bash bin/feature-upgrade <slug>

# Re-sync all synced bin/* (preferred)
"$HOME/.config/opencode/bin/stack/sync_spec_tooling.sh" "$(pwd)"

# Bulk normalize working tree
python3 "$HOME/.config/opencode/scripts/normalize-line-endings.py" "$(pwd)"
```

From **project parent** (after P1):

```bash
feature-upgrade <slug>
feature-upgrade <slug> --spec /path/to/spec
```

---

## Files modified or added in session

| File | Change |
| --- | --- |
| `bin/feature-upgrade` | Always sync spec tooling before `exec` |
| `bin/stack/sync_spec_tooling.sh` | Copy `templates/spec-repo/.gitattributes` into spec repo |
| `templates/spec-repo/.gitattributes` | **New** — LF rules for spec repos |
| `templates/spec-repo/.gitignore` | **New** — ignore `__pycache__/` and `*.py[cod]` |
| `templates/spec-repo/bin/lib/__pycache__/` | **Removed** |
| `docs/RUNBOOK.md` | CRLF troubleshooting section |
| `skills/setup-project/SKILL.md` | CRLF recovery for agents |

**External (blocshed-spec, not in OpenCode repo):**

| Path | Change |
| --- | --- |
| `/Users/robo/05_Repos/01_PROJECTS/apps/blocshed/blocshed-spec/bin/*` | Re-synced; LF confirmed |
| `.../blocshed-spec/.gitattributes` | Installed by sync — commit in spec repo if desired |

**Not modified:** `strip_crlf` implementation, `check-crlf.sh`, OpenCode root `.gitattributes`, impl-repo sync logic (already had `strip_crlf`).

---

## Validation performed

During the session:

```bash
# OpenCode config repo
bash scripts/check-crlf.sh
# check-crlf: ok

# blocshed-spec after sync
file .../blocshed-spec/bin/feature-upgrade .../blocshed-spec/bin/feature-check
# UTF-8 text (no "with CRLF line terminators")

test -f .../blocshed-spec/.gitattributes && head -3 .../blocshed-spec/.gitattributes
# Normalize line endings (CRLF breaks bin/* shebangs on macOS/Linux).
```

**Not resolved in session:** blocshed-spec registry/ticket validation (`INCOMPLETE`, capability/owner mismatches for `roborew/blocshed-web` tickets). Those require setup-skills / registry updates, then re-run `feature-upgrade`.

---

## Review checklist

- [ ] Confirm [`bin/feature-upgrade`](bin/feature-upgrade) always calls `sync_spec_tooling.sh` before `exec`
- [ ] Confirm [`bin/stack/sync_spec_tooling.sh`](bin/stack/sync_spec_tooling.sh) copies `.gitattributes` when template file exists
- [ ] Confirm [`templates/spec-repo/.gitattributes`](templates/spec-repo/.gitattributes) and [`.gitignore`](templates/spec-repo/.gitignore) exist; no `__pycache__` under template `bin/lib/`
- [ ] Confirm RUNBOOK and setup-project skill CRLF sections
- [ ] Run `bash scripts/check-crlf.sh` in OpenCode config repo
- [ ] Re-run `sync_spec_tooling.sh` on any spec repo that may have pre-`d257744` bins; commit `.gitattributes` in spec repo
- [ ] From project parent, run `feature-upgrade <slug>` and confirm sync runs before spec script executes
- [ ] Address blocshed-spec registry/ticket validation separately from line endings

---

## References

- Plan artifact: `.cursor/plans/crlf_line_endings_d91849d6.plan.md` (do not edit as part of review merge)
- Prior fix commit: `d257744` — `fix: normalize line endings and enhance script validation`
- Related scripts: `bin/stack/sync_spec_tooling.sh`, `bin/stack/sync_impl_tooling.sh`, `templates/spec-repo/bin/feature-upgrade`
- Existing review doc format: `TO REVIEW/2026-05-20-setup-project-empty-targets-fix.md`
