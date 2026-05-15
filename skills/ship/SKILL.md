---
name: ship
description: "Commit → push → PR with explicit confirmation at each step"
---

## Ship workflow

Use when the user wants to land changes safely.

1. **Status** — `git status`; list what will ship.
2. **Stage** — propose `git add` paths; **exclude** `.env*`, `*.pem`, `*lock*` unless user explicitly wants lockfiles, `node_modules/`, `dist/`, `build/`.
3. **Confirm** — ask user to confirm staged set.
4. **Commit** — draft message from `git log --oneline -10` style; user confirms body.
5. **Push** — feature branch only; never push to protected branches without user confirmation.
6. **PR** — `gh pr create` with title/body; user confirms.

## Hard rules

- No force push, `git reset --hard`, `git clean -f` / `-fd`, `git branch -D`, `git checkout .`, `git restore .`, or `rm -rf /` / `rm -rf ~`. No `DELETE` SQL without `WHERE`. No `DROP`/`TRUNCATE TABLE` without explicit user confirmation in chat.
- `git push --force-with-lease` only if user typed explicit approval **and** `OPENCODE_ALLOW_FORCE_PUSH=1` is set in the environment.
- Before running a risky git command, optionally validate with `scripts/preflight-git.sh '<command>'` from repo root (this config: `~/.config/opencode/scripts/`). Hook: `scripts/block-dangerous-git.sh` reads JSON stdin `{"tool_input":{"command":"..."}}` if your host supports PreToolUse-style interception (OpenCode: see README — not wired in `opencode.json` here).
- No secrets in commit message.
- Stop if tests fail or user cancels any step.
