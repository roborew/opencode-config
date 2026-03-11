# Stage-Based Orchestration Runbook

## Overview

- **Primary orchestrators** (`plan`, `debugger`, `refactor`, `review`) run on stronger models and own analysis + staged dispatch.
- **Execution subagents** (`build`, `designer`) run on cheaper models and execute bounded stage tasks.
- **Artifact writer** (`scribe`) writes markdown artifacts/docs in approved paths.
- **Verifier** (`verifier`) is an independent evidence gate and never writes code.
- **Mentor** (`mentor`) is optional and explanatory only.

## Agent Matrix

| Role | Agents | Model Tier | Responsibility |
|---|---|---|---|
| Primary | `plan`, `debugger`, `refactor`, `review` | smart | Orchestrate stages and decisions; no direct file edits |
| Artifact writer | `scribe` | fast | Write/update markdown artifacts and docs from orchestrator content |
| Execution | `build`, `designer` | fast | Execute assigned `stage_id` tasks with micro-TDD |
| Verification | `verifier` | fast | Verify acceptance criteria with traceable evidence |

Primary agents are permission-scoped with `edit: deny` and must delegate markdown file writes to `scribe`.

## Canonical Flow

1. Primary drafts artifact content in memory and dispatches `scribe` to write one artifact in `.plan/` (`plan.*`, `debug.*`, `refactor.*`, or `review.*`).
2. Primary dispatches one stage at a time to `build` or `designer`.
3. Execution subagent returns completion report (`stage_id`, files, tests, checks, blockers, risks, next input).
4. Primary dispatches next stage only after successful handoff.
5. For final completion, run `verifier`.
6. Prompt user: **"Start review now?"**
   - **Yes**: `review` creates/updates `.plan/review.<slug>.md`, `build` applies fixes, `verifier` re-checks.
   - **No**: end with resume command and artifact path for a clean new session.
7. Generate required docs only after verification gates pass by dispatching `scribe`.

## Review and Verifier Interaction

- `review` focuses on bug/correctness/security risks and fix planning.
- `verifier` checks conformance against:
  - original feature acceptance criteria (`.plan/plan.<slug>.md`)
  - review remediation criteria (`.plan/review.<slug>.md`) when review path is active.
- If verifier fails:
  - update the same `review.<slug>.md` artifact in place through `scribe`
  - mark completed tasks
  - append remediation tasks
  - append dated `IterationNotes`
  - repeat `build` -> `verifier` cycle

## MCP Usage Policy

Primaries and execution agents should use MCP only when it reduces uncertainty:

- `docs-mcp-server`: internal docs, prototypes, linked repos, architecture notes.
- `dash-api`: API/library contract lookup when behavior is unclear.

If a user says "look at the prototype", check `docs-mcp-server` first and record what was used.

## Documentation Gate (Required)

After successful verification, generate:

- `docs/changelog/<date>-<slug>.md`
- `docs/guides/<feature-slug>.md`
- `docs/architecture/<feature-slug>.md`

Use templates in:
- `docs/changelog/TEMPLATE.md`
- `docs/guides/TEMPLATE.md`
- `docs/architecture/TEMPLATE.md`

## Stage Dispatch Template

Use this when dispatching execution:

```text
Artifact: .plan/<type>.<slug>.md
Stage IDs: <stage-id-list>
Scope in: <paths/components>
Scope out: <explicit exclusions>
Acceptance checks: <commands>
Completion report required: stage_id, files_changed, tests_run, acceptance_check_status, blockers, residual_risks, next_stage_input
```

Use this when dispatching markdown writes to `scribe`:

```text
Target path: .plan/<type>.<slug>.md or docs/<section>/<name>.md
Operation: create|update
Content: full markdown body
Constraints: markdown only, approved paths only
```

## Smoke Checklist

- Artifact includes required schema sections (`StagePlan`, `StageAcceptanceChecks`, `CompletionReport`, `VerifierInputs`, `DocumentationOutputs`).
- Primary agents cannot edit files directly (`edit: deny`).
- Scribe can write to `.plan` and docs markdown paths only.
- Stage dispatch is one-at-a-time with completion handoff.
- UI work routes to `designer`; non-UI work routes to `build`.
- Optional review prompt appears at completion and supports defer/resume.
- Verifier receives original feature artifact and review artifact (if present).
- Verifier report includes criterion-level evidence.
- Verifier failure updates the existing review artifact (no fragmented review files).
- No stale references to removed agents (`implementor`, `fix`, `pr-reviewer`, `refactorer`).
- MCP lookups are used only when prompt/context indicates need.
- Final docs are generated only after verification gates pass.
