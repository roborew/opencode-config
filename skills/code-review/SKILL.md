---
name: code-review
description: Shared independent ticket and feature code-review contract; CodeRabbit is optional.
---

# Code Review

Review independently against the issue or feature contract, not the implementer's report. Inspect the diff, changed-file scope, test quality, assertion delta, and every acceptance criterion. A criterion without evidence is not verified.

## Ticket mode

Per-stage review (the coder dispatches this between stages and after the final stage):

- **Per-stage gate** — run focused lint, unit, contract, and schema checks; replay RED then GREEN; inspect assertion delta and scope drift; and require docs when behaviour changes. **No full regression per stage.** No CodeRabbit in ticket mode.

- **Final `all_stages: true` gate** (the coder dispatches this before `state:ready-for-review`, after every per-stage gate has APPROVED): run the **full test suite** via the compose test backend (`docker-compose.test.yml` via `sandbox exec` on the opencode-server, or direct `docker compose -f <compose_test_file>` on local dev — `skills/docker-sandbox/SKILL.md` invocation matrix). Inspect full-suite assertion delta and cross-stage integration. No CodeRabbit.

Either way: RED/GREEN/final-gate evidence is the compose-backend test-run output, not verbal claims. `compose_test_file: none` → `BLOCKED: ENV_BLOCKED` + `recommended_env_fix: add docker-compose.test.yml from templates/project-stub/`. Never host-local test runners.

CodeRabbit remains a one-shot feature-sign-off gate inside `architect-feature-signoff`; it never runs per-ticket.

## Feature mode

Run the documented Docker/Sysbox full regression, integration, and e2e checks. Delegate security review to `security-reviewer` when authentication, secrets, input, network, database, filesystem, or other security-sensitive paths are touched. CodeRabbit is optional and may run once at the feature gate or on explicit user request.

Return `APPROVED` only when all criteria have non-missing evidence, security is resolved, and no blocking findings remain. Return `NEEDS_CHANGES` or `BLOCKED` otherwise.
