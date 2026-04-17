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

- No force push. No secrets in commit message.
- Stop if tests fail or user cancels any step.
