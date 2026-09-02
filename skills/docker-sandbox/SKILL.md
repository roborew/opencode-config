---
name: docker-sandbox
description: "Sysbox sibling sandboxes via opencode-server sandbox CLI: self-contained Compose build/test backend for ticket + feature coder loops. Load when stages need Docker Compose."
modelTier: "fast"
roleReminder: "Probe + env gate first. Lifecycle-aware destroy: code-review destroys after APPROVED, keeps alive on BLOCKED. Host cloudflared only — never cloudflared-in-compose. No .env.example. Agents call sandbox_run_test from plugins/sandbox.js — never write docker compose invocations themselves."
---

## Skill reference (optional load)

Load when a stage needs Docker Compose build/test. Follow agent Hard Rules first. `SKILL_LOADED: docker-sandbox` is optional.

**Not** Cloudflare Workers Sandbox (`skills/cloudflare/references/sandbox/` — Durable Object / `@cloudflare/sandbox`). This skill is only the opencode-server Sysbox sibling CLI (`sandbox probe|create|exec|…`).

Loaded by `developer` / `frontend-dev` / `code-review` / `senior-dev` **and by `worktree-sandbox` via the `plugins/sandbox.js` plugin tools**. The orchestrator never loads this skill — it passes `sandbox: preferred|required` and load instructions to its children. **Agents call `sandbox_run_test` from the plugin; they do not write `docker compose` invocations.** The plugin's fallback logic reads this skill as the canonical Sysbox-vs-direct-Docker matrix.

## Host contract

```text
sandbox probe|create|exec|status|destroy|expose|preview|unexpose
```

Env: `OPENCODE_SANDBOX_ENABLED`, `OPENCODE_SANDBOX_MODE`, `OPENCODE_SANDBOX_REVIEW_DNS`, `OPENCODE_SANDBOX_ROUTE_IMAGE`, optional `OPENCODE_SANDBOX_TUNNEL_ID`.

Names: sibling `opencode-sandbox-<slug>`, publish helper `opencode-sandbox-route-<slug>`. Never ad-hoc `docker run --runtime=sysbox-runc`.

## Hard Rules

1. **Always `sandbox probe` first.** Unavailable → probe `docker` for the **Direct Docker fallback** below; if neither is available → `sandbox: unavailable`; continue non-Docker unless stage requires compose/Docker (then Blocked).
2. **Env gate before create** (never print secret values):
   - Require `.env` on worktree (or main before **worktree-env**).
   - If Infisical used: non-empty key *names* `INFISICAL_PROJECT_ID`, `INFISICAL_DOMAIN`|`INFISICAL_API_URL`, and `INFISICAL_TOKEN` **or** `CLIENT_ID`+`CLIENT_SECRET` (+ `INFISICAL_ENV` if used).
   - Never `.env.example` / invent values. Fix: `./scripts/setup.sh projects …` create+paste, then worktree-env if linked.
3. Prefer documented compose (`docker-compose.test.yml`, `compose.test.yaml`, README). Ask once if ambiguous; never invent a stack.
4. **Self-contained compose required for live/review stacks:** use the app's documented listener and private service topology. Do not add cloudflared to app Compose.
5. **Lifecycle-aware destroy.** Per-ticket TDD loop: developer creates the sandbox and keeps it alive after GREEN (does not destroy); code-review reuses via `sandbox status --id <sandbox_id>` and destroys after `APPROVED` or `ENV_BLOCKED`, keeps alive on `BLOCKED` for developer retry. Feature coder loop (`feature-review`): same reuse/destroy contract — `code-review` destroys after `APPROVED`/`ENV_BLOCKED`, keeps alive on `BLOCKED`. `destroy` unexposes first.
6. Never mount host `docker.sock` into nested app compose; never GPU/CUDA sandboxes.
7. Server Infisical ≠ app Infisical.
8. **do not recommend upgrading the Docker/base Node** to silence `engines.node` warnings — Host/PATH Node may stay on the OpenCode image Node (often 22) for MCP. Use the project toolchain (mise/asdf/fnm/nvm/volta) for installs and builds.

## ID hygiene

Slug from branch/feature (DNS-label sanitize). One sandbox per worktree session. The sandbox persists across developer → code-review within the same ticket session. code-review is the destroyer on `APPROVED`/`ENV_BLOCKED`; developer keeps it alive on completion.

## Happy path — run

```bash
sandbox probe
# env gate: test -f .env ; Infisical key names only
sandbox create --id <slug> --worktree "$(git rev-parse --show-toplevel)"
sandbox exec --id <slug> -- docker compose -f docker-compose.test.yml build
sandbox exec --id <slug> -- docker compose -f docker-compose.test.yml run --rm test
# developer keeps the sandbox alive after GREEN; code-review reuses it via
# sandbox status --id <slug> and destroys after APPROVED or ENV_BLOCKED
```

## Direct Docker fallback (non-Sysbox — Mac / local dev)

When `sandbox probe` is unavailable but `docker` is present (e.g. Docker Desktop on a dev machine), run the **same** `docker-compose.test.yml` directly — no Sysbox sibling, no `sandbox create/exec/destroy`. Docker is presumed always available on both opencode-server and local dev; this is the standard verification backend, not a degraded path.

```bash
docker compose -f docker-compose.test.yml build
docker compose -f docker-compose.test.yml run --rm test
# developer does NOT run `down` after GREEN — code-review reuses the built
# images with `run --rm test`, then runs `down` after APPROVED or ENV_BLOCKED
# (keeps alive on BLOCKED for developer retry)
```

- Same compose file and `test` service as the Sysbox path — the two backends are interchangeable for verification.
- **Volume-mount contract:** the compose file must volume-mount the project source so uncommitted edits are tested without a rebuild.
- Never ad-hoc `docker run --runtime=sysbox-runc`; never mount host `docker.sock` into nested app compose.
- If neither `sandbox` nor `docker` is available, report `sandbox: unavailable` (or `docker: unavailable`) and treat as `BLOCKED` when the stage requires compose/Docker.

## Evidence

`sandbox exec` logs are valid code-review evidence when sandbox is ready and compose tests are documented.

## On unavailable

Report `sandbox: unavailable`. Do not recommend enabling Sysbox from this skill.
