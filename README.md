# OpenCode Agent Orchestration

This repository uses a stage-based orchestration model to keep cheaper models focused and context-light while preserving quality gates.

## Topology

- **Primary planning mode:** `plan`
- **Primary execution mode:** `orchestrator`
- **Planning specialists (subagents):** `debugger`, `refactor`, `review`
- **Artifact writer:** `scribe`
- **Recovery replanner:** `helper`
- **Execution subagents:** `build`, `designer`
- **Verification gate:** `verifier`
- **Optional mentor:** `mentor`

## How It Works

1. `plan` asks what type of plan is needed (Feature, Debug, Refactor, Review) when prompt is greeting/unspecified.
2. `plan` drafts content (and invokes specialist subagents when needed).
3. Switch to `orchestrator`.
4. `orchestrator` dispatches `scribe` to create/update a single artifact in `.plan/`:
   - `.plan/plan.<slug>.md`
   - `.plan/debug.<slug>.md`
   - `.plan/refactor.<slug>.md`
   - `.plan/review.<slug>.md`
5. `orchestrator` dispatches one stage at a time to `build` or `designer`.
6. Execution subagents return completion reports with evidence.
7. `verifier` checks acceptance criteria with evidence before completion.
8. If execution is stuck or verifier fails repeatedly, `orchestrator` invokes `helper`, then `scribe` updates the existing artifact before retry.

## Review Decision Gate

After feature completion, ask: **"Start review now?"**

- **Yes:** `review` dispatches `scribe` to produce/update a review artifact, `build` applies fixes, `verifier` signs off.
- **No:** keep artifacts and resume in a new session later (better context hygiene).

## Verifier and Review Responsibilities

- `review`: identifies and prioritizes correctness/security/quality issues.
- `verifier`: validates requirement conformance against original feature criteria (and review criteria when review is active).

If verification fails, update the same `review.<slug>.md` artifact with:
- completed tasks marked complete
- new remediation tasks
- dated `IterationNotes`

The update is performed by `scribe` (not by primary agents).

When failures persist, `helper` produces a minimal strategy amendment and `scribe` applies it to the same artifact (`IterationNotes` + task status changes).

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

These docs are written via `scribe`.

Templates live in:

- `docs/changelog/TEMPLATE.md`
- `docs/guides/TEMPLATE.md`
- `docs/architecture/TEMPLATE.md`
