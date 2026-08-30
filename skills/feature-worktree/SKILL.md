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
4. Naming convention is `feat-<slug>` for a feature, `ticket-<issue>-<slug>-<abbrev>` for a ticket. The server auto-prefixes `opencode/`. `<abbrev>` is a 3–6-word kebab-case slug derived from the issue title by `worktree-manager` at `create_ticket` time; collisions within the same feature are suffixed `-2`, `-3`, …
5. Branches always look like `opencode/feat-<slug>` and `opencode/ticket-<issue>-<slug>-<abbrev>` (never `feature/...` or `ticket/...` on the wire).

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

> **Develop-loop path (default when `ORCHESTRATE_DEVELOP_LOOP` is unset or `1`):** the develop orchestrator loads `orchestrate-develop-loop` instead of running the manual schedule from this skill. The develop loop creates the feature worktree the same way, then for each runnable ticket creates a ticket worktree via `worktree-manager create_ticket` with `kickoff_agent` + `kickoff_message` (the plugin writes `<gitdir>/opencode-ticket-brief.json` and injects the message into the auto-started GUI session via `session.promptAsync`). The auto-started GUI session IS the ticket session — it loads `ticket-lifecycle`, reads the brief file, and reconstructs from GitHub (see `ticket-lifecycle` §0 Bootstrap). The develop loop owns batch sizing, auto-spawn, merge/cleanup; this skill still owns the worktree-creation JSON shapes and naming conventions it documents. `auto_spawn` on `create_ticket` is the orchestrator-side hint that the ticket Task should run unattended (no per-ticket prompts); `worktree-manager` echoes it back but never spawns anything itself.

## Ticket fan-out

Build the dependency DAG from each ticket's `depends_on`. Batch independent tickets, sequence dependent or overlapping-file tickets, and for each ticket dispatch:

```json
{
  "action": "create_ticket",
  "issue": <int>,
  "slug": "<slug>",
  "base": "opencode/feat-<slug>",
  "title": "<issue title>",
  "auto_spawn": true,
  "kickoff_agent": "developer" | "frontend-dev" | "ux-dev",
  "kickoff_message": "<short pointer — see ticket-lifecycle §0>"
}
```

`worktree-manager` derives `<abbrev>` from the title (or fetches it via `gh issue view`), dedupes collisions as `-2/-3`, and echoes `abbrev` + `auto_spawn` + kickoff status in the response. The plugin writes a durable brief file to `<worktree-gitdir>/opencode-ticket-brief.json`, polls for the auto-started GUI session, and injects the kickoff message via `session.promptAsync`. The auto-started GUI session **IS** the ticket session — it loads `ticket-lifecycle`, reads the brief file, reconstructs the rest from GitHub, and runs every stage + sub-PR stabilization internally. On the legacy `github-issue-run` path, run test-writer RED, the Owner GREEN stage, and code-review ticket mode in the child. Open sub-PRs with `head=opencode/ticket-<issue>-<slug>-<abbrev>` and `base=opencode/feat-<slug>`.

## Ticket teardown

After a child sub-PR merges, dispatch:

```json
{
  "action": "delete",
  "directory": "<ticket worktree dir>"
}
```

`worktree-manager` performs the pushed/clean pre-checks, then calls `worktree_delete`. In the feature worktree run `git fetch` followed by `git merge --ff-only origin/feat-<slug>` before dependent work. Never delete unmerged or unpushed work.

After a successful `delete`, **also delete the remote ticket branch** so it does not accumulate:

```json
HANDOFF_TO_DEVELOP_LOOP: {
  "action": "delete_remote_branch",
  "branch": "opencode/ticket-<issue>-<slug>-<abbrev>"
}
```

The develop orchestrator delegates `git push origin --delete` to a `developer` Task with `load: minimal`; the ticket session itself never deletes remote branches (per `agents/orchestrate.md` Hard Rule §82 addendum).

The feature worktree persists through PR stabilization. Only ticket worktrees are deleted on sub-PR merge. The feature worktree is deleted only after the feature-architect session merges the feature PR (via `worktree-manager`) — see `architect-feature-signoff/SKILL.md`.

## Hand-off markers

| Marker | Emitted by | Consumed by |
|---|---|---|
| `HANDOFF_TO_FEATURE_ARCHITECT` | develop orchestrator when the last ticket merges into `opencode/feat-<slug>` | architect agent in `opencode/feat-<slug>` (`architect-feature-signoff`) |
| `READY_FOR_HUMAN_REVIEW` | ticket session when sub-PR is green and comment-clean | develop orchestrator surfaces to user (single human gate per PR) |
| `BLOCKED` | ticket session on preflight-after-repair, CI-exhaustion, or cross-ticket review | develop orchestrator surfaces verbatim and pauses the batch |
| `ticket_report:` (issue comment) | ticket session on terminal report | develop orchestrator's `dev-loop-watch.sh` + `scripts/dev-loop-poller.sh` — durable wake channel and out-of-band merge detector |
| `DEV_LOOP_WAKE: { repo, feature, reason }` | poller (`scripts/dev-loop-poller.sh`) when `ticket_report:` delta detected | develop orchestrator; ignored if no active loop for that feature |

There is **no** `HANDOFF_TO_TICKET_SESSION` marker — the ticket session is the auto-started GUI session for the worktree, not a `task`-tool dispatch. The `session_notify` tool injects report-back messages into an existing session via `POST /session/{id}/prompt_async`; it does not dispatch a new subagent.

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