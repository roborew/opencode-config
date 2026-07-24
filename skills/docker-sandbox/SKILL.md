---
name: docker-sandbox
description: "Sysbox sibling sandboxes via opencode-server sandbox CLI: compose build/test and optional review URLs as {feature}.{apex} (Traefik via sandbox expose + Cloudflare DNS via MCP). Load when stages need Docker compose or web expose."
modelTier: "fast"
roleReminder: "Probe + env gate first. Expose = sandbox expose (Traefik) then optional CF DNS. Never install Traefik/cloudflared or create tunnels. No .env.example."
---

## Skill reference (optional load)

Load when a stage needs Docker Compose build/test and/or optional web review expose. Follow agent Hard Rules first. `SKILL_LOADED: docker-sandbox` is optional.

## Division of responsibility (do not invent new skills)

| Concern | Who owns it | Agent action |
|---------|-------------|--------------|
| Install Traefik / cloudflared on Ubuntu | Human / host ops (opencode-server README) | Never install or edit Traefik static config |
| Apply Traefik route for a sandbox | `sandbox expose` / `unexpose` CLI | Call CLI only — labels + route helper are automatic |
| Create Cloudflare **tunnel** | Never (one host tunnel already exists) | Forbidden |
| DNS for `{slug}.{apex}` | `cloudflare-api` MCP (+ `cloudflare` skill if needed for DNS semantics) | Upsert/delete CNAME → **existing** tunnel target when `OPENCODE_SANDBOX_REVIEW_DNS=on` |
| App Infisical / `.env` | Setup paste + worktree-env | Gate only; never invent secrets |

There is **no** separate Traefik skill and **no** “configure Cloudflare Tunnel” skill for review apps. Host tunnel + Traefik are prerequisites; this skill only orchestrates sibling lifecycle + optional DNS.

## Host contract

```text
sandbox probe|create|exec|status|destroy|expose|unexpose
```

Env: `OPENCODE_SANDBOX_ENABLED`, `OPENCODE_SANDBOX_MODE`, `OPENCODE_SANDBOX_TRAEFIK_*`, `OPENCODE_SANDBOX_REVIEW_DNS`.

Names: sibling `opencode-sandbox-<slug>`, route helper `opencode-sandbox-route-<slug>`. Never ad-hoc `docker run --runtime=sysbox-runc`.

## Hard Rules

1. **Always `sandbox probe` first.** Unavailable → `sandbox: unavailable`; continue non-Docker unless stage requires compose/Docker (then Blocked).
2. **Env gate before create** (never print secret values):
   - Require `.env` on worktree (or main before **worktree-env**).
   - If Infisical used: non-empty key *names* `INFISICAL_PROJECT_ID`, `INFISICAL_DOMAIN`|`INFISICAL_API_URL`, and `INFISICAL_TOKEN` **or** `CLIENT_ID`+`CLIENT_SECRET` (+ `INFISICAL_ENV` if used).
   - Never `.env.example` / invent values. Fix: `./scripts/setup.sh projects …` create+paste, then worktree-env if linked.
3. Prefer documented compose (`docker-compose.test.yml`, `compose.test.yaml`, README). Ask once if ambiguous; never invent a stack.
4. Always **destroy** what you create (finally). `destroy` unexposes first.
5. Never mount host `docker.sock` into nested app compose; never GPU/CUDA sandboxes.
6. **Expose only when asked.** Hostname = `{slug}.{apex}` (not `reviews.*`). App must publish `--port` on the sibling before expose.
7. **Traefik:** only via `sandbox expose` / `unexpose`. Do not hand-edit Traefik files or invent labels on random containers.
8. **Cloudflare:** DNS only when `OPENCODE_SANDBOX_REVIEW_DNS` is `on` (default). Never tunnel create/edit. On auth errors → user runs `./scripts/setup.sh mcp-auth cloudflare-api` with Zone DNS Edit.
9. Server Infisical ≠ app Infisical.

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
# … or compose up for a live app before expose
sandbox destroy --id <slug>
```

## Happy path — expose + DNS

After the app is up and publishing an inner port:

```bash
sandbox expose --id <slug> --port <port> --hostname <slug>.<apex>
```

Then, if `OPENCODE_SANDBOX_REVIEW_DNS=on` (or unset/default on):

1. Prefer load `cloudflare` skill for DNS record semantics when unsure.
2. Via **cloudflare-api** MCP (read first):
   - Resolve zone for `<apex>`.
   - Find how other hostnames on that zone point at the tunnel (existing CNAME target for apex/`www`/known app host — usually `*.cfargotunnel.com` or the zone’s tunnel target).
   - Create or update CNAME: name=`<slug>` (or FQDN per API), target=that **same** tunnel target, proxied as other app records on the zone.
3. Do **not** create a tunnel; do **not** change tunnel ingress (host cloudflared + Traefik already handle traffic).
4. Report `https://<slug>.<apex>`.
5. On teardown: delete **only** the DNS record this session created (if any), then `sandbox unexpose` / `destroy`.

If `OPENCODE_SANDBOX_REVIEW_DNS=off`: skip MCP DNS (assume wildcard already covers `*.apex`); still call `sandbox expose`.

## Evidence

`sandbox exec` logs are valid verifier evidence when sandbox is ready and compose tests are documented.

## On unavailable

Report `sandbox: unavailable`. Do not recommend enabling Sysbox from this skill.
