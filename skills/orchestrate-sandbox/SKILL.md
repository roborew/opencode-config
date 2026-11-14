---
name: orchestrate-sandbox
description: "Sandbox build/refresh/expose/destroy coordinator for the current checkout. Not for GitHub queue execution or direct sandbox CLI operations."
modelTier: "fast"
roleReminder: "Load only for menu option (2) or an explicit sandbox lifecycle request; delegate operations to developer loading docker-sandbox."
---

## Scope

Build or refresh the current feature branch in a Sysbox sibling without running the GitHub ticket queue. The coordinator does not load `docker-sandbox` and never invokes the sandbox CLI itself.

## Procedure

1. Require a successful checkout identity gate and reject protected branches before sandbox creation.
2. Derive a DNS-safe `sandbox_slug` from the verified branch or an explicit feature slug. Ask build intent only when unclear: `create_build_test`, `up_live`, or `refresh`.
3. Ask `Publish review URL? (yes/no)` once for live/expose intent unless already answered. Keep `publish_review_url` in session state.
4. Task `developer` with `load: full`, `execution_mode: sandbox_feature_build`, `load skill: docker-sandbox`, `sandbox: required`, the checkout contract, action, slug, compose path, and publish choice.
5. Require report evidence for probe, compose commands and exit status, sandbox id, review URL when requested, and keep/destroy decision. If the probe is unavailable, report once and soft-skip only when the user accepts; never invent host Docker/Sysbox wiring.
6. On success retain `sandbox_build_active`, `sandbox_slug`, `sandbox_compose_file`, and `review_url`. `refresh`, `expose`, and `destroy` re-task the same developer contract and never run issue-expand or queue discovery.

Use `docker-sandbox` for actual create/exec/expose/destroy behavior, including HTTPS tunnel service and No TLS Verify requirements. Do not create tunnels or use Cloudflare Workers Sandbox references.
