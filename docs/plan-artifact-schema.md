# .plan Artifact Schema

All `.plan/<type>.<slug>.md` files follow this structure. Primary agents produce them; execution and verification subagents consume them.

## Required Sections

| Section | Purpose |
|---------|---------|
| **Context** | Brief background, constraints, and assumptions |
| **Goal** | One-sentence objective |
| **Difficulty** | `easy`, `medium`, or `hard` — set by architect during planning; orchestrate uses this to scale post-implementation verification gates |
| **StagePlan** | Ordered stages with `stage_id`, **Owner** (`frontend-dev`, `developer`, or `ux-dev`), objective, and dependencies |
| **Tasks** | Numbered tasks mapped to a `stage_id` |
| **FilesToChange** | Paths and explanations mapped to a `stage_id` |
| **StageAcceptanceChecks** | Verification gates for each stage — **every stage MUST include at least one executable test or verification command** |
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
- `design.<slug>.md` - Prototype design brief (from `designer`); orchestrate dispatches `ux-dev` to generate code in `.prototype/<slug>/`

## Test-Driven Development (TDD) — Mandatory

**Every stage must be testable.** Plans that omit tests are invalid.

1. **StageAcceptanceChecks:** Each stage MUST have at least one executable test or verification command (e.g. `pnpm test path/to/file.test.ts`, `npm run lint`, `playwright test component.spec.ts`). No stage may have empty or placeholder-only checks.
2. **Task ordering:** For behavior changes, Tasks MUST order test-first: add/update test → run and confirm failure (red) → implement → run and confirm pass (green).
3. **FilesToChange:** Include test file paths for each stage that adds or changes behavior. Map test files to `stage_id` alongside production files.
4. **AcceptanceChecks:** End-to-end checks MUST include running the full test suite (or targeted tests) for changed code paths.

## Example Skeleton

```markdown
# <Type>: <Name>

## Context
...

## Goal
...

## Difficulty
One of: `easy`, `medium`, `hard` (architect sets at planning time).

## StagePlan
Each stage MUST have Owner. Orchestrate dispatches by Owner: `frontend-dev` for UI/design, `developer` for logic/backend, `ux-dev` for prototype generation from design artifacts.

1. `stage_id: stage-ui`
   - Owner: `frontend-dev`
   - Objective: ...
2. `stage_id: stage-core`
   - Owner: `developer`
   - Objective: ...

## Tasks
(TDD: test-first for behavior changes. Order: add test → red → implement → green.)
1. [stage-ui] Add component test for new UI behavior; run and confirm fail. Implement component. Run and confirm pass.
2. [stage-core] Add unit test for new logic; run and confirm fail. Implement logic. Run and confirm pass.

## FilesToChange
- [stage-ui] path/to/ui-file.tsx: explanation; path/to/ui.test.tsx: component test
- [stage-core] path/to/core-file.ts: explanation; path/to/core.test.ts: unit test

## StageAcceptanceChecks
(Every stage MUST have at least one executable test. No stage without tests.)
- [stage-ui] Run `pnpm test path/to/ui.test.tsx` (or equivalent component test)
- [stage-core] Run `pnpm test path/to/core.test.ts` (or equivalent unit test)

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
