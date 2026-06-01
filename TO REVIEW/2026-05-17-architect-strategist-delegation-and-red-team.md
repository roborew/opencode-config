# 2026-05-17 — Architect Strategist Delegation and Red-Team Planning

**Cursor chat created:** 2026-05-17 (filesystem birth date of transcript; first user message `Sunday, May 17, 2026, 11:02 PM (UTC+1)`).

**Cursor chat ID:** `c2e25c96-97e1-4a33-a502-d8df79d6413e`

**Transcript path:** `~/.cursor/projects/Users-robo-config-opencode/agent-transcripts/c2e25c96-97e1-4a33-a502-d8df79d6413e/c2e25c96-97e1-4a33-a502-d8df79d6413e.jsonl`

**Filename rule:** `YYYY-MM-DD-<slug>.md` where `YYYY-MM-DD` is the **Cursor chat creation date** (not the date this review note was edited later).

**Session scope:** Clarify when `architect` invokes `strategist` vs doing planning alone after `grill-me`; refine policy toward bounded **parallel** scoped fan-out plus a mandatory **`## Delegation Decision`** record; add **`mode: scoped`** and **`mode: red-team`** to the strategist contract; align plan artifact schema and operator docs.

**Status:** Design and implementation were agreed and applied in chat `c2e25c96-…` (`validate-opencode-config: OK`). **Re-apply** from §7 if `rg` finds no `Delegation Decision` / `mode: red-team` in the repo.

**Trigger:** User observed architect running `grill-me` then authoring the full plan and scribing, without strategists — wanted parallel sub-agents and clearer specialism alongside Grill Me.

---

## Executive summary

| Area | Outcome |
| --- | --- |
| Problem diagnosis | Strategists are **decomposition workers**, not default quality gates; medium single-domain plans were allowed to skip them entirely |
| Policy shift | **Scoped strategists** for breadth on multi-domain / uncertain / hard work; **red-team strategist** for plan challenge on medium+ |
| Artifact | New required section **`## Delegation Decision`** on every feature `.plan` |
| Strategist modes | `mode: scoped` (sub-problem report) and `mode: red-team` (challenge draft plan) |
| Parallelism | Architect launches scoped strategist Tasks **in parallel** where the host supports it |
| Docs | `architect-plan`, `architect` agent, `strategist` agent/skill, `plan-artifact-schema`, `RUNBOOK`, `README` |

---

## 1. Background (pre-change behaviour)

### Intended pipeline

```text
grill-me (Mode A interview)
  → architect-plan (investigate, classify Difficulty, maybe delegate)
  → scribe (write .plan artifact)
  → user switches to orchestrate
```

### When strategists were invoked (old rules)

| Difficulty | Strategist use |
| --- | --- |
| **easy** | No strategists; architect synthesizes |
| **medium** | No strategists if **single-domain** and investigation sufficient |
| **medium** | Scoped strategists if multi-domain, high uncertainty, or cross-cutting |
| **hard** | Must decompose; one scoped strategist per sub-problem |

**Why the user saw no strategists:** A bounded site feature often classifies as **medium single-domain** → architect may skip strategists, investigate, write the full plan, and Task `scribe`. That was by design, not broken routing.

### Agreed refinement (this chat)

| Pattern | Use when |
| --- | --- |
| **Scoped strategist** | 2+ separable concerns (API vs UI vs auth vs migration, etc.) |
| **Red-team strategist** | Challenge assumptions, tests, sequencing, scope, ownership on a **draft** plan |
| **Architect-only** | Easy, obvious, 1–2 files, linear work |
| **Skip scoped + red-team** | Only when **clearly low-risk** (document skip reason in `Delegation Decision`) |

**High-value pattern:** 2–5 **scoped** strategists in parallel **plus** one **red-team** pass on the merged draft.

### Final policy (post-change)

| Difficulty | Scoped strategists | Red-team strategist | Architect synthesizes alone |
| --- | --- | --- | --- |
| **easy** | No (default) | Only if a **specific uncertainty** remains | Yes (default) |
| **medium** | When multi-domain, uncertain, or cross-cutting | **Normally yes** unless clearly low-risk | Only when single-domain, sufficient investigation, **and** low-risk |
| **hard** | **2–5** scoped, parallel where supported | **Required** on merged draft before scribe | No — must decompose |

### Parallel flow (architect)

```text
1. grill-me (if Mode A routing requires it)
2. architect: Claude Context readiness + investigation
3. classify Difficulty
4. if scoped strategists needed:
     Task strategist (mode: scoped) × N  [parallel where supported]
5. architect: merge Sub-Problem Reports → draft plan
6. if red-team required:
     Task strategist (mode: red-team) on merged draft
7. architect: apply accepted findings; fill Delegation Decision
8. Task scribe → .plan/feature.<slug>.md
9. prompt: Switch to orchestrate
```

---

## 2. Verify whether changes are landed

```bash
cd ~/.config/opencode
rg -l "Delegation Decision|mode: red-team" agents skills docs README.md
bash scripts/validate-opencode-config.sh
```

- **Zero hits** → apply §7 in order.
- **Expected validation:** `validate-opencode-config: OK`

---

## 3. Files touched (checklist)

| # | File | What changed |
| --- | --- | --- |
| 1 | `agents/architect.md` | Decomposition Protocol steps 3–6; Feature delegation bullet; Hard Rule #7; strategist Task `mode:` |
| 2 | `skills/architect-plan/SKILL.md` | Opening summary; Difficulty table; medium path + red-team; Steps 3–4; schema + Delegation Decision block; specialist rules |
| 3 | `agents/strategist.md` | Dual-mode intro; Input Mode Contract; scoped vs red-team responsibilities; Hard Rules |
| 4 | `skills/strategist/SKILL.md` | Modes; red-team report format; workflow |
| 5 | `docs/plan-artifact-schema.md` | Required section + example skeleton |
| 6 | `docs/RUNBOOK.md` | Overview + Canonical Flow step 2 |
| 7 | `README.md` | One bullet on architect delegation (if README still has custom pipeline section) |

---

## 4. Mandatory plan artifact section

Every **feature** `.plan` must include:

```markdown
## Delegation Decision
- **Strategists used:** yes | no
- **Reason:** <why scoped strategists were used or skipped>
- **Sub-problems delegated:** <none | list of sub-problem IDs/titles>
- **Red-team pass:** skipped | requested | applied
- **Red-team reason:** <why the pass ran or why it was safe to skip>
```

---

## 5. Architect Task prompts (copy-paste)

### Scoped strategist (`load: auto`)

```text
load: auto
mode: scoped
Sub-problem ID: sp-ui-shell
Title: Public site layout and component shell
Description: Plan stages for marketing page sections and shared layout without backend changes.
Context: |
  - src/app/page.tsx — existing hero + grid
  - components/Header.tsx — nav pattern
Constraints: UI only; no API or DB in this slice.
Global context: Next.js App Router; slug: site-refresh

Produce your Sub-Problem Report and return immediately. Do not iterate or loop.
```

### Red-team strategist (`load: auto`)

```text
load: auto
mode: red-team
draft_plan: |
  <paste full merged markdown plan here>
context: |
  Investigation summary from architect (claude-context paths, risks).
risk_focus: tests, stage sizing, cross-cutting dependencies

Produce your Red-Team Report and return immediately. Do not iterate or loop.
```

---

## 6. Strategist output formats (reference)

### Sub-Problem Report (unchanged shape; see `skills/strategist/SKILL.md`)

### Red-Team Report (new — full template)

```markdown
# Red-Team Report

## Verdict
sound | needs changes | blocked by gaps

## Findings

### high: Missing stage tests
- **Issue:** `stage-api` has no executable StageAcceptanceChecks.
- **Why it matters:** Verifier cannot gate the stage; orchestrate may pass without evidence.
- **Recommended plan change:** Add `pnpm test src/...` to StageAcceptanceChecks and test paths in FilesToChange.

## Test and Verification Gaps
- ...

## Sequencing and Ownership Gaps
- ...

## Residual Risks
- ...

## Gaps
- ...
```

---

## 7. Recreation guide — exact edits per file

Apply with search-and-replace or patch. Snippets show **target text after this chat’s implementation**. If your file already matches, skip that hunk.

---

### 7.1 `agents/architect.md`

#### 7.1.1 `## When Invoking Subagents` — strategist line

**Find:**

```markdown
- **For strategists:** Each instance is scoped to one sub-problem. Require: "Produce your Sub-Problem Report and return immediately. Do not iterate or loop."
```

**Replace with:**

```markdown
- **For strategists:** Include `mode: scoped` or `mode: red-team` in every Task prompt. Each scoped instance covers one sub-problem. Require: "Produce your Sub-Problem Report and return immediately. Do not iterate or loop." For red-team: "Produce your Red-Team Report and return immediately. Do not iterate or loop."
```

#### 7.1.2 `## Feature Planning: Decomposition Protocol` — steps 1–5

**Find:**

```markdown
1. **Classify Difficulty** — `easy` | `medium` | `hard` (write `## Difficulty` into the artifact).
2. **Investigate** — After satisfying the Claude Context readiness gate above, use `claude-context` MCP (`search_code`, `find_files`) to explore the codebase.
3. **Easy** — Synthesize the full plan yourself (no strategists); then scribe and handoff.
4. **Medium** — If work is **single-domain** (one stack, bounded area) and investigation is sufficient, **synthesize the full plan yourself** (no strategists). If **multi-domain** (e.g. backend + frontend + infra), **high uncertainty** after investigation, or **cross-cutting** risk: decompose; spawn one **scoped** `strategist` per sub-problem; combine reports; scribe and handoff.
5. **Hard** — Decompose into sub-problems; spawn one **scoped** `strategist` per sub-problem (never one monolithic unscoped strategist). Combine reports, add global sections including **Difficulty**, then scribe and handoff.
```

**Replace with:**

```markdown
1. **Classify Difficulty** — `easy` | `medium` | `hard` (write `## Difficulty` into the artifact).
2. **Investigate** — After satisfying the Claude Context readiness gate above, use `claude-context` MCP (`search_code`, `find_files`) to explore the codebase.
3. **Delegation Decision** — Every feature artifact must include `## Delegation Decision` with strategists used/skipped, reason, scoped sub-problems, and red-team pass status.
4. **Easy** — Synthesize the full plan yourself (no scoped strategists) unless a specific uncertainty warrants one red-team pass; then scribe and handoff.
5. **Medium** — If work is **single-domain** (one stack, bounded area) and investigation is sufficient, you may skip scoped strategists, but run one **red-team** `strategist` unless the work is clearly low-risk. If **multi-domain** (e.g. backend + frontend + infra), **high uncertainty** after investigation, or **cross-cutting** risk: decompose; spawn one **scoped** `strategist` per sub-problem in parallel where supported; combine reports; then run a red-team strategist on the merged draft unless risk is already fully covered.
6. **Hard** — Decompose into sub-problems; spawn **2–5** **scoped** `strategist` instances, one per sub-problem (never one monolithic unscoped strategist), in parallel where supported. Combine reports, run a red-team strategist on the merged draft, add global sections including **Difficulty** and **Delegation Decision**, then scribe and handoff.
```

#### 7.1.3 `## When to Delegate to Specialists` — Feature bullet

**Find:**

```markdown
- **Feature** (option 1) → Follow the Decomposition Protocol above (via `architect-plan`). Easy: you author the plan. Medium: you author unless multi-domain / high uncertainty / cross-cutting, then strategists. Hard: scoped strategist(s), combine; pass to scribe.
```

**Replace with:**

```markdown
- **Feature** (option 1) → Follow the Decomposition Protocol above (via `architect-plan`). Easy: you author the plan and document strategist skip/use in **Delegation Decision**. Medium: you author only when single-domain and low-risk enough; otherwise use scoped strategists, and normally run a red-team strategist. Hard: scoped strategist(s), red-team merged draft, combine; pass to scribe.
```

#### 7.1.4 Hard Rules — rule 7

**Find:**

```markdown
7. **Feature planning by Difficulty.** Classify each feature as `easy`, `medium`, or `hard` and write `## Difficulty` into the artifact. **Easy:** synthesize without strategists. **Medium:** synthesize without strategists when single-domain and investigation suffices; otherwise decompose and use one scoped strategist per sub-problem (never one monolithic unscoped strategist). **Hard:** decompose; one scoped strategist per sub-problem; pass richer context per strategist than for medium.
```

**Replace with:**

```markdown
7. **Feature planning by Difficulty.** Classify each feature as `easy`, `medium`, or `hard` and write `## Difficulty` into the artifact. Every feature artifact must include `## Delegation Decision` covering strategist use/skips, reasons, sub-problems, and red-team pass status. **Easy:** synthesize without scoped strategists unless a specific uncertainty warrants one red-team pass. **Medium:** synthesize without scoped strategists only when single-domain and sufficiently low-risk; normally run a red-team strategist, and use one scoped strategist per sub-problem for multi-domain, uncertain, or cross-cutting work (never one monolithic unscoped strategist). **Hard:** decompose into 2–5 scoped strategist tasks, pass richer context per strategist than for medium, and run a red-team strategist against the merged draft before scribe.
```

---

### 7.2 `skills/architect-plan/SKILL.md`

#### 7.2.1 Mode A opening paragraph (after grill-me prerequisite)

**Find:**

```markdown
Classify task type. For **features**, classify **Difficulty** (`easy` | `medium` | `hard`), investigate via `claude-context`, then: **easy** — synthesize without strategists; **medium** — synthesize without strategists when single-domain and investigation suffices, else decompose and spawn scoped `strategist`(s); **hard** — decompose, spawn one `strategist` per sub-problem, combine reports. Always include `Difficulty` in the artifact. Pass the plan to scribe (trust successful scribe writes per agent Hard Rules), prompt user to switch to `orchestrate`. For other plan types, invoke the corresponding specialist directly.
```

**Replace with:**

```markdown
Classify task type. For **features**, classify **Difficulty** (`easy` | `medium` | `hard`), investigate via `claude-context`, then: **easy** — synthesize without scoped strategists unless a specific uncertainty warrants one red-team pass; **medium** — synthesize without scoped strategists only when single-domain and sufficiently low-risk, otherwise decompose and spawn scoped `strategist`(s); normally run one red-team strategist for medium plans; **hard** — decompose, spawn 2–5 scoped `strategist` instances, combine reports, then run a red-team strategist on the merged draft. Always include `Difficulty` and `Delegation Decision` in the artifact. Pass the plan to scribe (trust successful scribe writes per agent Hard Rules), prompt user to switch to `orchestrate`. For other plan types, invoke the corresponding specialist directly.
```

#### 7.2.2 Step 0 Difficulty table

**Find:**

```markdown
| **easy** | 1–2 stages, single concern, few files, no cross-cutting changes | **Do not** spawn strategists; you synthesize the full plan from investigation. |
| **medium** | 3–4 stages, multiple files, moderate complexity | **Default:** synthesize the full plan yourself if **single-domain** (one stack, bounded area) and investigation is sufficient. **Spawn** scoped strategists when **multi-domain** (e.g. backend + frontend + infra), **high uncertainty** after investigation, or **cross-cutting** risk. |
| **hard** | 5+ stages, cross-cutting concerns, high risk | **Must** decompose and spawn strategists; investigate more thoroughly and pass **richer** context per sub-problem than for medium. |
```

**Replace with:**

```markdown
| **easy** | 1–2 stages, single concern, few files, no cross-cutting changes | **Do not** spawn scoped strategists; synthesize the full plan from investigation. Use one red-team strategist only when a specific uncertainty remains. |
| **medium** | 3–4 stages, multiple files, moderate complexity | **Default:** synthesize the full plan yourself only if **single-domain** (one stack, bounded area), investigation is sufficient, and risk is low. **Normally run one red-team strategist.** Spawn scoped strategists when **multi-domain** (e.g. backend + frontend + infra), **high uncertainty** after investigation, or **cross-cutting** risk. |
| **hard** | 5+ stages, cross-cutting concerns, high risk | **Must** decompose and spawn 2–5 scoped strategists; investigate more thoroughly and pass **richer** context per sub-problem than for medium. Must run a red-team strategist on the merged draft. |
```

#### 7.2.3 Step 2 — easy / medium intro lines

**Find:**

```markdown
For **easy** difficulty: skip to **Easy path — synthesize plan** (after Step 1). Do not spawn strategists.

For **medium** when **single-domain** and investigation suffices: skip to **Medium synthesize path** (after Step 1)—author the full artifact yourself (same quality bar as easy); do not spawn strategists.
```

**Replace with:**

```markdown
For **easy** difficulty: skip to **Easy path — synthesize plan** (after Step 1). Do not spawn scoped strategists.

For **medium** when **single-domain**, investigation suffices, and risk is low: skip to **Medium synthesize path** (after Step 1)—author the full artifact yourself (same quality bar as easy); do not spawn scoped strategists. Normally still run one red-team strategist against the draft unless the task is clearly low-risk.
```

#### 7.2.4 Easy path — artifact fields

**Find:**

```markdown
1. Using investigation evidence from Step 1, author the full feature artifact yourself: `Context`, `Goal`, `Difficulty: easy`, `StagePlan`, `Tasks`, `FilesToChange`, `StageAcceptanceChecks`, `AcceptanceChecks`, `CompletionReport`, `ReviewDecisionGate`, `VerifierInputs`, `DocumentationOutputs`, `Risks`, `OutOfScope`, etc., per `docs/plan-artifact-schema.md`.
```

**Replace with:**

```markdown
1. Using investigation evidence from Step 1, author the full feature artifact yourself: `Context`, `Goal`, `Difficulty: easy`, `Delegation Decision`, `StagePlan`, `Tasks`, `FilesToChange`, `StageAcceptanceChecks`, `AcceptanceChecks`, `CompletionReport`, `ReviewDecisionGate`, `VerifierInputs`, `DocumentationOutputs`, `Risks`, `OutOfScope`, etc., per `docs/plan-artifact-schema.md`.
```

#### 7.2.5 Medium synthesize path

**Find:**

```markdown
1. Author the full feature artifact yourself with `Difficulty: medium` and the same schema requirements as the easy path.
2. Apply **Stage sizing budget** (below): aim for **3–7 stages**; split stages that would exceed **~15 developer tool rounds** or **>3 substantive files** per stage (judgment for trivial imports).
3. Go to **Step 5: Scribe and handoff** (skip Steps 3–4).
```

**Replace with:**

```markdown
1. Author the full feature artifact yourself with `Difficulty: medium`, `Delegation Decision`, and the same schema requirements as the easy path.
2. Apply **Stage sizing budget** (below): aim for **3–7 stages**; split stages that would exceed **~15 developer tool rounds** or **>3 substantive files** per stage (judgment for trivial imports).
3. Run one red-team strategist against the draft unless the task is clearly low-risk. Apply accepted red-team findings before scribe.
4. Go to **Step 5: Scribe and handoff** (skip scoped strategist decomposition).
```

#### 7.2.6 Step 3 heading and Task block

**Find:**

```markdown
### Step 3: Spawn strategists (one per sub-problem; when required)

For each sub-problem, invoke a separate `strategist` via Task with:

```
Sub-problem ID: <sp-id>
```

**Replace with:**

```markdown
### Step 3: Spawn scoped strategists (one per sub-problem; when required)

For each sub-problem, invoke a separate `strategist` via Task with `mode: scoped`. Launch these Tasks in parallel where the host supports parallel subagent dispatch.

```
mode: scoped
Sub-problem ID: <sp-id>
```

#### 7.2.7 Step 4 — combine + red-team

**Find:**

```markdown
### Step 4: Combine reports into full feature plan (when strategists were used)

After all strategist sub-problems report back:

1. **Collect** all Sub-Problem Reports.
2. **Merge stages** into a single ordered StagePlan. Resolve cross-sub-problem dependencies (e.g. if sp-2's UI depends on sp-1's data model, order sp-1 stages first).
3. **Combine** Tasks, FilesToChange, StageAcceptanceChecks, Risks from all reports.
4. **Add global sections**: Context, Goal, **Difficulty** (copy the level from Step 0), AcceptanceChecks (end-to-end), CompletionReport, ReviewDecisionGate, VerifierInputs, DocumentationOutputs, OutOfScope.
5. **Note gaps**: If any strategist reported gaps, investigate those gaps with `claude-context` and fill them in the combined plan.
6. **Set artifact metadata**: `artifact_type: feature`, `slug`, path `.plan/feature.<slug>.md`.
```

**Replace with:**

```markdown
### Step 4: Combine reports and red-team the draft (when strategists were used)

After all strategist sub-problems report back:

1. **Collect** all Sub-Problem Reports.
2. **Merge stages** into a single ordered StagePlan. Resolve cross-sub-problem dependencies (e.g. if sp-2's UI depends on sp-1's data model, order sp-1 stages first).
3. **Combine** Tasks, FilesToChange, StageAcceptanceChecks, Risks from all reports.
4. **Add global sections**: Context, Goal, **Difficulty** (copy the level from Step 0), **Delegation Decision**, AcceptanceChecks (end-to-end), CompletionReport, ReviewDecisionGate, VerifierInputs, DocumentationOutputs, OutOfScope.
5. **Note gaps**: If any strategist reported gaps, investigate those gaps with `claude-context` and fill them in the combined plan.
6. **Red-team**: For hard plans, and for medium plans unless risk is already fully covered, invoke one strategist with `mode: red-team` and the merged draft. Apply accepted findings and record red-team status in `Delegation Decision`.
7. **Set artifact metadata**: `artifact_type: feature`, `slug`, path `.plan/feature.<slug>.md`.
```

#### 7.2.8 Artifact Schema minimum list — add Delegation Decision

**Find:**

```markdown
- `Context`, `Goal`, **`Difficulty`** (`easy` | `medium` | `hard`)
```

**Replace with:**

```markdown
- `Context`, `Goal`, **`Difficulty`** (`easy` | `medium` | `hard`), **`Delegation Decision`**
```

#### 7.2.9 Insert new subsection after Artifact Schema minimum list

**Insert after** the `Risks`, `OutOfScope` bullet list under `## Artifact Schema (Required Structure)`:

```markdown
### Delegation Decision Structure

Every feature artifact must include the **Delegation Decision** block exactly as specified in §4 of this review doc (and in `docs/plan-artifact-schema.md` example skeleton).
```

#### 7.2.10 Specialist Delegation Rules — Feature bullet

**Find:**

```markdown
- **Feature (option 1):** Follow the **Feature Decomposition Protocol** above. Classify Difficulty; investigate with claude-context; for **easy** or **medium** (single-domain), synthesize without strategists when appropriate; for **medium** (multi-domain / uncertain / cross-cutting) or **hard**, decompose, spawn one strategist per sub-problem, combine reports; pass to scribe.
```

**Replace with:**

```markdown
- **Feature (option 1):** Follow the **Feature Decomposition Protocol** above. Classify Difficulty; investigate with claude-context; for **easy**, synthesize without scoped strategists unless a specific uncertainty warrants one red-team pass; for **medium**, synthesize without scoped strategists only when single-domain and low-risk, and normally run one red-team strategist; for **medium** (multi-domain / uncertain / cross-cutting) or **hard**, decompose, spawn scoped strategists in parallel where supported, combine reports, red-team the merged draft, and pass to scribe.
```

---

### 7.3 `agents/strategist.md`

**Replace** the opening section from `# Strategist Agent` through `## Scoped Sub-Problem Contract` header with:

```markdown
# Strategist Agent

You are the Strategist agent: a feature planning specialist with two modes:

- **`mode: scoped`** — receive an isolated sub-problem from the parent architect and return a concise investigation report covering only that sub-problem.
- **`mode: red-team`** — receive a draft feature plan and challenge it for missing tests, sequencing errors, scope drift, risk, unclear ownership, and gaps.

You are read-only; you do not write files or execute implementation.

## Execution readiness

- **Parent-directed load** (takes precedence):
  - `load: full` → load the `strategist` skill before first tool use.
  - `load: minimal` → Hard Rules and **Input Mode Contract** only; do not load the skill.
- **Auto-load triggers** (when parent says `load: auto` or omits the directive): load the `strategist` skill if **any** are true:
  - Sub-problem report or red-team report template/acceptance shape is ambiguous.
  - First strategist run for this artifact in this session.
- Load the skill **once** before your single-pass report—do not loop on skill load. Skill load never blocks completion. If load fails, report `SKILL_UNAVAILABLE: strategist` and stop unless the parent tells you to proceed without the skill.

## Input Mode Contract

The parent architect must provide one of:

- `mode: scoped`
- `mode: red-team`

If mode is omitted, default to `mode: scoped` only when the prompt clearly includes a sub-problem ID/title/description. Otherwise return `STRATEGIST_INPUT_ERROR: missing mode`.

## Scoped Sub-Problem Contract
```

**Replace** `## Your Responsibilities` bullet list with:

```markdown
## Your Responsibilities

In `mode: scoped`:

- Analyse the sub-problem using only the provided context and your own MCP lookups where the architect's context is insufficient.
- Produce a concise **Sub-Problem Report** with stages, tasks, files to change, and acceptance checks — scoped only to your assigned sub-problem.
- Structure stages with `Owner: frontend-dev` for UI stages and `Owner: developer` for logic stages.
- Return the report to the parent. The architect combines reports from all sub-problems into the full plan.

In `mode: red-team`:

- Challenge the draft plan only; do not rewrite the full plan.
- Look for missing executable tests, vague file ownership, unsafe stage ordering, hidden cross-domain dependencies, unaddressed security/performance/data risks, and over-large stages.
- Return a concise **Red-Team Report** with findings ordered by severity and concrete plan changes the architect should apply.
- If the plan is sound, say so and list any residual risks.
```

**Replace** Hard Rules 1 and 6:

```markdown
1. **Mode-bound.** Address only the assigned mode. In `mode: scoped`, address only your assigned sub-problem. In `mode: red-team`, challenge only the provided draft plan.
```

```markdown
6. **Concise output.** Keep the report focused: scoped mode returns investigation findings, proposed stages, files to change, acceptance checks; red-team mode returns findings, severity, and concrete changes. No preamble, no summaries of what you are about to do.
```

---

### 7.4 `skills/strategist/SKILL.md`

**Replace** frontmatter `description` / `roleReminder` and body intro through Hard Rules #8 with the dual-mode version. Minimum changes:

1. Update `description` to mention red-team.
2. Replace `## Strategist` paragraph and Hard Rules 1, 6–8 per §7.3 themes.
3. Add `## Input Contract` mode section + `### Red-Team Mode Inputs`.
4. Update `## Workflow` to 4 steps (scoped vs red-team).
5. Append full `## Red-Team Report Format` from §6.
6. Update `## Completion` last sentence to mention Red-Team Report.

**Full target for key new blocks:**

```markdown
---
name: strategist
description: "Scoped feature planning specialist (sub-problem report) and red-team plan challenger for architect drafts"
modelTier: "smart"
roleReminder: "mode: scoped → Sub-Problem Report; mode: red-team → Red-Team Report. One shot, no loop."
---

## Strategist

You are a feature planning specialist. The parent architect assigns one of two modes:

- **`mode: scoped`**: produce a Sub-Problem Report for your assigned slice only.
- **`mode: red-team`**: produce a Red-Team Report; do not rewrite the full plan.

You are read-only; do not write files or execute implementation.
```

(See §6 for Red-Team Report template; copy remainder of scoped workflow from existing skill, adjusting Hard Rules as in §7.3.)

---

### 7.5 `docs/plan-artifact-schema.md`

**In `## Required Sections` table**, after **Difficulty** row, add:

```markdown
| **Delegation Decision** | Feature planning record of strategist use/skips, scoped sub-problems, and red-team pass status |
```

**In `## Example Skeleton`**, after `## Difficulty` block, insert:

```markdown
## Delegation Decision
- **Strategists used:** yes | no
- **Reason:** why scoped strategists were used or skipped
- **Sub-problems delegated:** none | `sp-id` list with titles
- **Red-team pass:** skipped | requested | applied
- **Red-team reason:** why the challenge pass ran or why it was safe to skip
```

---

### 7.6 `docs/RUNBOOK.md`

**Overview — Primary planning mode bullet**, append after `Invokes:` list (or weave in):

```markdown
May Task scoped/red-team **`strategist`** for feature planning (see `architect-plan` Decomposition Protocol).
```

**Canonical Flow step 2** — replace the Features sentence with:

```markdown
2. **Features:** architect classifies **`## Difficulty`**, runs Claude Context readiness, investigates, records **`## Delegation Decision`**, uses scoped strategists for medium multi-domain/uncertain/cross-cutting and hard work, normally runs a red-team strategist for medium plans, always red-teams hard merged drafts, then **`scribe`** writes `.plan/feature.<slug>.md`. **Easy** may skip scoped strategists; **medium** single-domain low-risk may skip scoped but should red-team unless clearly safe to skip.
```

*(Adjust wording to match your RUNBOOK’s current step numbering if steps shifted.)*

---

### 7.7 `README.md`

If the README has a **Custom pipeline** or **architect** bullet, add:

```markdown
- **`architect`** — planning; records **`Delegation Decision`** in feature plans; uses scoped strategists for larger slices and red-teams medium/hard drafts when warranted; invokes `scribe` for `.plan/` artifacts.
```

---

## 8. Conversation arc (audit)

| Step | What happened |
| --- | --- |
| 1 | User asked why architect ran grill-me but not strategist on a site plan |
| 2 | Explained Difficulty-gated delegation; strategists = scoped decomposition, not default QA |
| 3 | User asked about parallel multitask + specialist value |
| 4 | Recommended scoped parallel fan-out + red-team pass; not “strategist on every task” |
| 5 | User: “ok lets do that” — implementation across 7 files |
| 6 | `validate-opencode-config.sh` passed |
| 7 | User requested `TO REVIEW` doc; renamed to chat creation date **2026-05-17** |
| 8 | User requested full recreation snippets + chat creation date metadata (this revision) |

---

## 9. What did not change

- `grill-me` still completes before planning discovery when Mode A routing applies.
- `scribe` remains the only write path for `.plan` artifacts.
- `orchestrate` owns execution; architect does not Task `developer` / `frontend-dev`.
- Post-implementation Mode B does not invoke strategists.
- `opencode.json` agent permissions already allow `task: strategist: allow` on architect — no JSON change required for this feature.

---

## 10. Operator quick reference

| Want | Say / check |
| --- | --- |
| Force decomposition | “This is **hard** / **multi-domain** — run scoped strategists in parallel.” |
| Force challenge pass | “Run **red-team** on the draft before scribe.” |
| Audit a plan | Open `.plan` → verify `## Delegation Decision` |
| Re-land config | §2 verify → §7 apply → `bash scripts/validate-opencode-config.sh` |

---

*Review note for `TO REVIEW/` — prefix **`2026-05-17`** = Cursor chat `c2e25c96-97e1-4a33-a502-d8df79d6413e` creation date.*
