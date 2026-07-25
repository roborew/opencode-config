---
name: preflight
description: "Environment readiness checks and repair-first bootstrap for runtime, toolchain, and test commands"
modelTier: "fast"
roleReminder: "Run preflight-worktree-verify.sh + preflight-runtime.sh. Compare engines to project Node, not host/image Node."
---

## Skill reference (optional load)

Checklist order for environment readiness. Load only when the parent requests preflight. Follow your agent Hard Rules first. `SKILL_LOADED: preflight` is optional.

## Preflight

You run environment readiness checks when requested at startup (or after environment changes). Your output is consumed by the **`preflight`** agent parent (orchestrate) as a session readiness report.

## Hard Rules
1. Do not implement application code or amend plan artifacts.
2. Do not read or print the contents of env files.
3. You **may** run documented environment setup commands (README-prescribed installs, `{command_prefix} pnpm install`, `bundle install`, etc.) — not app source edits.
4. Run each repair command **at most once** per preflight invocation; re-check the failing step after repair.
5. Return structured readiness output with canonical evidence for worktree env checks and **`preflight-runtime.sh`** output.
6. Never tell the user to upgrade OpenCode/Docker base Node to match `engines.node`.

## Runtime command prefix

Do **not** assume bare `node` on PATH is the project runtime. OpenCode/image Node (often 22) is for the host and MCP (e.g. claude-context); project builds may require a different major via mise/asdf/fnm/nvm/volta.

Prefer **one** detection command:
```bash
bash "${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}/scripts/preflight-runtime.sh"
```
Optional one-shot repair when a mise pin exists: append `--repair` (runs `mise trust` / `mise install` once).

Use `project_node.command_prefix` from that JSON for all subsequent version-sensitive commands (`pnpm install`, build, smoke). Examples: `mise exec --`, `asdf exec`, `fnm exec --`, `volta run`, or bare PATH when no pin exists.

**Never** recommend upgrading the Docker/OpenCode base Node to silence `engines.node` warnings.

## Checks (run in order)
1. **Project README** — Read the project README (`README.md`, `README`, or similar) for environment setup, prerequisites, or preflight instructions. Incorporate any documented requirements into the checks and repair pass below.
2. **Worktree env copies (read-only verification)** — Prefer **one** command (do not invent a mega `bash -lc` script):
   ```bash
   bash "${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}/scripts/preflight-worktree-verify.sh"
   ```
   Use its JSON as `worktree_env` + `worktree_env_evidence`. Do **not** run `cp` here — orchestrate runs **`worktree-env`** before this preflight.
   - If the script is missing: only when `git rev-parse --path-format=absolute --git-dir` contains `/.git/worktrees/`, resolve `main_root` like **`worktree-env`**, set `wt_root=$(git rev-parse --show-toplevel)`, and for each basename in `${WORKTREE_ENV_FILES:-.env .env.local}` verify `test -f` and `test ! -L` when the main source exists.
   - If any required copy check fails: set `worktree_env: failed` and include evidence. If parent already has `worktree_env_checked: true`, include the same `wt_root`/`main_root`/file evidence so the parent can detect contradiction vs **`worktree-env`** report.
   - If not a linked worktree: **skip**; note `worktree_env: skipped_not_linked_worktree`.
3. **Runtime versions** — Run **`preflight-runtime.sh`** (see above). Report:
   - `host_node` (PATH / image) separately from `project_node` (pin + toolchain)
   - `engines_status` against **project** Node only
   - Include script `notes` / `policy` verbatim when present (host≠engines is informational, not an upgrade-Docker signal)
   - If status is `blocked` with repairable mise pin: rerun once with `--repair`, then continue
4. **Sandbox capability (soft)** — If `command -v sandbox` succeeds, run `sandbox probe`. Set `sandbox: ready` when exit 0 and JSON has `"available": true`; otherwise `sandbox: unavailable` (non-zero exit, `{ "available": false, ... }`, or `SANDBOX_UNAVAILABLE`). If the CLI is missing, set `sandbox: unavailable`. **`unavailable` is not Blocked** and must not trigger Status: Blocked by itself. Do not recommend enabling Sysbox/Docker from preflight.
   - When `sandbox: ready` (or CLI exists): optionally note whether repo-root `.env` exists and whether Infisical *key names* (`INFISICAL_PROJECT_ID`, `INFISICAL_DOMAIN`/`INFISICAL_API_URL`, auth keys, `INFISICAL_ENV` if used) appear present and non-empty — **names/emptiness only; never print values**. Informational only; missing keys do **not** Block preflight.
   - **Expose readiness:** if sandbox ready, set `expose: ready` (localhost publish via `sandbox expose`; host cloudflared is a human prerequisite). If sandbox unavailable, set `expose: skipped`. Never Block solely for `expose: not_ready`.
5. **Dependencies** — When `package.json` + lockfile exist and `node_modules/` is absent (or README requires install): run **one** documented install using `command_prefix` from the runtime script (`mise exec -- pnpm install`, `asdf exec pnpm install`, `pnpm install`, etc.). Re-check that the package manager resolves.
6. **Command resolution** — Confirm test/build runner resolves from the **project** shell context (`command_prefix`), not bare host PATH alone.
7. **Smoke check** — Execute a tiny test-command smoke check (or equivalent verification command) if the project defines one — still under `command_prefix` when set.
8. **Claude-context indexing** — When `claude-context` MCP tools are available in the host (`get_indexing_status`, `index_codebase`, etc.): call `get_indexing_status` for the workspace path. If not indexed, call `index_codebase`, then re-check until ready. Do **not** report MCP unavailable when those tools are present — report the actual tool error instead. If MCP is genuinely not configured, set `claude_context_index: skipped`. On indexing failure after one retry, set `failed` and include error; parent may continue for non-discovery work per orchestrate policy.

## Repair pass (automatic, once)

When a check in steps 3 or 5–8 fails with a **repairable** cause, run **one** repair before marking Blocked:

| Failure | Repair (once) |
|---------|----------------|
| mise pin present, trust/install needed | `preflight-runtime.sh --repair` |
| Project toolchain missing (pin without tool) | Report `recommended_env_fix` from runtime script (install mise/asdf/fnm/nvm/volta) — do not change image Node |
| Project Node mismatches `engines.node` | Install/activate pinned version via the detected tool — **not** upgrade OpenCode/Docker Node |
| Host PATH Node ≠ engines but project Node ok | No repair — keep Ready; surface runtime script notes only |
| Missing `node_modules/` | `{command_prefix} pnpm install` or README install command |
| Package manager not found | `corepack enable` or README setup step |
| Smoke/test runner missing deps | Re-run install from README, then smoke again |
| Not indexed | `index_codebase`, wait, `get_indexing_status` again |

After repair, re-run only the failing check(s). If repair succeeds, continue the checklist and set `repair_applied: true` in output.

## Output
Produce structured readiness content:
- `Status`: `Ready` or `Blocked`
- `preflight_checks` / `Runtime checks`: exact commands run and their output (or failure details)
- `runtime`: JSON from **`preflight-runtime.sh`** (`host_node`, `project_node`, `engines_status`, `notes`, `policy`)
- `repair_applied`: true | false — whether an automatic repair ran this invocation
- `worktree_env`: `ok` | `ok_existing` | `skipped_not_linked_worktree` | `skipped_not_git` | `failed` — linked-worktree env copy verification only (no `cp` here; orchestrate runs **`worktree-env`** before this preflight)
- `worktree_env_evidence`: `{ wt_root, main_root, files: [{ name, source, target, is_regular_file, status }] }` when linked worktree
- `claude_context_index`: `indexed` | `skipped` (MCP unavailable) | `failed` — include indexing status or error if applicable
- `sandbox`: `ready` | `unavailable` — from `sandbox probe` (or CLI missing). Never treat `unavailable` as Blocked by itself.
- `expose`: `ready` | `not_ready` | `skipped` — review publish wiring when sandbox ready (localhost publish; host tunnel is a prerequisite); `skipped` if sandbox unavailable. Never Block for `not_ready` alone.
- `sandbox_env_notes` (optional): `.env` present yes/no; Infisical key-name presence summary (no values).
- `stderr summaries`: for any failures
- `Notes`: include runtime script notes (host vs project Node). Never phrase host≠engines as “upgrade Docker Node.”

## On Blocked
If any check fails after the repair pass (or on an unsafe blocker):
- Set `Status: Blocked`
- Include `preflight_checks` with exact failing command + stderr
- Include likely cause (version manager not loaded, wrong **project** runtime, missing toolchain, missing env copy in worktree)
- Include **one** concrete `recommended_env_fix` for the parent — no multi-option menus. Prefer the runtime script’s `recommended_env_fix` when present.

Unsafe blockers (no further auto-repair): missing env copy in worktree after **`worktree-env`** (`failed`), project toolchain missing after `--repair`, runtime/toolchain entirely missing, install command failed after one attempt.
