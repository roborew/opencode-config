---
name: feature-worktree
description: Coordinate feature and ticket worktrees via the worktree-manager subagent (which drives the /experimental/worktree API so worktrees and sessions register in the Desktop GUI).
---

# Feature Worktree

This skill is **routing only**: it does not perform worktree operations itself. All worktree lifecycle (create, list, delete, reset) is delegated to the `worktree-manager` subagent, which calls the four `worktree_*` tools registered by `plugins/worktree.js`. **Raw git worktree subcommands (`worktree add`, `worktree remove`, `branch opencode/...`) are forbidden** — they bypass GUI registration and are not coordinated with session start.

## Hard rules

1. The orchestrator (`orchestrate`) MUST NOT call worktree tools directly. Delegate to `worktree-manager` with a JSON-shaped `prompt` containing one `action`.
2. Never accept raw `git worktree` as a fallback path. On API failure, distinguish: (a) **dead upstream** (connection refused / 503) → surface `BLOCKED: WORKTREE_API_FAILED` and stop; the user must restart the opencode-server stack. (b) **recoverable `WorktreeNotGitError` (400)** → `worktree-manager` auto-invokes the sanctioned `recover` action (the system's own `rewrite-worktree-gitdirs.py` + session deregister), which is **not** raw `git worktree`. If recovery fails, then surface `BLOCKED: WORKTREE_API_FAILED`.
3. The pre-delete checks (pushed, clean) and the self-guard against `OPENCODE_APPS_DIR` are owned by `worktree-manager` and `plugins/worktree.js` respectively. Do not re-implement them here.
4. Naming convention is `feat-<slug>` for a feature, `ticket-<issue>-<slug>` for a ticket. The server auto-prefixes `opencode/`.
5. Branches always look like `opencode/feat-<slug>` and `opencode/ticket-<issue>-<slug>` (never `feature/...` or `ticket/...` on the wire).

## Setup (feature worktree)

Run inside the parent repo session. Issue a single `worktree-manager` Task:

```json
{
  "action": "create_feature",
  "slug": "<slug>",
  "base": "develop"
}
```

`worktree-manager` returns `{ ok: true, name, branch: "opencode/feat-<slug>", directory, base, reset_applied }`. Record `directory` and `branch` in the checkout contract. Push the branch yourself after the Task succeeds (the plugin does not push).

Present auto versus manual scheduling once; default to manual batches.

## Ticket fan-out

Build the dependency DAG from each ticket's `depends_on`. Batch independent tickets, sequence dependent or overlapping-file tickets, and for each ticket dispatch:

```json
{
  "action": "create_ticket",
  "issue": <int>,
  "slug": "<slug>",
  "base": "opencode/feat-<slug>"
}
```

Run test-writer RED, the Owner GREEN stage, and code-review ticket mode in the child. Open sub-PRs with `head=opencode/ticket-<issue>-<slug>` and `base=opencode/feat-<slug>`.

## Ticket teardown

After a child sub-PR merges, dispatch:

```json
{
  "action": "delete",
  "directory": "<ticket worktree dir>"
}
```

`worktree-manager` performs the pushed/clean pre-checks, then calls `worktree_delete`. In the feature worktree run `git fetch` followed by `git merge --ff-only origin/feat-<slug>` before dependent work. Never delete unmerged or unpushed work.

The feature worktree persists through PR stabilization. Only ticket worktrees are deleted on sub-PR merge. The feature worktree is deleted only after spec `feature-complete` merge (or manually by the user) — also via `worktree-manager`.

## Restart / recovery

When `opencode-server` restarts and worktree directories exist but no session is attached, dispatch:

```json
{
  "action": "reset",
  "directory": "<worktree dir>"
}
```

This calls `POST /experimental/worktree/reset` and reconciles the session linkage. After reset, re-list with `action: "list"` to confirm the GUI sees the worktree.

## Recovery

### Stuck worktrees (WorktreeNotGitError)

If worktrees are stuck in the GUI / `worktree_list` after a failed delete, dispatch:

```json
{
  "action": "recover",
  "directory": "<worktree dir>"
}
```

This runs the system's sanctioned cleanup script (`rewrite-worktree-gitdirs.py remove/prune/scrub`) and deregisters orphan sessions. It does **not** use raw `git worktree`.

## Failure response

If `worktree-manager` returns any `blocker_code`, surface it to the user verbatim (alongside `manualRecovery` if present) and stop. Do not retry, do not fall back, do not skip.