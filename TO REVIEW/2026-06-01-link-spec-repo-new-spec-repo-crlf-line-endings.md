# 2026-06-01 — `link-spec-repo` / `new-spec-repo` CRLF Line Endings Fix

**Session scope:** Diagnose and fix `env: bash\r: No such file or directory` when running `~/.config/opencode/bin/new-spec-repo`; normalize line endings on `bin/link-spec-repo` and `bin/new-spec-repo`; add Git attributes so `bin/*` stays LF; confirm both scripts remain valid after staging in the editor.

**Session completed:** 2026-06-01 — when this chat finalized the CRLF fixes, `.gitattributes` update, and post-staging verification. (The `16 May` timestamps in the operator’s `mycelia-tree` `ls` output were existing folder dates, not the session date.)

**Status:** Implemented and finalized in this chat. **Verify on disk before merge** — this repo may have since reorganized (e.g. `bin/` removed or scripts consolidated under `bin/stack/` / `setup-project`). Search for the behaviors below in the active entrypoint if paths differ.

**Related sessions (same or adjacent dates):**

- [`2026-05-19-crlf-line-endings-hardening.md`](2026-05-19-crlf-line-endings-hardening.md) — spec-repo sync path, `strip_crlf`, bulk normalize, CI gate
- [`2026-06-01-crlf-line-endings-and-architect-bash-permissions.md`](2026-06-01-crlf-line-endings-and-architect-bash-permissions.md) — broader CRLF + architect permission work (separate session)
- [`2026-06-01-readme-web-mobile-naming-and-new-spec-repo-automation.md`](2026-06-01-readme-web-mobile-naming-and-new-spec-repo-automation.md) — `new-spec-repo` create-or-sync behavior (separate session)

**Operator context at session start:** `mycelia-tree` parent folder with sibling repos `mycelia-tree-frontend` and `mycelia-tree-api` already present locally.

---

## Executive summary

| Area | Outcome |
| --- | --- |
| Symptom | `new-spec-repo` failed immediately with `env: bash\r: No such file or directory` |
| Root cause | Windows-style **CRLF** (`\r\n`) on shell shebangs — kernel/`env` looks for `bash\r` |
| Files fixed | `bin/new-spec-repo`, `bin/link-spec-repo` normalized to **LF-only** |
| Prevention | Root `.gitattributes` extended with `bin/* text eol=lf` |
| Permissions | Both scripts confirmed **executable** (`chmod +x`) |
| Validation | `file`, `rg` (no `\r`), `bash -n` — all passed |
| Editor UX | Files “disappearing” after **Stage** was explained as clean working tree / committed state, not deletion |

---

## 1. Problem reported

### Command

From the application parent folder (`~/05_Repos/01_PROJECTS/apps/mycelia-tree`):

```bash
~/.config/opencode/bin/new-spec-repo mycelia-tree mycelia-tree-frontend mycelia-tree-api
```

### Failure

```text
env: bash\r: No such file or directory
```

The script never started. Local sibling repos (`mycelia-tree-frontend`, `mycelia-tree-api`) already existed; the failure blocked spec-repo bootstrap before any `gh repo create` output.

### Secondary report

After attempting to stage fixes in the editor, both `bin/link-spec-repo` and `bin/new-spec-repo` **vanished from the Source Control view** and appeared as generic **text** rather than shell scripts in some UI surfaces.

---

## 2. Root cause

### Technical mechanism

On macOS/Linux, the kernel reads the first line of an executable script as the interpreter path. With CRLF, the shebang is effectively:

```text
#!/usr/bin/env bash\r
```

`/usr/bin/env` then searches for a binary named `bash\r`, which does not exist → `env: bash\r: No such file or directory`.

### Why both scripts were affected

| File | CRLF state at investigation |
| --- | --- |
| `bin/new-spec-repo` | Had CRLF on first report; fixed in first pass of this chat |
| `bin/link-spec-repo` | Still had CRLF on second pass — `file` reported *with CRLF line terminators* |

CRLF also causes some tools (Finder, certain editors) to treat scripts as plain **text** instead of Unix shell executables, even when `chmod +x` is set.

### Why `.gitattributes` alone was insufficient

At session time the repo had `*.sh text eol=lf` but **`bin/link-spec-repo` and `bin/new-spec-repo` have no `.sh` extension**, so Git did not enforce LF on checkout/commit for those paths until `bin/*` was added.

---

## 3. What was implemented

### 3.1 Strip CRLF from both scripts

One-shot normalize (macOS):

```bash
sed -i '' 's/\r$//' ~/.config/opencode/bin/link-spec-repo ~/.config/opencode/bin/new-spec-repo
```

Effect: every line ends with `\n` only; shebang becomes `#!/usr/bin/env bash\n`.

### 3.2 Ensure executability

```bash
chmod +x ~/.config/opencode/bin/link-spec-repo ~/.config/opencode/bin/new-spec-repo
```

Both were already mode `755`; command was idempotent confirmation.

### 3.3 Extend root `.gitattributes`

Added alongside existing `*.sh text eol=lf`:

```gitattributes
bin/* text eol=lf
```

Purpose: keep extensionless `bin/*` helpers on LF in future checkouts and commits.

### 3.4 Verification performed in chat

| Check | Expected | Result |
| --- | --- | --- |
| `file bin/link-spec-repo bin/new-spec-repo` | *Bourne-Again shell script text executable* — **no** “CRLF” | Pass |
| `rg $'\r' bin/link-spec-repo bin/new-spec-repo` | No matches | Pass |
| `bash -n bin/link-spec-repo` | Exit 0 | Pass |
| `bash -n bin/new-spec-repo` | Exit 0 | Pass |
| `od -c` on shebang line | `bash` then `\n` only | Pass |
| `git ls-files bin/link-spec-repo bin/new-spec-repo` | Both tracked | Pass |

### 3.5 Git / commit state at end of chat

After the user staged changes, investigation showed:

- **`git status`:** clean working tree (`nothing to commit`)
- **Files on disk:** both scripts present, non-empty, executable
- **Likely commit captured in session:** `d159b06` — *chore: update .gitattributes to enforce LF line endings for bin directory*

**“Disappeared” files explanation:** Once changes are fully staged and/or committed, the Source Control panel only lists **pending** diffs. A clean tree means the files remain in the repo but no longer appear in the changes list — not that they were deleted.

---

## 4. Script inventory (content unchanged by CRLF fix)

Line-ending normalization was **non-functional** — script logic was not edited in this chat. Brief reference:

### `bin/new-spec-repo`

- Creates `{GH_ORG}/{app}-spec` via `gh repo create … --clone`
- Copies scaffold from `templates/spec-repo/`
- Writes `docs/agents/repos.md` from target repo arguments
- Commits, pushes, optional branch protection, label seeding via `yq`/`jq`

**Usage (at session time):**

```bash
GH_ORG=roborew new-spec-repo <app-slug> [target-repo ...]
```

### `bin/link-spec-repo`

- Run **inside** an implementation repo
- Writes `docs/agents/issue-tracker.md` with `SPEC_REPO`
- Installs `bin/feature-context` from OpenCode templates when missing
- Appends scratch paths to `.gitignore` (`tmp/`, `.research/`, etc.)

**Usage:**

```bash
link-spec-repo <owner/name-of-spec-repo>
```

---

## 5. Operator recovery

### Re-run bootstrap after fix

From the app parent folder (adjust paths and repo names):

```bash
~/.config/opencode/bin/new-spec-repo mycelia-tree mycelia-tree-frontend mycelia-tree-api
```

If the spec repo was **never created** (script failed on startup), no rollback is required.

If **`roborew/mycelia-tree-spec` already exists** from a partial run, later sessions may use create-or-sync behavior — see [`2026-06-01-readme-web-mobile-naming-and-new-spec-repo-automation.md`](2026-06-01-readme-web-mobile-naming-and-new-spec-repo-automation.md).

### Verify scripts locally

```bash
file ~/.config/opencode/bin/new-spec-repo ~/.config/opencode/bin/link-spec-repo
bash -n ~/.config/opencode/bin/new-spec-repo
bash -n ~/.config/opencode/bin/link-spec-repo
```

Must **not** see “CRLF” in `file` output.

### Prevent recurrence

- Keep **`bin/* text eol=lf`** in root `.gitattributes`
- In Cursor/VS Code: **Files: Eol** → `\n` for this repo
- After editing shell scripts on Windows or via copy/paste, re-run `sed` or `scripts/check-crlf.sh` if present

---

## 6. Files touched in this session

| Path | Change |
| --- | --- |
| `bin/new-spec-repo` | CRLF → LF |
| `bin/link-spec-repo` | CRLF → LF |
| `.gitattributes` | Added `bin/* text eol=lf` |

**Not in scope this chat:** `templates/spec-repo/bin/*`, sync scripts, architect permissions, `new-spec-repo` branch/git-flow logic (documented in sibling TO REVIEW files).

---

## 7. Acceptance checklist

- [ ] `bin/new-spec-repo` and `bin/link-spec-repo` exist and are executable
- [ ] Neither file contains `\r` bytes
- [ ] `file` identifies both as Bourne-Again shell scripts (no CRLF mention)
- [ ] `bash -n` passes on both
- [ ] Root `.gitattributes` includes `bin/* text eol=lf`
- [ ] `new-spec-repo` runs without `env: bash\r` from the opencode config path
- [ ] After commit, Source Control is clean; scripts still open from `bin/` in the tree

---

## 8. Follow-ups (optional, not done here)

| Item | Notes |
| --- | --- |
| Rename `mycelia-tree-frontend` → `mycelia-tree-web` | Naming convention in later README sessions |
| Bulk CRLF audit of entire config repo | Covered in [`2026-05-19-crlf-line-endings-hardening.md`](2026-05-19-crlf-line-endings-hardening.md) |
| CI gate for `bin/*` without `.sh` | Ensure `scripts/check-crlf.sh` includes `bin/` if not already |
| Consolidation into `setup-project` | If `bin/new-spec-repo` becomes a shim, port LF normalization + `.gitattributes` policy to the active stack path |
