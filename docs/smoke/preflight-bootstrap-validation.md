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

**Setup:** Open a **linked git worktree** for an impl repo (e.g. `fidget-web` on branch `opencode/*`). Ensure main checkout has `.env` / `.env.local` at repo root. In the worktree, remove symlinks if present (do not delete main-checkout files):

```bash
cd /path/to/fidget-web-worktree
git rev-parse --path-format=absolute --git-dir   # should contain /.git/worktrees/
rm -f .env .env.local 2>/dev/null || true
rm -rf node_modules
```

**Run:** New OpenCode session in the worktree → **`orchestrate`** → answer **yes** to preflight.

**Pass criteria (first run):**
1. **`worktree-env`** runs once; report includes `wt_root`, `main_root`, per-file `readlink` + `is_symlink`; `worktree_env: ok`.
2. **`preflight`** agent runs repair pass if needed (`mise exec -- pnpm install`, indexing).
3. `Status: Ready`; `env_gate_passed`; work menu **(1)–(4)** appears.
4. No `(a)/(b)/(c)` option menu for routine setup.

**Pass criteria (second run — idempotency):** Same session or new session with symlinks and `node_modules` already present → preflight reports `ok_existing` / skips repair; **`worktree-env` not invoked again** when `worktree_env_checked` is set from prior success in same bootstrap (or on rerun after user requests, symlinks show `ok_existing`).

## Manual smoke — hard block (regular env file)

In a linked worktree, create a real file (not symlink):

```bash
cd /path/to/worktree
echo "test=1" > .env
```

**Run:** Preflight bootstrap.

**Pass criteria:**
- **`worktree-env`** reports `blocked_regular_file` / `ENV_BLOCKED`.
- Orchestrate stops with **one** remediation line (move/remove real `.env` in worktree).
- No automatic overwrite of the file.

## Canonical verification commands (operator)

Use these to validate ground truth without re-running full agents:

```bash
wt_root="$(git rev-parse --show-toplevel)"
common="$(git rev-parse --path-format=absolute --git-common-dir)"
main_root="$(dirname "$common")"
for f in .env .env.local; do
  [ -e "$main_root/$f" ] || continue
  echo "=== $f ==="
  test -L "$wt_root/$f" && echo "symlink: yes" || echo "symlink: NO"
  [ -L "$wt_root/$f" ] && readlink "$wt_root/$f"
done
mise exec -- node -v 2>/dev/null || node -v
test -d node_modules && echo "node_modules: present" || echo "node_modules: MISSING"
```

## agent-run.zsh mise detection

```bash
~/.config/opencode/scripts/agent-run.zsh 'command -v mise; mise exec -- node -v 2>/dev/null || node -v'
```

**Pass criteria:** `mise` resolves (Homebrew or `~/.local/bin`) and `node -v` matches project `.mise.toml` when present.
