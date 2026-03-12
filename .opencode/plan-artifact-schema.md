# .plan Artifact Schema

All `.plan/<type>.<slug>.md` files follow this structure. Primary agents produce them; execution and verification subagents consume them.

## Required Sections

| Section | Purpose |
|---------|---------|
| **Context** | Brief background, constraints, and assumptions |
| **Goal** | One-sentence objective |
| **StagePlan** | Ordered stages with `stage_id`, **Owner** (`designer` or `developer`), objective, and dependencies |
| **Tasks** | Numbered tasks mapped to a `stage_id` |
| **FilesToChange** | Paths and explanations mapped to a `stage_id` |
| **StageAcceptanceChecks** | Verification gates for each stage (tests, commands, criteria) |
| **EnvReadiness** | Runtime/toolchain preflight status, required commands, and known environment constraints |
| **AcceptanceChecks** | End-to-end completion checks |
| **CompletionReport** | Required executor handoff fields back to primary |
| **ReviewDecisionGate** | Prompt behavior after feature completion: start review now or defer |
| **VerifierInputs** | Required references for verifier: original feature plan, optional review artifact, completion reports, evidence |
| **ReviewIterationPolicy** | On verifier fail, update existing review artifact; add IterationNotes and remediation tasks |
| **DocumentationOutputs** | Final required docs under `docs/changelog`, `docs/guides`, and `docs/architecture` |
| **Risks** | Known risks, rollback notes |
| **OutOfScope** | Explicitly excluded work |

## CompletionReport Contract

Each execution stage must return:

- `stage_id`
- `plan_file`
- `files_changed`
- `tests_run` and outcomes
- `acceptance_check_status` (pass/fail by check)
- `blockers`
- `residual_risks`
- `next_stage_input`

If environment is blocked:
- `blocker_code: ENV_BLOCKED`
- `preflight_checks`
- `recommended_env_fix`

## Artifact Types

- `feature.<slug>.md` - Feature implementation (from `plan`)
- `debug.<slug>.md` - Bug fix (from `debugger`)
- `refactor.<slug>.md` - Refactor migration (from `refactor`)
- `review.<slug>.md` - Review changes (from `review`)

## Example Skeleton

```markdown
# <Type>: <Name>

## Context
...

## Goal
...

## StagePlan
Each stage MUST have Owner. Orchestrate dispatches by Owner: `designer` for UI/design, `developer` for logic/backend.

1. `stage_id: stage-ui`
   - Owner: `designer`
   - Objective: ...
2. `stage_id: stage-core`
   - Owner: `developer`
   - Objective: ...

## Tasks
1. [stage-ui] ...
2. [stage-core] ...

## FilesToChange
- [stage-ui] path/to/ui-file.tsx: explanation
- [stage-core] path/to/core-file.ts: explanation

## StageAcceptanceChecks
- [stage-ui] Run `pnpm test path/to/ui.test.tsx`
- [stage-core] Run `pnpm test path/to/core.test.ts`

## EnvReadiness
- Status: Ready | Blocked
- Runtime checks:
  - `ruby -v`
  - `bundle -v`
  - project-specific test command smoke check
- Notes:
  - version manager assumptions
  - required shell initialization details

## AcceptanceChecks
- Run targeted tests
- Run lint/type checks for touched code

## CompletionReport
- Required: stage_id, files_changed, tests_run, blockers, residual_risks

## ReviewDecisionGate
- Orchestrator: on completion, prompt "Switch to architect for review and documentation sign-off."
- Architect: after review sign-off, invoke document and scribe for docs.

## VerifierInputs
- Original feature plan: `.plan/feature.<slug>.md`
- Review artifact (if present): `.plan/review.<slug>.md`
- Stage completion reports and test evidence

## ReviewIterationPolicy
- Update existing `.plan/review.<slug>.md` in place
- Mark completed tasks, add remediation tasks, append dated IterationNotes

## DocumentationOutputs
- `docs/changelog/<date>-<slug>.md`
- `docs/guides/<slug>.md`
- `docs/architecture/<slug>.md`

## Risks
- ...

## OutOfScope
- ...
```
