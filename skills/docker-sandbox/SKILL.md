---
name: docker-sandbox
description: "Sysbox sibling sandboxes via opencode-server sandbox CLI: self-contained compose (Caddy) build/test and optional review URLs as {feature}.{apex} (localhost publish via sandbox expose + Cloudflare tunnel hostname + DNS via MCP). Load when stages need Docker compose or web expose."
modelTier: "fast"
roleReminder: "Probe + env gate first. Compose must be self-contained (Caddy). Expose = sandbox expose (localhost) then CF tunnel hostname (HTTPS + No TLS Verify ON) + optional DNS. Host cloudflared only — never cloudflared-in-compose. No .env.example."
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
sandbox probe|create|exec|status|destroy|expose|unexpose
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
7. **Expose only when asked.** Hostname = `{slug}.{apex}` (not `reviews.*`). App must publish Caddy `--port` on the sibling before expose (typically `80` or `443`).
8. **Publish:** only via `sandbox expose` / `unexpose`.
9. **Cloudflare:** after expose, upsert tunnel public hostname with **service type HTTPS** and **No TLS Verify ON** (see happy path). DNS when `OPENCODE_SANDBOX_REVIEW_DNS` is `on` (default). Never tunnel create. Never use HTTP service type for review hostnames. On auth errors → user runs `./scripts/setup.sh mcp-auth cloudflare-api` (Zone DNS Edit + Tunnel Edit on existing tunnel).
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

## Happy path — expose + tunnel hostname + DNS

After the self-contained stack is up (Caddy publishing an inner port, usually `80` or `443`):

```bash
sandbox expose --id <slug> --port 80 --hostname <slug>.<apex>
# JSON includes host_port, origin (often http://127.0.0.1:<host_port> — ignore scheme), url
```

Then:

1. Prefer load `cloudflare` skill for DNS/tunnel record semantics when unsure.
2. Via **cloudflare-api** MCP (read first):
   - Resolve zone for `<apex>`.
   - Upsert **public hostname** on the **existing** host tunnel (`OPENCODE_SANDBOX_TUNNEL_ID` when set) with these **required** fields (do not copy expose `origin` verbatim):
     - **Hostname:** `<slug>.<apex>`
     - **Service type:** `HTTPS` (never `HTTP` — browsers need HTTPS at the review URL; HTTP origin service type is incorrect for this flow)
     - **URL / service:** `https://127.0.0.1:<host_port>` (take `host_port` from expose JSON; force `https://` scheme)
     - **TLS → No TLS Verify:** **ON** (`originRequest.noTLSVerify: true`) — local/self-signed origin certs will fail verification otherwise
   - If `OPENCODE_SANDBOX_REVIEW_DNS=on` (or unset/default on): create or update CNAME name=`<slug>` → same tunnel target other app records use (`*.cfargotunnel.com`), proxied as peers on the zone.
3. Do **not** create a tunnel; do **not** put cloudflared in compose.
4. Report `https://<slug>.<apex>` (always HTTPS).
5. On teardown: delete **only** the DNS record and tunnel public hostname this session created (if any), then `sandbox unexpose` / `destroy`.

If `OPENCODE_SANDBOX_REVIEW_DNS=off`: still upsert tunnel public hostname with HTTPS + No TLS Verify as above; skip MCP DNS (assume wildcard already covers `*.apex`).

## Evidence

`sandbox exec` logs are valid verifier evidence when sandbox is ready and compose tests are documented.

## On unavailable

Report `sandbox: unavailable`. Do not recommend enabling Sysbox from this skill.
