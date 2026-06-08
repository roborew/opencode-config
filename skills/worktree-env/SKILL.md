---
name: worktree-env
description: "Linked git worktree: copy .env and .env.local from main checkout (bash/cp only)"
modelTier: "fast"
roleReminder: "Only create root env files as copies when in a linked worktree; otherwise skip. Idempotent — report ok_existing when a regular file already exists. One report and stop."
---

## Skill reference (optional load)

Load when the parent (`orchestrate`) delegates worktree env setup before preflight. Follow the **worktree-env** agent Hard Rules first.

## Purpose

When the workspace is a **linked git worktree**, ensure repo-root env files (default **`.env`**, **`.env.local`**) are **copies** of the main checkout files so each worktree can customize settings (e.g. a separate database) without affecting other checkouts. Use **`bash` + `cp` only** (no edit/write tools for secret contents).

Override the file list with space-separated **`WORKTREE_ENV_FILES`** (e.g. `WORKTREE_ENV_FILES=".env .env.local .env.development"`).

## Hard Rules

1. Do not read or print the contents of env files.
2. Do not modify env files in the main checkout—only create or replace copies **in the current worktree root**.
3. If a target env file in the worktree already exists as a **regular file** (not a symlink), report `ok_existing` for that file—do not overwrite (the user may have customized it).
4. Emit exactly one final report to the parent with **canonical evidence**, then stop.
5. **Idempotent:** If the worktree already has a regular file at the target path, report `ok_existing` and do not recopy.

## Detection

Run from **repository root** (`git rev-parse --show-toplevel`); `cd` there first if needed.

1. **Inside git:** `git rev-parse --is-inside-work-tree` → must be `true`; else `worktree_env: skipped_not_git`.
2. **Linked worktree:** `git_dir=$(git rev-parse --path-format=absolute --git-dir)`. If `git_dir` matches `*/.git/worktrees/*`, treat as linked. Otherwise **skip** with `worktree_env: skipped_not_linked_worktree` (primary checkout or unusual layout).
3. **Main checkout root:**
   - If **`PREFLIGHT_MAIN_REPO_ROOT`** is set and non-empty: `main_root="${PREFLIGHT_MAIN_REPO_ROOT%/}"`.
   - Else: `common=$(git rev-parse --path-format=absolute --git-common-dir)`; `main_root=$(dirname "$common")"`. (Assumes common dir is `<repo>/.git`; document in report if `separate-git-dir` breaks this.)
4. **Worktree root:** `wt_root=$(git rev-parse --show-toplevel)`.
5. **Files to copy:** `${WORKTREE_ENV_FILES:-.env .env.local}` (space-separated basenames only).

## Actions (linked worktree only)

For each basename `f` in the file list:

- `source="${main_root}/${f}"`; `target="${wt_root}/${f}"`.
- If **`source`** is not a readable path: **skip** this file (`skipped_missing_source` for `f`); continue other files.
- If **`target`** exists and is a **regular file** (`test -f` and not `test -L`): report `ok_existing` for this file (no `cp` needed).
- If **`target`** is missing, or is a **symlink** (legacy layout): run **`cp -f "$source" "$target"`** via bash. `cp` replaces symlinks with a regular-file copy.
- If **`cp`** fails: report `failed_cp` with command evidence — do not report success.

**Post-action verification (required for every copied file):** run `test -f "$target"` and `test ! -L "$target"`. If `cp` ran but verification fails, report `failed_cp` with command evidence — do not report success.

**Overall status:** `ok` if no file has `failed_cp`; any `failed_cp` → `worktree_env: failed_cp`.

## Permissions (OpenCode)

- **Prefer `cp` via `bash` only** (no `edit` tool on `.env`). Global `opencode.json` may deny edits to `.env`; many stacks still allow file copy through **bash**—try that first.
- **`external_directory`:** main checkout paths must be **allow** (not `ask`) so `cp` can read sources outside the worktree root without mid-session prompts.
- If `cp` is **denied by the sandbox**, add under **`agents/worktree-env.md`** `permission.edit` with `"*": deny` and `".env": allow` at repo root (mirror `scribe` patterns), then retry—or run the same `cp` command manually in a terminal.

## Output (structured)

Return to parent:

- `worktree_env`: `ok` | `skipped_not_git` | `skipped_not_linked_worktree` | `failed_cp`
- `wt_root`, `main_root`: absolute paths
- `files`: per-file `{ name, status: ok | ok_existing | skipped_missing_source | failed_cp, source, target, is_regular_file }` (paths only, not contents)
- `commands_run`: brief list (`cp`, `test -f`, `test ! -L`, etc.)
- `recommended_env_fix`: one line if failed
- If `failed_cp`, include `blocker_code: ENV_BLOCKED` only when the user cannot proceed to preflight without fixing this (orchestrate may still run preflight verification after manual fix)

## On success

Status ready for **`preflight`** agent: worktree env copies are in place or not required. Parent should set `worktree_env_checked: true` and store this report as `worktree_env_evidence` — do not expect a second **`worktree-env`** invocation in the same bootstrap unless canonical verification later contradicts this evidence.
