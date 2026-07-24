---
name: docker-sandbox
description: "Sysbox sibling sandboxes via opencode-server sandbox CLI: compose build/test and optional Traefik review URLs as {feature}.{apex}. Load when stages need Docker compose or web expose and sandbox is available."
modelTier: "fast"
roleReminder: "Always sandbox probe + env gate first. Hostname is {slug}.{apex}. Never create CF tunnels or use .env.example. Destroy what you create."
---

## Skill reference (optional load)

Load when a stage needs Docker Compose build/test and/or optional web review expose via Sysbox siblings. Follow your agent Hard Rules first. `SKILL_LOADED: docker-sandbox` is optional.

## Host contract

```text
sandbox probe|create|exec|status|destroy|expose|unexpose
```

Env: `OPENCODE_SANDBOX_ENABLED`, `OPENCODE_SANDBOX_MODE`, `OPENCODE_SANDBOX_TRAEFIK_*`, `OPENCODE_SANDBOX_REVIEW_DNS`.

Labels/names owned by the server CLI (`opencode-sandbox-<slug>`). Agents must not ad-hoc `docker run --runtime=sysbox-runc`.

## Hard Rules

1. **Always `sandbox probe` first.** If unavailable → report `sandbox: unavailable` and continue non-Docker path. Blocked only if stage `test_commands` explicitly require compose/Docker.
2. **Env gate before create** (never print secret values):
   - Require `.env` on the worktree (or main before **worktree-env** copy).
   - If Infisical is used: require non-empty key *names* `INFISICAL_PROJECT_ID`, `INFISICAL_DOMAIN`|`INFISICAL_API_URL`, and `INFISICAL_TOKEN` **or** `INFISICAL_CLIENT_ID`+`INFISICAL_CLIENT_SECRET` (plus `INFISICAL_ENV` when used).
   - **Never** read/copy `.env.example` or invent values.
   - On failure: do not create sandbox. Fix: `./scripts/setup.sh projects …` create+paste `.env`, or manual `.env`, then **worktree-env** if linked worktree.
3. Prefer repo-documented compose (`docker-compose.test.yml`, `compose.test.yaml`, README test|dev). Ask once if ambiguous; never invent a stack.
4. Always **destroy** sandboxes you create (finally). `destroy` unexposes first.
5. Never mount host `docker.sock` into nested app compose.
6. Never use sandbox for GPU/CUDA — unsupported.
7. **Expose only when asked** for web review. Hostname = `{slug}.{apex}` (not `reviews.*`). Nested app must publish `--port` on the sibling.
8. **Never create Cloudflare tunnels.** DNS upsert only when `OPENCODE_SANDBOX_REVIEW_DNS=on`; point at existing tunnel target. On DNS auth errors: tell user `./scripts/setup.sh mcp-auth cloudflare-api` + Zone DNS Edit.
9. Server Infisical ≠ app Infisical — app secrets come from mounted repo `.env`.

## ID hygiene

Slug from branch/feature short name (DNS-label sanitize). One sandbox per worktree session unless `status` shows ready id — reuse.

## App apex discovery

1. `opencode.md` / registry: `review_domain` or `apex_domain`
2. Else README domain
3. Else ask once; suggest scribe add `review_domain` later

## Happy path — run

```bash
sandbox probe
# env gate: test -f .env ; check Infisical key names without printing values
sandbox create --id <slug> --worktree "$(git rev-parse --show-toplevel)"
sandbox exec --id <slug> -- docker compose -f docker-compose.test.yml build
sandbox exec --id <slug> -- docker compose -f docker-compose.test.yml run --rm test
sandbox destroy --id <slug>
```

## Happy path — expose (after app is up and publishing a port)

```bash
# hostname = {slug}.{apex} e.g. blockshed.blockshared.com
sandbox expose --id <slug> --port <port> --hostname <slug>.<apex>
# optional: cloudflare-api MCP DNS for hostname → existing tunnel target
# report https://<slug>.<apex>
sandbox unexpose --id <slug>
sandbox destroy --id <slug>
```

## Evidence

When sandbox is ready and the repo documents compose tests, `sandbox exec` logs are valid verifier evidence.

## On unavailable

Report `sandbox: unavailable`. Do not recommend enabling Sysbox from this skill. Fall back unless the stage explicitly requires compose/Docker.
