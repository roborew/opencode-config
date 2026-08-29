---
name: docker-sandbox
description: "Sysbox sibling sandboxes via opencode-server sandbox CLI: self-contained Compose build/test and deterministic local web previews. Load when stages need Docker Compose or a web preview."
modelTier: "fast"
roleReminder: "Probe + env gate first. sandbox preview derives the route hostname from one sandbox ID and waits for the requested app port before exposure. Follow project-specific runtime contracts. Never manually combine Compose up and sandbox expose. Host cloudflared only — never cloudflared-in-compose. No .env.example."
---

## Skill reference (optional load)

Load when a stage needs Docker Compose build/test and/or optional web review expose. Follow agent Hard Rules first. `SKILL_LOADED: docker-sandbox` is optional.

**Not** Cloudflare Workers Sandbox (`skills/cloudflare/references/sandbox/` — Durable Object / `@cloudflare/sandbox`). This skill is only the opencode-server Sysbox sibling CLI (`sandbox probe|create|exec|…`).

Orchestrate does not load this skill; it passes `sandbox: preferred|required` and load instructions to `developer` / `frontend-dev` / `code-review`. Menu **(2)** / `execution_mode: sandbox_feature_build` is the parallel build-refresh path (no issue queue).

## Division of responsibility (do not invent new skills)

| Concern | Who owns it | Agent action |
|---------|-------------|--------------|
| Install host cloudflared (one tunnel) | Human / host ops (opencode-server docs/sandbox.md) | Never install cloudflared; never create a tunnel |
| Localhost publish for a sandbox | `sandbox expose` / `unexpose` CLI | Call CLI only — returns `host_port` + hint `origin` (scheme may be `http://`; **do not** copy that scheme into the tunnel) |
| Tunnel public hostname `{slug}.{apex}` → origin | `cloudflare-api` via MCPJungle | Upsert/delete on the **existing** host tunnel — **always HTTPS + No TLS Verify ON** (see below) |
| DNS for `{slug}.{apex}` | `cloudflare-api` via MCPJungle (+ `cloudflare` skill if needed) | Upsert/delete CNAME → tunnel target when `OPENCODE_SANDBOX_REVIEW_DNS=on` |
| App Infisical / `.env` | Setup paste + worktree-env | Gate only; never invent secrets |

Host tunnel is a prerequisite; this skill orchestrates sibling lifecycle + optional tunnel hostname + DNS. Do not invent a tunnel-create skill.

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
4. **Self-contained compose required for live/review stacks:** use the app’s documented listener and private service topology. Do not add cloudflared to app Compose.
5. Always **destroy** what you create (finally). `destroy` unexposes first.
6. Never mount host `docker.sock` into nested app compose; never GPU/CUDA sandboxes.
7. **Expose only when asked.** Hostname = `{slug}.{apex}` (not `reviews.*`). The app must bind the requested `--port` in the sibling before exposure.
8. **Preview atomically:** use `sandbox preview`, never a manual combination of Compose up and `sandbox expose`. It derives `<slug>.<apex>` and waits for the requested port before creating the Traefik route. Project instructions own any app-specific environment variables and host/tenant behavior.
9. **Verify before reporting success:** request a meaningful route through the derived hostname; verify no unexpected redirect host and that primary assets load. Treat 403, 502, port-readiness timeout, or an unexpected redirect as a failed preview. Diagnose the project’s documented host/runtime contract; never invent domain or tenant records.
10. Server Infisical ≠ app Infisical.

## ID hygiene

Slug from branch/feature (DNS-label sanitize). One sandbox per worktree session unless `status` shows ready id — reuse.

## App apex discovery

1. `opencode.md` / registry: `review_domain` or `apex_domain`
2. Else README domain
3. Else ask once; suggest scribe add `review_domain` later

## Happy path — run

```bash
sandbox probe
# env gate: test -f .env ; Infisical key names only
sandbox create --id <slug> --worktree "$(git rev-parse --show-toplevel)"
sandbox exec --id <slug> -- docker compose -f docker-compose.test.yml build
sandbox exec --id <slug> -- docker compose -f docker-compose.test.yml run --rm test
# … or compose up -d for a live app before expose
sandbox destroy --id <slug>
```

## Direct Docker fallback (non-Sysbox — Mac / local dev)

When `sandbox probe` is unavailable but `docker` is present (e.g. Docker Desktop on a dev machine), run the **same** `docker-compose.test.yml` directly — no Sysbox sibling, no `sandbox create/exec/destroy`. Docker is presumed always available on both opencode-server and local dev; this is the standard verification backend, not a degraded path.

```bash
docker compose -f docker-compose.test.yml build
docker compose -f docker-compose.test.yml run --rm test
# cleanup in a finally path:
docker compose -f docker-compose.test.yml down
```

- Same compose file and `test` service as the Sysbox path — the two backends are interchangeable for verification.
- **Volume-mount contract:** the compose file must volume-mount the project source so uncommitted edits are tested without a rebuild.
- Never ad-hoc `docker run --runtime=sysbox-runc`; never mount host `docker.sock` into nested app compose.
- If neither `sandbox` nor `docker` is available, report `sandbox: unavailable` (or `docker: unavailable`) and treat as `BLOCKED` when the stage requires compose/Docker.

## Deterministic local preview

After `sandbox create`, use the app’s documented apex, compose file, and listener port:

```bash
sandbox preview --id <slug> --app-apex <apex> --compose-file <compose-file> --port <port>
# URL=https://<slug>.<apex>
```

The sandbox ID is the single source of truth for the route hostname. `preview` rejects a supplied hostname that differs from `<id>.<app-apex>`, waits for the requested port in the sibling, and creates the Traefik adapter itself.

When public DNS is not configured, use the project’s local hostname setup or an HTTPS request resolved to `127.0.0.1` to verify the route. On teardown, run `sandbox destroy --id <slug>`.

## Other app review URLs

Use an app’s documented `sandbox expose` procedure only when it requires a non-preview flow. Never create a tunnel or add cloudflared to app Compose.

## Evidence

`sandbox exec` logs are valid code-review evidence when sandbox is ready and compose tests are documented.

## On unavailable

Report `sandbox: unavailable`. Do not recommend enabling Sysbox from this skill.
