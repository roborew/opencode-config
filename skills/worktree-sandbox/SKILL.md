---
name: worktree-sandbox
description: "Compose-test backend lifecycle for one linked git worktree (env copy + sandbox bring-up + per-stage test runs + teardown). Loaded by the worktree-sandbox agent on load: full. Tools live in plugins/sandbox.js — this skill documents the mode matrix and lifecycle, not the tool schemas."
modelTier: "fast"
roleReminder: "Coordinate via plugin tools only — never re-invent a docker compose invocation. Entry/exit only: stage implementers call sandbox_run_test directly from the plugin."
---

## Skill reference (optional load)

Load when the parent (`orchestrate` or `coder`) dispatches the `worktree-sandbox` subagent with `load: full`. Follow the **worktree-sandbox** agent Hard Rules first. `SKILL_LOADED: worktree-sandbox` is optional.

## Purpose

The `worktree-sandbox` subagent owns the **compose-test backend lifecycle** for one linked git worktree (ticket or feature). It collapses the legacy `worktree-env` → `preflight` → `developer`-build → `developer`-warm dance into a single coordinator that drives `plugins/sandbox.js`. Every tool the agent calls is one of the 8 plugin tools; every command the agent wants to run is delegated to the plugin.

## Plugin tools (by reference, not duplicated)

The plugin registers 8 tools in `plugins/sandbox.js`. The agent calls them by name; this skill does not duplicate the JSON schema — see the plugin source for arg shapes. Names and one-line purpose:

| Tool | Purpose |
|------|---------|
| `sandbox_probe` | Resolves `OPENCODE_SANDBOX_ENABLED`, `command -v sandbox`, `command -v docker`. Returns `{ sandbox, docker, recommended_backend }`. |
| `env_copy` | Copies `.env` / `.env.local` / `WORKTREE_ENV_FILES` from main checkout to worktree; replaces legacy symlinks. No contents, no `.env.example`. |
| `sandbox_create` | `sandbox create --id <id> --worktree <path>` (or no-op + warning when sandbox: unavailable). One sandbox per worktree. |
| `sandbox_build` | `sandbox exec --id <id> -- docker compose -f <file> build` (or direct docker compose). Idempotent. |
| `sandbox_warm` | Smoke command inside the compose service — replaces cold-boot-on-first-RED. |
| `sandbox_run_test` | Per-stage test runner — `sandbox exec --id <id> -- docker compose -f <file> run --rm <service> <command>` with optional `test_filter`. |
| `sandbox_status` | Read-only sandbox status. |
| `sandbox_destroy` | `sandbox destroy --id <id>` (unexpose first by default). Owned by `worktree-sandbox` (mode: teardown) and `code-review` per `docker-sandbox` §5. |

The Infisical env-gate runs inside `sandbox_create` (no values, key names only — per `docker-sandbox` skill §5). The Direct-Docker fallback is automatic when `sandbox probe` reports `sandbox: unavailable` and `docker: ready` — every tool accepts both backends and routes accordingly. The plugin never invents an invocation form.

## Mode matrix

The `worktree-sandbox` agent runs **exactly one** mode per Task. The parent sequences them.

| Mode | Tools called | Trigger |
|------|--------------|---------|
| `env_copy` | `env_copy` | Orchestrate bootstrap, before any verification backend setup. |
| `probe_and_create` | `sandbox_probe` → `sandbox_create` → `sandbox_build` → `sandbox_warm` | Coder §0.3 entry (ticket or feature), once per worktree. |
| `status` | `sandbox_status` | Ad-hoc — coder asks when in doubt. |
| `teardown` | `sandbox_status` (confirm idle) → `sandbox_destroy` | Coder §0-completion, before posting `ticket_report:` / `feature_report:`. |

## Lifecycle

```text
                    ┌───────────────────────────────────────────────┐
                    │   Orchestrate bootstrap (develop branch)      │
                    └────────────────────┬──────────────────────────┘
                                         │ Task worktree-sandbox mode: env_copy
                                         ▼
                    ┌───────────────────────────────────────────────┐
                    │   env_copy (one Task)                        │
                    │   → wt_root, main_root, files[]               │
                    └────────────────────┬──────────────────────────┘
                                         │
                                         ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │   Coder §0.3 (ticket OR feature worktree) — one Task             │
   │   Task worktree-sandbox mode: probe_and_create                   │
   │   → sandbox_probe → sandbox_create → sandbox_build → sandbox_warm│
   │   → sandbox_id, backend, compose_test_file, build_seconds,        │
   │     warm_run_seconds                                              │
   └────────────────────┬─────────────────────────────────────────────┘
                        │
                        ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │   Stage loop (per stage[] entry in opencode-task-yaml)           │
   │   test-writer (RED), developer/frontend-dev/ux-dev (GREEN),       │
   │   code-review (per-stage focused).                                │
   │                                                                  │
   │   These callers invoke `sandbox_run_test` from the plugin         │
   │   DIRECTLY — worktree-sandbox is NOT in this path.                │
   └────────────────────┬─────────────────────────────────────────────┘
                        │
                        ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │   Coder §0-completion (ticket OR feature worktree) — one Task    │
   │   Task worktree-sandbox mode: teardown                            │
   │   → sandbox_status (confirm idle) → sandbox_destroy               │
   │   → sandbox_id, destroyed_at, events                              │
   └──────────────────────────────────────────────────────────────────┘
```

## Hard rules

1. **Stage implementers and code-review call `sandbox_run_test` directly.** Do NOT route through `worktree-sandbox` for per-stage runs — `worktree-sandbox` is entry/exit only.
2. **Never write `.env` contents.** `env_copy` returns paths only.
3. **Plugin is the source of truth for invocation form.** Agents do not write `sandbox create|exec|destroy` or `docker compose` invocations directly; they call plugin tools. The `docker-sandbox` skill is the canonical Sysbox-vs-direct-Docker reference for the plugin's fallback logic, not for agents writing bash.
4. **Sandbox destroy is explicit.** Per `docker-sandbox` §5, `code-review` keeps the sandbox alive on `BLOCKED` and destroys on `APPROVED` / `ENV_BLOCKED`. For the **ticket/feature terminal teardown** the `worktree-sandbox` agent always destroys.
5. **`mise exec --` stays.** It's the project's pinned runner inside the container; not a Mac-only thing in this config.

## Permissions

- **Agent-level posture** (already configured in `agents/worktree-sandbox.md`):
  - `tools.write / edit / read / bash: false` — the agent must not edit, read, or shell out; every action goes through plugin tools.
  - `permission.edit: { "*": "deny" }` — never edit any file.
  - `permission.external_directory: { "*": "allow" }` — main checkout paths must be reachable so `env_copy` can `cp` from them without prompting.
- **Runtime rule:** the agent never holds a `bash` tool, so a `docker compose` or `sandbox create` invocation is impossible from the agent's side. The only escape hatch is the plugin; the plugin's `sandbox_destroy` is the only direct `sandbox destroy` path.

## Output

Return to parent (plugin tool responses are authoritative):

- `mode`: `env_copy` | `probe_and_create` | `status` | `teardown`
- `status`: `ok` | `blocked`
- For `probe_and_create`: `sandbox_id`, `backend` (`sandbox` | `docker`), `compose_test_file`, `build_seconds`, `warm_run_seconds`
- For `teardown`: `sandbox_id`, `backend`, `destroyed_at`, `events` (per-step ok/fail)
- For `env_copy`: `wt_root`, `main_root`, `files[]` (per-file `{name, source, target, status, is_regular_file}`)
- `blocker_code` only when `status: blocked` — values: `ENV_BLOCKED` | `SANDBOX_ID_COLLISION`
- `recommended_env_fix` only when `blocked`
- `evidence` — per-mode timings, file statuses, etc.

## On success

The parent surfaces the canonical handles (`sandbox_id`, `compose_test_file`, `backend`) to downstream dispatches. Stage implementers and `code-review` use them to call `sandbox_run_test` directly — `worktree-sandbox` is not in the per-stage path. Teardown is dispatched by the parent before the terminal `ticket_report:` / `feature_report:` comment is posted, so the next session starts with a clean compose backend.

## See also

- `plugins/sandbox.js` — the 8 tools this skill references.
- `agents/worktree-sandbox.md` — host posture, Hard Rules, mode matrix.
- `skills/docker-sandbox/SKILL.md` — Sysbox-vs-direct-Docker matrix + lifecycle-aware destroy contract (referenced by the plugin's fallback logic, not by agent bash).
- `skills/ticket-lifecycle/SKILL.md` §0.3 + §0-completion — dispatches `worktree-sandbox` (probe_and_create + teardown).
- `skills/feature-review/SKILL.md` §0.3 + §0-completion — same.
- `skills/orchestrate/SKILL.md` §0 Bootstrap — dispatches `worktree-sandbox` (env_copy) instead of the legacy `worktree-env`.
- `agents/coder.md`, `agents/code-review.md`, `agents/senior-dev.md` — direct callers of `sandbox_run_test` from the plugin.
