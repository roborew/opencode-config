# Stage-Based Orchestration Runbook

## Overview

- **Built-in agents:** `plan` and `build` remain OpenCode defaults (Codex model) for generic/quick tasks.
- **Primary planning mode** (`architect`) classifies task type, drafts plan content, and invokes `scribe` to persist the artifact.
- **Primary execution mode** (`orchestrator`) runs delegated stage execution and recovery flow.
- **Planning specialists** (`debugger`, `refactor`, `review`) are subagents invoked by `architect`.
- **Execution subagents** (`implementor`, `designer`) run on cheaper models and execute bounded stage tasks.
- **Artifact writer** (`scribe`) writes markdown artifacts/docs in approved paths.
- **Recovery replanner** (`helper`) diagnoses stuck/failed states and amends existing artifacts through `scribe`.
- **Verifier** (`verifier`) is an independent evidence gate and never writes code.
- **Mentor** (`mentor`) is optional and explanatory only.

## Agent Matrix

| Role | Agents | Model Tier | Responsibility |
|---|---|---|---|
| Primary (planning) | `architect` | smart | Ask plan type, invoke specialist planner, produce plan, call scribe to write artifact |
| Coordinator | `orchestrator` | smart | Execute artifact stages, grade child reports, enforce helper-triggered recovery, dispatch scribe for docs |
| Planning specialists | `debugger`, `refactor`, `review` | smart | Return type-specific plan drafts to architect |
| Artifact writer | `scribe` | fast | Write/update markdown artifacts and docs from architect/orchestrator content |
| Recovery | `helper` | fast | Replan minimal strategy deltas and trigger artifact amendment |
| Execution | `implementor`, `designer` | fast | Execute assigned `stage_id` tasks with micro-TDD |
| Verification | `verifier` | fast | Verify acceptance criteria with traceable evidence |

Both primaries (`architect`, `orchestrator`) are non-writing (`edit: deny`). Only `scribe` writes markdown artifacts/docs.

## Canonical Flow

1. `architect` asks for plan type (Feature/Debug/Refactor/Review) when request is greeting/unspecified.
2. `architect` invokes matching specialist subagent (`debugger`/`refactor`/`review`) as needed and produces artifact draft content.
3. `architect` invokes `scribe` to write the artifact to `.plan/<type>.<slug>.md` (mandatory step).
4. User switches to `orchestrator`.
5. `orchestrator` ensures artifact exists; if missing, dispatches `scribe` to write it.
6. `orchestrator` invokes `helper` environment preflight and writes `EnvReadiness` to artifact via `scribe`.
7. `orchestrator` dispatches one stage at a time to `implementor` or `designer` only if EnvReadiness is `Ready`.
8. Execution subagent returns completion report (`stage_id`, files, tests, checks, blockers, risks, next input).
9. `orchestrator` dispatches next stage only after successful handoff.
10. For final completion, run `verifier`.
11. Prompt user: **"Start review now?"**
   - **Yes**: `review` creates/updates `.plan/review.<slug>.md`, `implementor` applies fixes, `verifier` re-checks.
   - **No**: end with resume command and artifact path for a clean new session.
12. Generate required docs from artifact `DocumentationOutputs` by dispatching `scribe` (mandatory before declaring completion).

At each stage handoff, orchestrator grades child output:
- `PASS` -> continue
- `NEEDS_RETRY` -> corrective feedback and rerun stage
- `BLOCKED` -> helper + scribe amendment path

## Escalation and Recovery (enforced)

Invoke `helper` immediately when any occurs:
- same stage fails verification twice
- unresolved blocker reported by execution subagent
- verifier reports failed criteria requiring strategy change
- execution reports `ENV_BLOCKED` (runtime/toolchain mismatch)

Recovery loop:
1. `helper` diagnoses and proposes minimal amendment.
2. `scribe` updates existing artifact in place.
3. resume with next indicated stage.

Do not advance stages until helper amendment is applied.
Do not allow repeated test-command retries under unresolved environment mismatch.
Do not start execution stages before helper startup preflight is recorded in artifact.

## Subagent Loop Exit Strategy (enforced)

When a subagent repeats the same completion message or stalls:

1. **OpenCode config**: Scribe has `steps: 5`, implementor has `steps: 20` in `opencode.json` — forces exit after that many agentic iterations.
2. **Orchestrator loop detection**: If the same or near-identical child report is received 2+ times, treat as `BLOCKED`, invoke `helper`, and amend the same artifact via `scribe` before any retry.
3. **Scribe exit rule**: Scribe returns exactly once per task. After reporting path + operation + summary, it stops.
4. **Implementor anti-loop rule**: Implementor must not repeat the same verbal intent (e.g. "Let me create X"); one statement, then execute. If the same failing command repeats twice without meaningful change, return `blocker_code: STAGE_STUCK` and stop.
5. **Manual escape**: Use `Ctrl+C` or session interrupt. Resume in a new session with artifact path if needed.

Provider-level `timeout` (e.g. 300000ms) can be set in `opencode.json` under `provider.<name>.options` to cap LLM request duration.

## Review and Verifier Interaction

- `review` focuses on bug/correctness/security risks and fix planning.
- `verifier` checks conformance against:
  - original feature acceptance criteria (`.plan/feature.<slug>.md`)
  - review remediation criteria (`.plan/review.<slug>.md`) when review path is active.
- If verifier fails:
  - update the same `review.<slug>.md` artifact in place through `scribe`
  - mark completed tasks
  - append remediation tasks
  - append dated `IterationNotes`
  - invoke `helper` when repeated failures or blocker persists
  - repeat `implementor` -> `verifier` cycle

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
- Artifact includes `EnvReadiness` and is updated before stage execution.
- Primary agents cannot edit files directly (`edit: deny`).
- Scribe can write to `.plan` and docs markdown paths only.
- Helper never writes directly and only amends existing artifacts via `scribe`.
- Helper is invoked on repeated verifier failure or unresolved blockers.
- Environment/toolchain blockers (`ENV_BLOCKED`) halt stage progression and require helper+scribe amendment before retry.
- Stage dispatch is one-at-a-time with completion handoff.
- UI work routes to `designer`; non-UI work routes to `implementor`.
- Optional review prompt appears at completion and supports defer/resume.
- Verifier receives original feature artifact and review artifact (if present).
- Verifier report includes criterion-level evidence.
- Verifier failure updates the existing review artifact (no fragmented review files).
- No stale references to removed agents (`fix`, `pr-reviewer`, `refactorer`). Execution uses `implementor` (not built-in `build`) in the custom pipeline.
- MCP lookups are used only when prompt/context indicates need.
- Final docs are generated only after verification gates pass.
