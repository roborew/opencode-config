---
name: orchestrate-bootstrap
description: "Fresh-session bootstrap: preflight choice, checkout identity, indexing readiness, work selection, and GitHub issue-expand readiness. Not for queue execution or recovery."
modelTier: "fast"
roleReminder: "Load before work selection; reload only when checkout identity changes."
---

> Hard Rules live in `agents/orchestrate.md`; this skill owns only startup gates and work selection.

## Procedure

1. If neither `env_gate_passed` nor `env_gate_declined` is recorded, ask exactly: `Run preflight now? (yes/no)`. On yes, Task `worktree-env` with `load: full`, then Task `preflight` with `load: full` using the repair-first flow. On no, record `env_gate_declined` and do not run preflight.
2. Always run checkout identity: Task `developer` with `load: minimal` to execute `skills/github-issue-run/lib/checkout-contract.sh`. Require `status: ok`, repo root, branch, worktree status, main checkout root, protected-branch status, head SHA, and branch policy. Stop on mismatch or protected branch before implementation/state mutation.
3. Run Claude Context readiness for the workspace path. If unavailable, record `MCP_FALLBACK`; discovery-heavy children must enforce their own readiness gate.
4. When no work source is supplied, present exactly:

```text
(1) Work from a GitHub `feature:<slug>` backlog in this repo? (primary — use for all new spec/targeted execution)
(2) Build / refresh this feature branch in Sysbox sandbox? (compose build/test + optional review URL — parallel with other work)
(3) Hand back to `architect` for remediation loop? (impl option 4 → **R** — re-check PR / tickets / feedback after you pushed fixes)
(4) Something else (debug, refactor, doc review, etc.) — describe the task; usually switch to `architect` unless they give a `feature:<slug>`, issue #, or narrow execution scope
```

5. For `(1)`, capture the kebab-case slug and Task `developer` with `load: minimal` to run `opencode-run impl orchestrate-readiness-check <slug>` with the verified repo-root expectation. PASS requires non-empty `stages[]` and implementation planning on every open feature ticket. FAIL stops and returns to spec architect option 1; never enter flat mode or local-plan compatibility.
6. For `(2)`, load `orchestrate-sandbox`; do not enter the GitHub queue. For `(3)`, stop with the implementation architect Phase R handoff. For `(4)`, route to architect unless the message supplies an explicit queue or sandbox request.

## Environment State

Track `worktree_env_checked`, canonical `{wt_root, main_root, files[]}` evidence, `preflight_repair_attempted`, and `sandbox_status`. Do not create an artifact for these values. One automatic repair pass is allowed; after a second identical report, stop with one `recommended_env_fix` and `LOOP_DETECTED` where applicable.
