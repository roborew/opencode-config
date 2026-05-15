---
name: hotfix
description: "Minimal emergency fix from main, hotfix branch, [HOTFIX] PR"
---

## Hotfix workflow

1. Confirm production urgency and scope.
2. `git fetch` and branch `hotfix/<short-slug>` from `main` or default release branch (ask user).
3. Make the **smallest** change that fixes the incident. No drive-by refactors.
4. Run **only** tests relevant to the touched paths.
5. Open PR with `[HOTFIX]` prefix; describe rollback.

## Stop conditions

- If change touches **>3 files** or alters public APIs, warn: likely not a hotfix — use normal feature flow.

## Git safety (same as ship)

Never: force push (unless user + `OPENCODE_ALLOW_FORCE_PUSH=1` for `--force-with-lease` only), `git reset --hard`, `git clean -f` / `-fd`, `git branch -D`, `git checkout .`, `git restore .`, destructive `rm -rf` on `/` or `~`. Validate with `scripts/preflight-git.sh '<command>'` when unsure. See `scripts/block-dangerous-git.sh` for hook-shaped checks.
