# OpenCode Agent Orchestration

This repository uses a stage-based orchestration model to keep cheaper models focused and context-light while preserving quality gates.

## Topology

- **Primary orchestrators:** `plan`, `debugger`, `refactor`, `review`
- **Execution subagents:** `build`, `designer`
- **Verification gate:** `verifier`
- **Optional helper:** `mentor`

## How It Works

1. A primary agent creates a single artifact in `.plan/`:
   - `.plan/plan.<slug>.md`
   - `.plan/debug.<slug>.md`
   - `.plan/refactor.<slug>.md`
   - `.plan/review.<slug>.md`
2. The primary dispatches one stage at a time to `build` or `designer`.
3. The subagent returns a completion report with evidence.
4. The primary either dispatches the next stage or requests adjustments.
5. `verifier` checks acceptance criteria with evidence before completion.

## Review Decision Gate

After feature completion, ask: **"Start review now?"**

- **Yes:** `review` produces/updates a review artifact, `build` applies fixes, `verifier` signs off.
- **No:** keep artifacts and resume in a new session later (better context hygiene).

## Verifier and Review Responsibilities

- `review`: identifies and prioritizes correctness/security/quality issues.
- `verifier`: validates requirement conformance against original feature criteria (and review criteria when review is active).

If verification fails, update the same `review.<slug>.md` artifact with:
- completed tasks marked complete
- new remediation tasks
- dated `IterationNotes`

## MCP Usage Expectations

Use MCP selectively when it helps resolve uncertainty:

- `docs-mcp-server` for internal docs, prototypes, and linked references.
- `dash-api` for API/library contract lookup.

If a request says "look at the prototype", check `docs-mcp-server` first.

## Required Final Docs Per Feature

Generate after verification passes:

- `docs/changelog/<date>-<slug>.md`
- `docs/guides/<feature-slug>.md`
- `docs/architecture/<feature-slug>.md`

Templates live in:

- `docs/changelog/TEMPLATE.md`
- `docs/guides/TEMPLATE.md`
- `docs/architecture/TEMPLATE.md`
