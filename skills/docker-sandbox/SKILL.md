---
name: docker-sandbox
description: "Sysbox sibling sandboxes via opencode-server sandbox CLI: self-contained Compose build/test and deterministic BlocShed previews. Load when stages need Docker Compose or a web preview."
modelTier: "fast"
roleReminder: "Probe + env gate first. For BlocShed, sandbox preview is mandatory: it derives APP_SUBDOMAIN and the Traefik hostname from one sandbox ID. Never manually combine Compose up and sandbox expose. Host cloudflared only — never cloudflared-in-compose. No .env.example."
---

## Skill reference (optional load)

Load when a stage needs Docker Compose build/test and/or optional web review expose. Follow agent Hard Rules first. `SKILL_LOADED: docker-sandbox` is optional.

**Not** Cloudflare Workers Sandbox (`skills/cloudflare/references/sandbox/` — Durable Object / `@cloudflare/sandbox`). This skill is only the opencode-server Sysbox sibling CLI (`sandbox probe|create|exec|…`).

Orchestrate does not load this skill; it passes `sandbox: preferred|required` and load instructions to `developer` / `frontend-dev` / `verifier`. Menu **(2)** / `execution_mode: sandbox_feature_build` is the parallel build-refresh path (no issue queue).

## Division of responsibility (do not invent new skills)

| Concern | Who owns it | Agent action |
|---------|-------------|--------------|
| Install host cloudflared (one tunnel) | Human / host ops (opencode-server docs/sandbox.md) | Never install cloudflared; never create a tunnel |
| Localhost publish for a sandbox | `sandbox expose` / `unexpose` CLI | Call CLI only — returns `host_port` + hint `origin` (scheme may be `http://`; **do not** copy that scheme into the tunnel) |
| Tunnel public hostname `{slug}.{apex}` → origin | `cloudflare-api` MCP | Upsert/delete on the **existing** host tunnel — **always HTTPS + No TLS Verify ON** (see below) |
| DNS for `{slug}.{apex}` | `cloudflare-api` MCP (+ `cloudflare` skill if needed) | Upsert/delete CNAME → tunnel target when `OPENCODE_SANDBOX_REVIEW_DNS=on` |
| App Infisical / `.env` | Setup paste + worktree-env | Gate only; never invent secrets |

Host tunnel is a prerequisite; this skill orchestrates sibling lifecycle + optional tunnel hostname + DNS. Do not invent a tunnel-create skill.

## Host contract

```text
sandbox probe|create|exec|status|destroy|expose|preview|unexpose
```

Env: `OPENCODE_SANDBOX_ENABLED`, `OPENCODE_SANDBOX_MODE`, `OPENCODE_SANDBOX_REVIEW_DNS`, `OPENCODE_SANDBOX_ROUTE_IMAGE`, optional `OPENCODE_SANDBOX_TUNNEL_ID`.

Names: sibling `opencode-sandbox-<slug>`, publish helper `opencode-sandbox-route-<slug>`. Never ad-hoc `docker run --runtime=sysbox-runc`.

## Hard Rules

1. **Always `sandbox probe` first.** Unavailable → `sandbox: unavailable`; continue non-Docker unless stage requires compose/Docker (then Blocked).
2. **Env gate before create** (never print secret values):
   - Require `.env` on worktree (or main before **worktree-env**).
   - If Infisical used: non-empty key *names* `INFISICAL_PROJECT_ID`, `INFISICAL_DOMAIN`|`INFISICAL_API_URL`, and `INFISICAL_TOKEN` **or** `CLIENT_ID`+`CLIENT_SECRET` (+ `INFISICAL_ENV` if used).
   - Never `.env.example` / invent values. Fix: `./scripts/setup.sh projects …` create+paste, then worktree-env if linked.
3. Prefer documented compose (`docker-compose.test.yml`, `compose.test.yaml`, README). Ask once if ambiguous; never invent a stack.
4. **Self-contained compose required for live/review stacks:**
   - Private compose network only.
   - Include **Caddy** (or equivalent) reverse-proxying to app services.
   - Publish Caddy (typically `:80` or `:443`). Edge TLS is at Cloudflare; origin often uses self-signed/private TLS.
   - Do **not** add cloudflared to compose (one host tunnel).
5. Always **destroy** what you create (finally). `destroy` unexposes first.
6. Never mount host `docker.sock` into nested app compose; never GPU/CUDA sandboxes.
7. **Expose only when asked.** Hostname = `{slug}.{apex}` (not `reviews.*`). App must publish its requested `--port` on the sibling before exposure.
8. **BlocShed preview is mandatory and atomic:** use `sandbox preview --id <slug> --app-apex blocshed.app --compose-file docker-compose.test.yml --port 3000`. It starts Compose with `APP_SUBDOMAIN=<slug>` and exposes only `https://<slug>.blocshed.app` through Traefik. Never run BlocShed Compose up and `sandbox expose` separately; never override `APP_SUBDOMAIN`; never provide a different hostname.
9. **Publish:** use `sandbox preview` for BlocShed; use `sandbox expose` / `unexpose` only for other documented app flows.
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

## BlocShed preview — deterministic Traefik route

After `sandbox create`, use exactly this command for a BlocShed preview:

```bash
sandbox preview --id <slug> --app-apex blocshed.app --compose-file docker-compose.test.yml --port 3000
# APP_SUBDOMAIN=<slug>
# URL=https://<slug>.blocshed.app
```

The sandbox ID is the single source of truth. For example, `test-feature-branch` always means `APP_SUBDOMAIN=test-feature-branch` and `https://test-feature-branch.blocshed.app`. The command rejects a supplied hostname that differs from this value and creates the required Traefik adapter itself.

Do not use standalone `sandbox expose` for BlocShed, and do not trust a pre-existing `.env` `APP_SUBDOMAIN` value. Verify the actual preview URL (including `/users/sign_in`) after the command completes. On teardown, run `sandbox destroy --id <slug>`.

## Other app review URLs

For non-BlocShed documented flows, use the app's specified `sandbox expose` procedure and any required host tunnel/DNS management. Never create a tunnel or add cloudflared to app Compose.

## Evidence

`sandbox exec` logs are valid verifier evidence when sandbox is ready and compose tests are documented.

## On unavailable

Report `sandbox: unavailable`. Do not recommend enabling Sysbox from this skill.
