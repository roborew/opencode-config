---
name: debug-fix
description: "Reproduce, trace code + git history, minimal fix, regression test"
---

## Debug-fix workflow

1. **Reproduce** — minimal repro steps or failing test.
2. **Trace** — read code path; use `git log --oneline -- path` and `git log -S'symbol' -- path` for regressions.
3. **Root cause** — one paragraph; cite files/lines.
4. **Fix** — smallest change; add **regression test** that fails before fix and passes after.
5. **Verify** — run targeted tests.

## Git history

When the bug is a regression, use `git bisect` only if user approves time cost; otherwise narrow with `git log -S` and blame.
