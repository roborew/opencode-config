---
name: code-review
description: Shared independent ticket and feature code-review contract; CodeRabbit is optional.
---

# Code Review

Review independently against the issue or feature contract, not the implementer's report. Inspect the diff, changed-file scope, test quality, assertion delta, and every acceptance criterion. A criterion without evidence is not verified.

## Ticket mode

Run focused lint, unit, contract, and schema checks; replay RED then GREEN; inspect assertion delta and scope drift; and require docs when behaviour changes. Do not run full regression or CodeRabbit in ticket mode.

## Feature mode

Run the documented Docker/Sysbox full regression, integration, and e2e checks. Delegate security review to `security-reviewer` when authentication, secrets, input, network, database, filesystem, or other security-sensitive paths are touched. CodeRabbit is optional and may run once at the feature gate or on explicit user request.

Return `APPROVED` only when all criteria have non-missing evidence, security is resolved, and no blocking findings remain. Return `NEEDS_CHANGES` or `BLOCKED` otherwise.
