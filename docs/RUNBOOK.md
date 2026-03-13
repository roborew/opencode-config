# Stage-Based Orchestration Runbook

## Overview

- **Built-in agents:** `plan` and `build` remain OpenCode defaults (Codex model) for generic/quick tasks.
- **Primary planning mode** (`architect`) — read-only: exploration, reporting, drafting plans; also owns review and documentation after implementation. Invokes: `debugger`, `refactor`, `review`, `document`, `scribe`. Never invokes `frontend-dev`, `developer`, or `orchestrate`. Prompts user to switch to orchestrate when done; receives user back for review + docs after orchestrate completes.
- **Primary execution mode** (`orchestrate`) runs delegated stage execution and recovery flow. On completion, prompts user to switch to architect for review and documentation.
- **Planning specialists** (`debugger`, `refactor`, `review`) — read-only subagents of architect; return plan drafts, never write code.
- **Documentation generator** (`document`) — read-only; generates changelog/guides/architecture content; architect invokes, then scribe writes.
- **Execution subagents** (`developer`, `frontend-dev`) — coding agents invoked by orchestrate only; architect never invokes them.
- **Artifact writer** (`scribe`) — only write path; writes plan artifacts and docs (invoked by architect and orchestrate).
- **Recovery replanner** (`helper`) diagnoses stuck/failed states and amends existing artifacts through `scribe`.
- **Verifier** (`verifier`) is an independent evidence gate and never writes code.
- **Mentor** (`mentor`) is optional and explanatory only.

## Agent Matrix

| Role | Agents | Model Tier | Responsibility |
|---|---|---|---|
| Primary (planning) | `architect` | smart | Read-only: explore, report, draft. Plan mode: scribe writes artifact → switch to orchestrate. Post-implementation: review → sign-off → document → scribe writes docs |
| Coordinator | `orchestrate` | smart | Execute artifact stages, grade child reports, enforce helper-triggered recovery, dispatch scribe for docs |
| Planning specialists | `debugger`, `refactor`, `review` | smart | Return type-specific plan drafts to architect |
| Documentation generator | `document` | fast | Generate changelog/guides/architecture content; architect invokes, scribe writes |
| Artifact writer | `scribe` | fast | Write/update markdown artifacts and docs from architect/orchestrate content |
| Recovery | `helper` | fast | Replan minimal strategy deltas and trigger artifact amendment |
| Execution | `developer`, `frontend-dev` | fast | Execute assigned `stage_id` tasks with micro-TDD |
| Verification | `verifier` | fast | Verify acceptance criteria with traceable evidence |

Both primaries (`architect`, `orchestrate`) are non-writing (`edit: deny`). Only `scribe` writes markdown artifacts/docs.

## Permission Conventions (skill creep prevention)

- **Skill:** Each agent may load only its core skill(s). No `skill: { "*": "allow" }`. Explicit allow per skill (e.g. `architect`, `developer`, `preflight` for developer).
- **Architect subagents** (`debugger`, `refactor`, `review`, `document`): `task: { "*": deny }` — they cannot invoke scribe or any other agent. Return content only to parent; architect handles scribe handoff.

## Canonical Flow

1. `architect` asks for plan type (Feature/Debug/Refactor/Review) when request is greeting/unspecified.
2. `architect` invokes matching specialist subagent (`debugger`/`refactor`/`review`) as needed and produces artifact draft content.
3. `architect` invokes `scribe` to write the artifact to `.plan/<type>.<slug>.md` (mandatory step).
4. User switches to `orchestrate`.
5. `orchestrate` ensures artifact exists; if missing, dispatches `scribe` to write it.
6. `orchestrate` starts by asking whether to run startup preflight checks now (`yes/no`).
7. If yes: `orchestrate` invokes `developer` for preflight (developer loads `preflight` skill), reports results, and pauses for remediation if blocked.
8. If no (or preflight is ready): `orchestrate` lists existing plans and asks user to select one or switch to `architect` to create a new plan.
9. `orchestrate` dispatches one stage at a time to `developer` or `frontend-dev`.
10. Execution subagent returns completion report (`stage_id`, files, tests, checks, blockers, risks, next input).
11. `orchestrate` dispatches next stage only after successful handoff.
12. For final completion, run `verifier`.
13. When verifier passes for all stages: **"Implementation complete. Switch to architect for review and documentation sign-off."** Do not run review or documentation. User switches to architect.
14. Architect (post-implementation): invokes `review` for sign-off. If remediation: scribe writes review artifact → user switches to orchestrate → developer applies fixes → verifier. If sign-off: architect invokes `document` → scribe writes docs.

At each stage handoff, orchestrate grades child output:
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
Use startup preflight as an optional session gate; do not require artifact writes for preflight output.

## Subagent Loop Exit Strategy (enforced)

When a subagent repeats the same completion message or stalls:

1. **OpenCode config**: Scribe has `steps: 5`, developer has `steps: 60` in `opencode.json` — forces exit after that many agentic iterations.
2. **Orchestrator loop detection**: If the same or near-identical child report is received 2+ times, treat as `BLOCKED`, invoke `helper`, and amend the same artifact via `scribe` before any retry.
3. **Scribe exit rule**: Scribe returns exactly once per task. After reporting path + operation + summary, it stops.
4. **Developer anti-loop rule**: Developer must not repeat the same verbal intent (e.g. "Let me create X"); one statement, then execute. If the same failing command repeats twice without meaningful change, return `blocker_code: STAGE_STUCK` and stop.
5. **Manual escape**: Use `Ctrl+C` or session interrupt. Resume in a new session with artifact path if needed.
6. **Manual handoff (Task did not return):** If a subagent completed and produced a report but the Task did not return control to the orchestrator, switch to the `orchestrate` agent and paste the completion report. The orchestrator will grade it and proceed to the next stage. Do not message the subagent again—it has already completed.

Provider-level `timeout` (e.g. 300000ms) can be set in `opencode.json` under `provider.<name>.options` to cap LLM request duration.

`default_agent` is set to `orchestrate` so execution sessions start with the coordinator as the active primary context.

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
  - repeat `developer` -> `verifier` cycle

## MCP Usage Policy

Primaries and execution agents should use MCP only when it reduces uncertainty:

- **`claude-context`**: Semantic code search in workspace. Use during planning (architect, debugger, refactor, review) to discover files/code to change and populate `FilesToChange` with evidence. Requires indexing (`index_codebase`) before search. Before planning large features, ensure the workspace is indexed if claude-context is available.
- **`context7`**: Up-to-date docs for 9000+ external libraries. Use when framework/library API behavior is uncertain. Limit to 3 calls per question.
- **`docs-mcp-server`**: Internal docs, prototypes, linked repos, architecture notes.
- **`dash-api`**: API/library contract lookup when behavior is unclear.

If a user says "look at the prototype", check `docs-mcp-server` first and record what was used.

**Execution phase**: Developer and frontend-dev receive `FilesToChange` from the plan; do not use claude-context for discovery unless the plan is ambiguous and the assigned stage requires locating additional files.

## Documentation Gate (Required)

After architect's review sign-off, architect invokes `document` to generate content, then `scribe` to write:

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
- Helper never writes directly and only amends existing artifacts via `scribe`.
- Helper is invoked on repeated verifier failure or unresolved blockers.
- Environment/toolchain blockers (`ENV_BLOCKED`) halt stage progression and require helper+scribe amendment before retry.
- Stage dispatch is one-at-a-time with completion handoff.
- UI work routes to `frontend-dev`; non-UI work routes to `developer`.
- Orchestrator prompts "Switch to architect for review and documentation" on completion.
- Verifier receives original feature artifact and review artifact (if present).
- Verifier report includes criterion-level evidence.
- Verifier failure updates the existing review artifact (no fragmented review files).
- No stale references to removed agents (`fix`, `pr-reviewer`, `refactorer`). Execution uses `developer` (not built-in `build`) in the custom pipeline.
- MCP lookups are used only when prompt/context indicates need.
- Final docs are generated by architect (document + scribe) after review sign-off.
