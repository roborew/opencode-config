---
name: docker-sandbox
description: "Sysbox sibling sandboxes via opencode-server sandbox CLI for ephemeral compose build/test. Load when stages need Docker compose tests and sandbox is on PATH or preflight reports sandbox: ready."
modelTier: "fast"
roleReminder: "Always sandbox probe first. Never invent docker.sock or ad-hoc sysbox-runc. Destroy what you create."
---

## Skill reference (optional load)

Load when a stage needs Docker Compose build/test inside an ephemeral Sysbox sibling sandbox managed by the opencode-server `sandbox` CLI. Follow your agent Hard Rules first. `SKILL_LOADED: docker-sandbox` is optional.

## Host contract

CLI on PATH inside the OpenCode server container when enabled:

```text
sandbox probe|create|exec|status|destroy
```

`expose` / `unexpose` are Phase 2 stubs — not required; if called, treat as “not implemented yet.”

Env (server-computed): `OPENCODE_SANDBOX_ENABLED=0|1`, `OPENCODE_SANDBOX_MODE=off|auto|on`.

Labels/names are owned by the server CLI (`opencode-sandbox-<slug>`). Agents must not `docker run --runtime=sysbox-runc` ad hoc on the host socket except via this CLI.

## Hard Rules

1. **Always `sandbox probe` first.** If unavailable (CLI missing, non-zero exit, or JSON `{ "available": false, "reason": "SANDBOX_UNAVAILABLE" }`): report `sandbox: unavailable` and continue with the existing non-Docker preflight/test path. Blocked **only** if the stage’s `test_commands` explicitly require compose/Docker.
2. **Prefer repo-documented compose test entrypoints** — `docker-compose.test.yml`, `compose.test.yaml`, or README “test” compose. Do not invent a stack.
3. **Always destroy sandboxes you create** (finally / on failure). Prefer `sandbox destroy --id <slug>` even when exec fails.
4. **Never mount host `docker.sock`** into nested app compose.
5. **Never use sandbox for GPU/CUDA workloads** — unsupported.
6. **Phase 2:** `expose` / `unexpose` are reserved; do not call them as required steps.
7. **Never** ad-hoc `docker run --runtime=sysbox-runc` or invent host Docker usage when probe fails.

## ID hygiene

- Slug from branch or feature short name (lowercase, hyphenated, short).
- One sandbox per worktree session unless `sandbox status` shows an existing ready id for that slug — reuse then; do not create duplicates.

## Happy path

```bash
sandbox probe
# expect exit 0 + {"available": true, ...}

sandbox create --id <slug> --worktree "$(git rev-parse --show-toplevel)"

sandbox exec --id <slug> -- docker compose -f docker-compose.test.yml build
sandbox exec --id <slug> -- docker compose -f docker-compose.test.yml run --rm test

sandbox destroy --id <slug>
```

Adjust the compose file/service to match the repo’s documented test entrypoint.

## Evidence

When sandbox is ready and the repo documents compose tests, `sandbox exec` logs are valid test evidence for verifier — same weight as local test runners.

## On unavailable

Report `sandbox: unavailable` (include probe stderr / reason when present). Do not recommend enabling Sysbox or mounting Docker from this skill. Fall back to non-Docker commands unless the stage explicitly requires compose/Docker (then Blocked with that requirement cited).
