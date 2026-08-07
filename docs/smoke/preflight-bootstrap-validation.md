# Preflight bootstrap — validation harness

Run after changing preflight / worktree-env / orchestrate bootstrap rules. Validates config integrity and documents manual smoke scenarios for linked-worktree repair-first bootstrap.

## Config integrity (local)

```bash
cd ~/.config/opencode
bash scripts/check-crlf.sh
bash scripts/validate-opencode-config.sh
```

**Pass criteria:** exit 0 from both scripts.

## Manual smoke — preflight declined, checkout identity still captured

**Setup:** Open a session on a **feature/topic branch** (primary checkout or linked worktree). Ensure env is already usable (or accept that skipped preflight means no auto-repair).

**Run:** New OpenCode session → **`orchestrate`** → answer **no** to preflight → choose GitHub backlog or provide `feature:<slug>`.

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

**Run:** New OpenCode session in the worktree → **`orchestrate`** → answer **yes** to preflight.

**Pass criteria (first run):**
1. **`worktree-env`** runs once; report includes `wt_root`, `main_root`, per-file `is_regular_file`; `worktree_env: ok`.
2. **`preflight`** agent runs repair pass if needed (`mise exec -- pnpm install`, indexing).
3. `Status: Ready`; `env_gate_passed`; work menu **(1)–(5)** appears.
4. No `(a)/(b)/(c)` option menu for routine setup.

**Pass criteria (second run — idempotency):** Same session or new session with env copies and `node_modules` already present → preflight reports `ok_existing` / skips repair; **`worktree-env` not invoked again** when `worktree_env_checked` is set from prior success in same bootstrap (or on rerun after user requests, copies show `ok_existing`).

## Manual smoke — customized env copy preserved

In a linked worktree with an existing env copy, customize a setting (e.g. a separate database name):

```bash
cd /path/to/worktree
# After first preflight bootstrap created .env from main checkout:
echo "DATABASE_URL=postgres://localhost/my_worktree_db" >> .env
```

**Run:** Preflight bootstrap again (new session or rerun).

**Pass criteria:**
- **`worktree-env`** reports `ok_existing` for `.env` — does **not** overwrite the customized file.
- Preflight verifies `.env` is a regular file (`is_regular_file: true`).

## Manual smoke — legacy symlink migration

In a linked worktree with old symlink layout:

```bash
cd /path/to/worktree
ln -sf /path/to/main-checkout/.env .env
```

**Run:** Preflight bootstrap.

**Pass criteria:**
- **`worktree-env`** replaces symlink with a regular-file copy from main checkout (`worktree_env: ok`).
- Post-check: `test -f .env && test ! -L .env`.

## Canonical verification commands (operator)

Prefer the scripts (same JSON agents return):

```bash
bash ~/.config/opencode/scripts/worktree-env.sh              # copy + report (linked worktree only)
bash ~/.config/opencode/scripts/preflight-worktree-verify.sh # read-only verify
bash ~/.config/opencode/scripts/preflight-runtime.sh         # host vs project Node + engines
```

**Runtime policy:** Compare `engines.node` to **project** Node (`mise` / `asdf` / `fnm` / `nvm` / `volta` / pin files). Host/PATH Node may be OpenCode image Node 22 for MCP — do **not** treat that as “upgrade Docker to Node 24.”

Or validate ground truth without agents:

```bash
wt_root="$(git rev-parse --show-toplevel)"
common="$(git rev-parse --path-format=absolute --git-common-dir)"
main_root="$(dirname "$common")"
for f in .env .env.local; do
  [ -e "$main_root/$f" ] || continue
  echo "=== $f ==="
  test -f "$wt_root/$f" && test ! -L "$wt_root/$f" && echo "regular file: yes" || echo "regular file: NO"
done
bash ~/.config/opencode/scripts/preflight-runtime.sh | jq '{host: .host_node.version, project: .project_node.version, via: .project_node.via, engines_status}'
test -d node_modules && echo "node_modules: present" || echo "node_modules: MISSING"
```

## agent-run.zsh mise detection

```bash
~/.config/opencode/scripts/agent-run.zsh 'command -v mise; mise exec -- node -v 2>/dev/null || node -v'
```

**Pass criteria:** `mise` resolves (Homebrew or `~/.local/bin`) and `node -v` matches project `.mise.toml` when present.

## Manual smoke — preflight permission posture (no .env prompts)

**Setup:** Start a session in a linked worktree whose main checkout has `.env` / `.env.local` at repo root. Ensure global `opencode.json` `permission.edit` still has `.env: deny`, `.env.*: deny`, `**/.env: deny`, `**/.env.*: deny`.

**Run:** New OpenCode session → **`orchestrate`** → answer **yes** to preflight.

**Pass criteria:**
1. Neither **`worktree-env`** nor **`preflight`** raises a permission prompt for `.env` / `.env.local` (read, write, edit, or bash `cp` / `test -f` against them).
2. `preflight-worktree-verify.sh` runs and returns JSON without prompting.
3. `worktree-env.sh` completes the copy (or `ok_existing`) without prompting.
4. If `sandbox` is ready, preflight's optional `.env` / Infisical key-name presence notes complete via bash only (`grep -l`, `awk`, `test -e`) without a permission prompt.
5. **Validation of the agent-level override:** `agents/preflight.md` and `agents/worktree-env.md` contain `tools.read: false`, `permission.edit` with `".env": "allow"` / `".env.*": "allow"` / `"**/.env": "allow"` / `"**/.env.*": "allow"`, and `permission.external_directory: { "*": "allow" }`. The `permission.bash` block mirrors the dangerous denies from global `opencode.json` (`rm -rf /*`, `sudo *`, etc.) and has `"*": "allow"`.
6. **Negative check:** No agent outside `preflight` / `worktree-env` inherits those `.env` allows — global `opencode.json` still denies `.env` for everyone else (developer, frontend-dev, verifier, etc.).
