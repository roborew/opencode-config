# Plan artifact schema

Execution plans live in one of two places depending on workflow mode. **Spec-driven features** use **GitHub issue bodies** as the source of truth after fanout. **Legacy local plans** use **`.plan/<type>.<slug>.md`** files.

See [FEATURE-PIPELINE.md](FEATURE-PIPELINE.md) for the operator flow and [RUNBOOK.md](RUNBOOK.md) for agent behaviour.

---

## GitHub issue task block (`opencode-task-yaml`)

Spec **fanout** embeds a minimal fenced `opencode-task-yaml` block (routing only). **`issue-expand`** in the implementation repo adds `stages[]` and fills **Implementation planning** markdown (Context, Current state, Stage plan, Tests). This is the **execution source of truth** for spec-driven features (no parallel `.plan/issue.*` files).

Legacy `opencode-task-json` fences are still parsed during migration.

### Root fields (fanout — spec phase)

| Field | Required | Purpose |
|-------|----------|---------|
| `task_id` | yes | Stable id from PRD ticket |
| `owner` | yes | `developer`, `frontend-dev`, or `ux-dev` |
| `depends_on` | no | Ticket ids (fanout → **Blocked by**) |
| `capability` | no | Registry capability |
| `stages` | no | Must be empty at fanout; added by **issue-expand** |

Product `acceptance` lives in **Requirements** markdown, not in the yaml block.

### Root fields (orchestrate — after issue-expand)

| Field | Required | Purpose |
|-------|----------|---------|
| `stages` | yes | Non-empty; see below |
| `commit_message` | per stage | In each stage entry (flat mode may use root — legacy json) |

### `stages[]` (issue-expand)

When non-empty, **orchestrate** runs one stage per loop (`execution_mode: github_issue_stage`) before marking the issue ready-for-review.

| Field | Required | Purpose |
|-------|----------|---------|
| `stage_id` | yes | e.g. `1-red`, `2-green` |
| `owner` | yes | `developer`, `frontend-dev`, or `ux-dev` |
| `objective` | yes | One stage goal |
| `files` | no | Paths to touch (from codebase discovery) |
| `acceptance` | yes | Stage acceptance strings |
| `test_commands` | yes | Commands for verifier |
| `commit_message` | yes | Subject for this stage's commit (`Refs: #n`) |

Human-readable detail lives under **## Implementation planning** (same content as a `.plan` artifact, adapted for GitHub).

### Canonical issue body sections

Parent PRD · User stories · Requirements · **Implementation planning** · **opencode-task-yaml** · Description · Blocked by

---

## Legacy `.plan` artifacts (local file mode)

All `.plan/<type>.<slug>.md` files follow this structure when using **architect option 2** (legacy local plan). Primary agents produce them; execution and verification subagents consume them. After architect Mode B sign-off and documentation, the active file may be **archived** to `.plan/<type>.<slug>.completed.md` (same markdown structure; filename marks completion for orchestrate listing).

### Required sections

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
| **ReviewDecisionGate** | Prompt behaviour after feature completion: start review now or defer |
| **VerifierInputs** | Required references for verifier: original feature plan, optional review artifact, completion reports, evidence |
| **ReviewIterationPolicy** | On verifier fail, update existing review artifact; add IterationNotes and remediation tasks |
| **DocumentationOutputs** | Final required docs under `docs/changelog`, `docs/guides`, and `docs/architecture` |
| **Risks** | Known risks, rollback notes |
| **OutOfScope** | Explicitly excluded work |

### CompletionReport contract

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

### Artifact types

- `feature.<slug>.md` — Feature implementation (from `plan`)
- `debug.<slug>.md` — Bug fix (from `debugger`)
- `refactor.<slug>.md` — Refactor migration (from `refactor`)
- `review.<slug>.md` — Review changes (from `review`)
- Prototype design briefs from `designer` are embedded in GitHub issue implementation plans; `design_delivery: prototype-required` adds ordered `ux-dev` then `frontend-dev` stages.

### Test-driven development (TDD) — mandatory

**Every stage must be testable.** Plans that omit tests are invalid.

1. **StageAcceptanceChecks:** Each stage MUST have at least one executable test or verification command.
2. **Task ordering:** For behavior changes, Tasks MUST order test-first: add/update test → run and confirm failure (red) → implement → run and confirm pass (green).
3. **FilesToChange:** Include test file paths for each stage that adds or changes behavior.
4. **AcceptanceChecks:** End-to-end checks MUST include running the full test suite (or targeted tests) for changed code paths.
