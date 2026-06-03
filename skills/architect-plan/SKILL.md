---
name: architect-plan
description: "Planning mode: feature decomposition, specialists (debug/refactor/review/document/design), Mode A scribe handoff, artifact schema."
modelTier: "smart"
roleReminder: "Read-only planning. Architect completes grill-me before loading this skill for a new episode. Mode B uses architect-review."
---

> **Hard Rules live in the architect agent markdown; this skill adds protocol detail only for planning (Mode A).** Non-negotiables—scope, files, delegation, brevity, scribe handoff—come from the agent, not from this file.

## Mode A — Initial planning

**Prerequisite (architect agent):** For a new planning episode, the **`grill-me`** phase must be **complete** before you load **`architect-plan`** or execute anything below—see architect **Skill routing** (pre-planning interview after plan type + first substantive requirements). If you are reading this skill, the grill phase should already be done.

Classify task type. For **features**, classify **Difficulty** (`easy` | `medium` | `hard`), investigate via `claude-context`, then: **easy** — synthesize without strategists; **medium** — synthesize without strategists when single-domain and investigation suffices, else decompose and spawn scoped `strategist`(s); **hard** — decompose, spawn one `strategist` per sub-problem, combine reports. Always include `Difficulty` in the artifact. Pass the plan to scribe (trust successful scribe writes per agent Hard Rules), prompt user to switch to `orchestrate`. For other plan types, invoke the corresponding specialist directly.

Orchestrate reads `Difficulty` for post-implementation gates (see **`orchestrate-execution`** skill).

## Guiding Principles

- **Framework alignment**: infer the primary stack from repo signals (or ask once) and evaluate options using that stack's idioms.
- **Best-practice foundations**: apply SOLID, domain boundaries, modular design, and resiliency patterns where appropriate.
- **Integration first**: evaluate mature third-party services before bespoke builds, and call out lock-in, compliance, and cost impacts.
- **Performance and scale**: highlight hot paths, Big-O, DB/query load, caching strategy, and eventual-consistency trade-offs.
- **Security and compliance**: include data privacy and relevant compliance impacts in every serious option.
- **Context efficiency**: keep each stage bounded so cheap subagents can execute with minimal context.

## First-Turn Behavior (planning)

- If the user message is a greeting or does not specify task type, ask:
  "What type of plan do you need today?"
  Options:
  1. Feature
  2. Debug
  3. Refactor
  4. Review
  5. Document
  6. Prototype Design
- If the user says orchestrate completed / implementation done / ready for review: do **not** use this skill for that path—load **`architect-review`** instead.

## Claude Context Readiness Gate (mandatory)

Before any `claude-context` discovery for feature investigation, strategist gap-fill, or artifact evidence gathering:

- Call `get_indexing_status` for the workspace path.
- If the index is missing, stale, or not ready, call `index_codebase`, then re-check until ready before using `search_code` or `find_files`.
- Only if `claude-context` is unavailable, errors, or indexing fails after retry may you fall back to bash, glob, or `rg`. If you do, record `MCP_FALLBACK: claude-context unavailable or indexing failed — <error>` in the returned plan `Context` or `Gaps`.
- Do not begin Step 1 investigation with bash, glob, or `rg` when `claude-context` is configured and healthy.

## Responsibility Boundaries (mandatory)

| Role | Responsibility | Writes? |
|------|----------------|--------|
| **Architect** | Coordination, decomposition, investigation via claude-context, delegation, scribe handoff; review and documentation after implementation | No — read-only |
| **strategist** | Scoped sub-problem analysis; returns sub-problem report to architect | No — read-only |
| **debugger, refactor, review, document, designer** | Planning specialists; return plan drafts to architect | No — read-only |
| **scribe** | Writes plan artifacts and docs to approved paths | Yes — only write path |

You may **only** invoke: `strategist`, `debugger`, `refactor`, `review`, `document`, `designer`, and `scribe`. Do **not** invoke `frontend-dev`, `developer`, or `orchestrate` — those are execution subagents used by orchestrate.

## Supplementary Hard Rules (planning; agent Hard Rules override on conflict)

0. **No narration.** Do not describe what you are about to do. Do not explain your reasoning steps in output. Invoke subagents directly. Produce output only after actions complete.
1. **Read-only.** You and your planning specialists never write source code or execute implementation.
2. **No direct artifact writes.** You must invoke `scribe` via Task to create/update `.plan/<type>.<slug>.md`. Never write the artifact yourself.
3. **Delegate specialist planning.** For each option (Feature, Debug, Refactor, Review, Document, Prototype Design), invoke the corresponding subagent. Pass specialist output to scribe verbatim. Do not synthesize or modify.
4. **Scribe is the only write path.** After receiving specialist output, immediately invoke `scribe` with the artifact routing tuple (`artifact_type`, `slug`) and full markdown content. Pass content verbatim.
5. **User handoff.** After scribe confirms a **successful** write (per agent rule 4), emit the architect agent **execution handoff** (feature backlog or legacy `.plan` variant). Do not invoke orchestrate yourself.
6. **Scribe handoff:** After scribe returns **success** with **write/edit tool evidence** and **no** `SCRIBE_FAILED`, **do not** re-read or `test -f` by default. If scribe reports failure, omits evidence, or `SCRIBE_FAILED`, re-invoke scribe once with the same content. If still missing, report to user. For **`artifact_type: design`**, read saved file and compare to passed content; on mismatch, `HANDOFF_DRIFT` and retry.
7. **Specialist output trust:** Pass all specialist output to scribe verbatim. Do not modify, synthesize, or merge.
8. Ask clarifying questions when goals, constraints, or context are ambiguous.
9. Before invoking a specialist, ask any blocking clarifying questions if goals, constraints, or context are ambiguous.
10. Detect or confirm framework/language context before final recommendation.
11. If user references prototypes/docs/APIs, query MCP sources (`docs-mcp-server`, `dash-api`) and cite findings in Context. Use `claude-context` to discover files/code for `FilesToChange` when the codebase is large or structure is unclear. Use `context7` for external library docs when framework behavior is uncertain.
12. **Claude Context readiness first.** Before any planning discovery, enforce the Claude Context readiness gate above. Do not fall back to bash, glob, or `rg` unless `claude-context` is unavailable or indexing failed after retry.

**Brevity:** Concise headings and bullets; no reasoning narration unless the user asks; do not repeat unchanged plan text (deltas only).

## Feature Decomposition Protocol (mandatory for Feature / option 1)

When the user selects Feature, follow this protocol. You **must not** send one huge unscoped prompt to a single strategist when **multiple sub-problems** require strategists; use scoped strategists per sub-problem. **Easy** and **medium single-domain** features skip strategists when you synthesize the plan yourself (see below).

### Step 0: Classify Difficulty (mandatory)

After initial understanding, set **Difficulty** for the feature (write it into the plan artifact as `## Difficulty` with value `easy`, `medium`, or `hard`):

| Level | Typical signal | Strategist use |
|-------|----------------|----------------|
| **easy** | 1–2 stages, single concern, few files, no cross-cutting changes | **Do not** spawn strategists; you synthesize the full plan from investigation. |
| **medium** | 3–4 stages, multiple files, moderate complexity | **Default:** synthesize the full plan yourself if **single-domain** (one stack, bounded area) and investigation is sufficient. **Spawn** scoped strategists when **multi-domain** (e.g. backend + frontend + infra), **high uncertainty** after investigation, or **cross-cutting** risk. |
| **hard** | 5+ stages, cross-cutting concerns, high risk | **Must** decompose and spawn strategists; investigate more thoroughly and pass **richer** context per sub-problem than for medium. |

### Step 1: Investigate with claude-context

After satisfying the Claude Context readiness gate above, read **`CONTEXT.md`** or the context file from **`CONTEXT-MAP.md`** when present (domain glossary from **`grill-me`**). Then use `claude-context` (`search_code`, `find_files`) to investigate the codebase and gather concrete evidence:
- Identify relevant files, modules, and code patterns for the requested feature.
- Map existing architecture boundaries (components, services, data models, routes).
- Note dependencies between areas of the codebase.

### Step 2: Decompose into sub-problems

For **easy** difficulty: skip to **Easy path — synthesize plan** (after Step 1). Do not spawn strategists.

For **medium** when **single-domain** and investigation suffices: skip to **Medium synthesize path** (after Step 1)—author the full artifact yourself (same quality bar as easy); do not spawn strategists.

For **medium** when **multi-domain / high uncertainty / cross-cutting**, and for **hard**: break the feature into **distinct, isolated sub-problems**. Each sub-problem should:
- Address one clear concern or area of the codebase (e.g. "data model + API endpoint", "UI component shell", "state management wiring", "auth integration").
- Have minimal overlap with other sub-problems.
- Be answerable by a strategist that only sees the context for that slice.

Assign each sub-problem an ID (e.g. `sp-1`, `sp-data-model`, `sp-ui-shell`).

**Decomposition guidelines:**
- Small features (1-2 files, single concern): 1 sub-problem is sufficient — spawn a single strategist.
- Medium features (3-6 files, 2-3 concerns): 2-3 sub-problems.
- Large features (many files, multiple concerns): 3-5 sub-problems. Never exceed 5.
- Each sub-problem must have clear boundaries so the strategist cannot drift.

### Easy path — synthesize plan (after Step 1)

When **Difficulty: easy**:

1. Using investigation evidence from Step 1, author the full feature artifact yourself: `Context`, `Goal`, `Difficulty: easy`, `StagePlan`, `Tasks`, `FilesToChange`, `StageAcceptanceChecks`, `AcceptanceChecks`, `CompletionReport`, `ReviewDecisionGate`, `VerifierInputs`, `DocumentationOutputs`, `Risks`, `OutOfScope`, etc., per `docs/plan-artifact-schema.md`.
2. Every stage must have Owner, tests, and executable checks (same bar as strategist output).
3. Go to **Step 5: Scribe and handoff** (skip Steps 3–4).

### Medium synthesize path — single-domain (after Step 1)

When **Difficulty: medium** and you are **not** spawning strategists:

1. Author the full feature artifact yourself with `Difficulty: medium` and the same schema requirements as the easy path.
2. Apply **Stage sizing budget** (below): aim for **3–7 stages**; split stages that would exceed **~15 developer tool rounds** or **>3 substantive files** per stage (judgment for trivial imports).
3. Go to **Step 5: Scribe and handoff** (skip Steps 3–4).

### Step 3: Spawn strategists (one per sub-problem; when required)

For each sub-problem, invoke a separate `strategist` via Task with:

```
Sub-problem ID: <sp-id>
Title: <short title>
Description: <specific question/concern to analyse>
Context: <pre-investigated findings from claude-context — relevant file paths, code snippets, patterns>
Constraints: <what is in-scope and out-of-scope for this sub-problem>
Global context: <framework, slug, shared conventions>
```

**Critical:** Provide only the context relevant to that sub-problem. Do not dump the full codebase investigation into every strategist.

Require: "Produce your Sub-Problem Report and return immediately. Do not iterate or loop."

### Step 4: Combine reports into full feature plan (when strategists were used)

After all strategist sub-problems report back:

1. **Collect** all Sub-Problem Reports.
2. **Merge stages** into a single ordered StagePlan. Resolve cross-sub-problem dependencies (e.g. if sp-2's UI depends on sp-1's data model, order sp-1 stages first).
3. **Combine** Tasks, FilesToChange, StageAcceptanceChecks, Risks from all reports.
4. **Add global sections**: Context, Goal, **Difficulty** (copy the level from Step 0), AcceptanceChecks (end-to-end), CompletionReport, ReviewDecisionGate, VerifierInputs, DocumentationOutputs, OutOfScope.
5. **Note gaps**: If any strategist reported gaps, investigate those gaps with `claude-context` and fill them in the combined plan.
6. **Set artifact metadata**: `artifact_type: feature`, `slug`, path `.plan/feature.<slug>.md`.

The combined plan must follow the schema in `docs/plan-artifact-schema.md` exactly.

### Step 5: Scribe and handoff

Pass the feature plan to `scribe` via Task. After scribe success with tool evidence and no `SCRIBE_FAILED`, trust the write (see agent Hard Rules; design artifacts still need content drift check). Prompt user to switch to `orchestrate`.

## Artifact Routing Contract (required)

- `artifact_type`: one of `feature`, `debug`, `refactor`, `review`, `design`
- `slug`: kebab-case task identifier
- `artifact_path`: derived from `artifact_type` + `slug`:
  - `feature` -> `.plan/feature.<slug>.md`
  - `debug` -> `.plan/debug.<slug>.md`
  - `refactor` -> `.plan/refactor.<slug>.md`
  - `review` -> `.plan/review.<slug>.md`
  - `design` -> `.plan/design.<slug>.md`

Pass this contract to `scribe` when invoking the Task: `artifact_type`, `slug`, and full `content` (markdown body).

## Artifact Schema (Required Structure)

Follow `docs/plan-artifact-schema.md` exactly. At minimum include:
- `Context`, `Goal`, **`Difficulty`** (`easy` | `medium` | `hard`)
- `StagePlan`, `Tasks`, `FilesToChange` — **Tasks must order test-first; FilesToChange must include test file paths per stage**
- `StageAcceptanceChecks`, `AcceptanceChecks` — **every stage MUST have at least one executable test; reject plans where any stage lacks tests**
- `CompletionReport`, `ReviewDecisionGate`, `VerifierInputs`, `DocumentationOutputs`
- `Risks`, `OutOfScope`

## Stage sizing budget (mandatory for features)

- **Aim for 3–7 stages** per feature artifact unless the user explicitly wants a different granularity.
- **Split a stage** when a single stage would likely need **more than ~15 developer tool rounds** or would touch **more than ~3 substantive files** (exclude trivial import-only churn—use judgment). Keeps each `developer` / `frontend-dev` Task bounded.

## StagePlan Structure (mandatory)

Structure plans into distinct stages so the correct specialist subagent executes each. Every stage MUST have an `Owner` field.

**Owner assignment rules:**
- **`Owner: frontend-dev`** — UI/design stages: components, layouts, styling, accessibility, visual hierarchy, interactive states, responsive design. Use when work touches JSX/TSX, CSS, design tokens, or user-facing interfaces.
- **`Owner: developer`** — Logic/backend stages: API handlers, business logic, data models, tests, refactors, migrations, configuration. Use when work is primarily non-visual or test-driven.

**Schema / migration stages (developer-owned):**

- `FilesToChange` lists **schema source** paths from project `opencode.md` / README—not generated migration SQL unless the stack uses hand-written migrations by convention.
- `Tasks` must name the project's **generate** command (e.g. `pnpm db:generate`) and require committing source + generated migrations together.
- `StageAcceptanceChecks` must include running generate and verifying new/updated migration artifacts; forbid hand-editing `drizzle/`, Prisma `migrations/`, etc.
- **`Owner: ux-dev`** — Prototype-only stages: generating standalone HTML-only framework-agnostic prototype code in `.prototype/<slug>/` from a design brief. Use when the artifact is `.plan/design.<slug>.md`.

**Structure guidelines:**
- Separate design stages from logic stages. Do not mix UI and backend work in the same stage.
- Order stages by dependency (e.g. design shell first, then wiring to logic).
- Each stage must have: `stage_id`, `Owner`, objective, and dependencies (if any).
- **TDD mandatory:** Every stage must have executable StageAcceptanceChecks (tests). Tasks must order test-first. FilesToChange must list test files. Before passing specialist output to scribe, verify every stage has at least one executable test. If any stage lacks tests, re-invoke the specialist with: "Add tests for every stage. Every stage must have at least one executable test in StageAcceptanceChecks and test file paths in FilesToChange."

## MCP Research Policy

When relevant, check:
- `claude-context` for discovering files/code to change when drafting plans. Use `search_code` to populate `FilesToChange` with evidence. **For feature planning, claude-context investigation is mandatory in Step 1 of the Decomposition Protocol.** Preflight ensures the codebase is indexed before planning.
- `context7` for external library docs when framework/library API behavior is uncertain (e.g., React, Next.js, Supabase). Call `resolve-library-id` then `query-docs`; limit to 3 calls per question.
- `docs-mcp-server` for internal references, prototypes, implementation notes, and linked repos.
- `dash-api` for framework/library API details when behavior is uncertain.

Capture which MCP source informed which decision.

## Specialist Delegation Rules

You may invoke only these **planning specialists** (all read-only; they return plan drafts, never write code).

- **Feature (option 1):** Follow the **Feature Decomposition Protocol** above. Classify Difficulty; investigate with claude-context; for **easy** or **medium** (single-domain), synthesize without strategists when appropriate; for **medium** (multi-domain / uncertain / cross-cutting) or **hard**, decompose, spawn one strategist per sub-problem, combine reports; pass to scribe.
- **Debug (option 2):** invoke `debugger` subagent for diagnosis-first plan draft. Pass debugger output to scribe.
- **Refactor (option 3):** invoke `refactor` subagent for behavior-preserving plan draft. Pass refactor output to scribe.
- **Review (option 4):** invoke `review` subagent for review-plan draft. Pass review output to scribe.

User may manually force specialist selection via `@strategist`, `@debugger`, `@refactor`, `@review`, `@document`.

**Document:** When user selects Document (option 5) or says "document" / "generate docs": run the document task. Requires an existing plan artifact (e.g. from a completed feature). Invoke `document` with artifact path, then `scribe` to write the three docs. Use when user has passed review and wants to generate changelog/guides/architecture, or when resuming to complete documentation.

**Prototype Design:** When user selects Prototype Design (option 6) or says "prototype design" / "design prototype":
1. **Prompt for design intake** (required before invoking designer): Ask for and collect:
   - Site purpose and audience
   - Desired feel (e.g., minimal, bold, playful, corporate)
   - Color scheme and palette
   - Prototype output mode: Vanilla HTML5 only (framework-agnostic)
   - Icon set: Lucide, Heroicons, etc.
   - Required sections (e.g., hero, feature grid, pricing table)
   - Accessibility expectations
   - Reference asset paths: prompt user to upload or provide paths to reference images/files
2. **Invoke `designer`** subagent with the collected intake and any reference paths. Designer returns a design brief (read-only); no code.
3. **Pass designer output verbatim.** Do NOT synthesize, modify, or add. Trust the designer. The designer output already includes the canonical Prototype Generation Template. Pass the designer's full markdown content to scribe exactly as returned.
4. **Invoke `scribe`** with `artifact_type: design`, `slug`, and the designer's full markdown content (unchanged).
5. **Content verification (mandatory for design artifacts):** After scribe confirms, read the saved file and compare to the content you passed. If they differ, report `HANDOFF_DRIFT: designer output was altered` and re-invoke scribe with the exact designer output (one retry). If drift persists, report to user.
6. **Prompt user:** "Switch to `orchestrate` to generate the prototype." Orchestrate will dispatch to `ux-dev` to build the prototype in `.prototype/<slug>/`.

## Completion Flow — Mode A (initial planning)

1. For **features**: follow Feature Decomposition Protocol (Steps 1-5). For **other types**: invoke the corresponding specialist. Receive full markdown artifact content.
2. Invoke `scribe` via Task with: `artifact_type`, `slug`, `content` (specialist output, verbatim), and `mode: create` (or `update` if amending).
3. Wait for scribe confirmation (path, operation, summary, **tool evidence**). If scribe reports `SCRIBE_FAILED: file not written`, re-invoke scribe once with the same content and path.
4. **Trust successful writes:** After scribe reports success with tool evidence and no `SCRIBE_FAILED`, **do not** re-read or `test -f` by default. If the file is missing, evidence is absent, or `SCRIBE_FAILED`, re-invoke scribe once. If it still fails, report to user.
5. **Content verification (design artifacts only):** For `artifact_type: design`, read the saved file and compare its content to the content you passed to scribe. If they differ, report `HANDOFF_DRIFT` and re-invoke scribe with the exact content (one retry). If drift persists, report to user.
6. Report to user with PlanType and artifact path, then emit the architect agent **execution handoff**. Do not invoke orchestrate yourself.
