# Worktree-sandbox bootstrap — validation harness

Run after changing `worktree-sandbox` / `plugins/sandbox.js` / orchestrate bootstrap rules. Validates config integrity and documents manual smoke scenarios for the linked-worktree compose-test-backend bring-up flow.

## Config integrity (local)

```bash
cd ~/.config/opencode
bash scripts/check-crlf.sh
bash scripts/validate-opencode-config.sh
```

**Pass criteria:** exit 0 from both scripts.

## Manual smoke — verification backend declined, checkout identity still captured

**Setup:** Open a session on a **feature/topic branch** (primary checkout or linked worktree). Ensure env is already usable (or accept that skipped worktree-sandbox means no auto-repair).

**Run:** New OpenCode session → **`orchestrate`** → choose GitHub backlog or provide `feature:<slug>`.

**Pass criteria:**
1. Orchestrate still runs **`checkout-contract.sh`** (via **`developer`** `load: minimal`) before work selection or issue transition.
2. Report includes `impl_repo_path`, `branch`, `is_linked_worktree`, `protected_branch`.
3. No subagent creates or switches branches; implementation Tasks include `expected_branch` and `branch_policy`.
4. If `protected_branch: true`, orchestrate stops before `state:in-progress` unless user confirms.

## Manual smoke — branch mutation blocked

**Run:** Attempt `git switch other-branch` or `git checkout -b new-feature` from an execution subagent context (or via `scripts/preflight-git.sh`).

**Pass criteria:** Command blocked by `block-dangerous-git.sh` / agent bash denies; subagent reports refusal or `CHECKOUT_CONTRACT_FAILED` rather than silently switching.

## Manual smoke — repairable linked worktree (fidget-web example)

**Setup:** Open a **linked git worktree** for an impl repo (e.g. `fidget-web` on branch `opencode/*`). Ensure main checkout has `.env` / `.env.local` at repo root. In the worktree, remove env files if present (do not delete main-checkout files):

```bash
cd /path/to/fidget-web-worktree
git rev-parse --path-format=absolute --git-dir   # should contain /.git/worktrees/
rm -f .env .env.local 2>/dev/null || true
rm -rf node_modules
```

**Run:** New OpenCode session in the worktree → **`orchestrate`** → answer **yes** to bootstrap.

**Pass criteria (first run):**
1. Orchestrate runs `worktree-sandbox` `mode: env_copy` once; report includes `wt_root`, `main_root`, per-file `is_regular_file`; `worktree_env: ok`.
2. Coder session (when kicked) runs `worktree-sandbox` `mode: probe_and_create` silently — `sandbox_id`, `backend`, `compose_test_file`, `build_seconds`, `warm_run_seconds` populated.
3. `Status: Ready`; `env_gate_passed`; work menu **(1)–(4)** appears.
4. No `(a)/(b)/(c)` option menu for routine setup.

**Pass criteria (second run — idempotency):** Same session or new session with env copies and `node_modules` already present → `worktree-sandbox` `mode: env_copy` reports `ok_existing` for every file; `mode: probe_and_create` reuses an existing sandbox via `sandbox status` and re-warms without rebuilding from scratch.

## Manual smoke — customized env copy preserved

In a linked worktree with an existing env copy, customize a setting (e.g. a separate database name):

```bash
cd /path/to/worktree
# After first worktree-sandbox env_copy created .env from main checkout:
echo "DATABASE_URL=postgres://localhost/my_worktree_db" >> .env
```

**Run:** Worktree-sandbox env_copy again (new session or rerun).

**Pass criteria:**
- `mode: env_copy` reports `ok_existing` for `.env` — does **not** overwrite the customized file.
- The plugin's per-file `is_regular_file: true` for `.env`.

## Manual smoke — legacy symlink migration

In a linked worktree with old symlink layout:

```bash
cd /path/to/worktree
ln -sf /path/to/main-checkout/.env .env
```

**Run:** Worktree-sandbox env_copy.

**Pass criteria:**
- `mode: env_copy` replaces symlink with a regular-file copy from main checkout (`worktree_env: ok`, `status: ok_replaced_symlink`).
- Post-check: `test -f .env && test ! -L .env`.

## Canonical verification commands (operator)

The plugin (`plugins/sandbox.js`) replaces the legacy scripts. To invoke a single tool manually for ground truth, use `node -e` against the plugin, or run the equivalent sandbox / docker CLI directly:

```bash
# env_copy ground truth
wt_root="$(git rev-parse --show-toplevel)"
common="$(git rev-parse --path-format=absolute --git-common-dir)"
main_root="$(dirname "$common")"
for f in .env .env.local; do
  [ -e "$main_root/$f" ] || continue
  echo "=== $f ==="
  test -f "$wt_root/$f" && test ! -L "$wt_root/$f" && echo "regular file: yes" || echo "regular file: NO"
done

# sandbox_status ground truth
sandbox status --id <sandbox_id> || docker compose -f docker-compose.test.yml ps

# sandbox_run_test ground truth (per-stage)
sandbox exec --id <sandbox_id> -- docker compose -f docker-compose.test.yml run --rm test
# OR direct docker compose on local dev:
docker compose -f docker-compose.test.yml run --rm test
```

**Runtime policy:** Compare `engines.node` to **project** Node (`mise` / `asdf` / `fnm` / `nvm` / `volta` / pin files). Host/PATH Node may be OpenCode image Node 22 for MCP — do **not** treat that as "upgrade Docker to Node 24."

## Manual smoke — worktree-sandbox permission posture (no .env prompts)

**Setup:** Start a session in a linked worktree whose main checkout has `.env` / `.env.local` at repo root. Ensure global `opencode.json` `permission.edit` still has `.env: deny`, `.env.*: deny`, `**/.env: deny`, `**/.env.*: deny`.

**Run:** New OpenCode session → **`orchestrate`** → bootstrap.

**Pass criteria:**
1. `worktree-sandbox` `mode: env_copy` raises no permission prompt for `.env` / `.env.local` — the agent holds no `read` / `edit` / `write` / `bash` tools; the `env_copy` plugin tool uses `fs.copyFile` and never touches `~/.config/opencode/**`.
2. `env_copy` returns its structured envelope without prompting.
3. `mode: probe_and_create` completes env-gate (`sandbox_create` reads `fs.stat` on `.env` for presence, no values, no edits).
4. If `sandbox` is ready, the plugin's optional `.env` / Infisical key-name presence checks run via `fs` only — no permission prompt.
5. **Validation of the agent-level posture:** `agents/worktree-sandbox.md` enables `write: false`, `edit: false`, `read: false`, `bash: false`, and `permission.edit: { "*": "deny" }` — the agent is plugin-tools-only. The `permission.bash` block is absent (no `bash` tool to gate).
6. **Negative check:** No agent outside `worktree-sandbox` reaches `.env` via the plugin — global `opencode.json` still denies `.env` for everyone else (developer, frontend-dev, code-review, etc.); they use the plugin's `sandbox_run_test` for test execution.
