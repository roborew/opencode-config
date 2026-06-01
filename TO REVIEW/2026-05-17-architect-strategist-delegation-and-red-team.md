# 2026-05-17 — Architect Strategist Delegation and Red-Team Planning

**Session scope:** Clarify when `architect` invokes `strategist` vs doing planning alone after `grill-me`; refine policy toward bounded parallel fan-out plus a mandatory **Delegation Decision** record; add **`mode: scoped`** and **`mode: red-team`** to the strategist contract; align plan artifact schema and operator docs.

**Status:** Design and implementation were agreed and applied in this chat (`validate-opencode-config: OK`). If the repo no longer contains the edits below, re-apply from this document (search for `Delegation Decision` / `mode: red-team` — absence means not landed).

**Trigger:** User observed architect running `grill-me` then authoring the full plan and scribing, without strategists — wanted parallel sub-agents and clearer specialism alongside Grill Me.

---

## Executive summary

| Area | Outcome |
| --- | --- |
| Problem diagnosis | Strategists are **decomposition workers**, not default quality gates; medium single-domain plans were allowed to skip them entirely |
| Policy shift | **Scoped strategists** for breadth on multi-domain / uncertain / hard work; **red-team strategist** for plan challenge on medium+ |
| Artifact | New required section **`## Delegation Decision`** on every feature `.plan` |
| Strategist modes | `mode: scoped` (sub-problem report) and `mode: red-team` (challenge draft plan) |
| Parallelism | Architect should launch scoped strategist Tasks **in parallel** where the host supports it |
| Docs | `architect-plan`, `architect` agent, `strategist` agent/skill, `plan-artifact-schema`, `RUNBOOK`, `README` |

---

## Background: how architect planning worked before

### Intended pipeline

```text
grill-me (Mode A interview)
  → architect-plan (investigate, classify Difficulty, maybe delegate)
  → scribe (write .plan artifact)
  → user switches to orchestrate
```

### Sub-agents and roles

| Agent / skill | Role in planning |
| --- | --- |
| **grill-me** | Q&A against domain language (`CONTEXT.md`), ADRs; human alignment before planning |
| **architect** | Read-only coordinator; investigates via `claude-context`; never writes artifacts |
| **strategist** | Scoped sub-problem planner; one-shot Sub-Problem Report per slice |
| **debugger / refactor / review / document / designer** | Type-specific plan drafts for non-feature paths |
| **scribe** | Only write path for `.plan` and allowed docs |

### When strategists were invoked (old rules)

| Difficulty | Strategist use |
| --- | --- |
| **easy** | No strategists; architect synthesizes |
| **medium** | No strategists if **single-domain** and investigation sufficient |
| **medium** | Scoped strategists if multi-domain, high uncertainty, or cross-cutting |
| **hard** | Must decompose; one scoped strategist per sub-problem |

**Why the user saw no strategists:** A bounded site feature often classifies as **medium single-domain** → architect is **explicitly allowed** to skip strategists, investigate, write the full plan, and Task `scribe`. That is by design, not a broken routing.

### What strategists are not

- Not a mandatory “second opinion” on every task
- Not run **during** `grill-me` (grill-me completes first; then planning discovery)
- Not execution agents (`developer` / `frontend-dev` are orchestrate-only)
- Not writers (no file writes; parent merges and scribes)

---

## Design discussion (this chat)

### User goal

Use sub-agents **as much as useful** for multitasking and distinct skills — alongside Grill Me’s human Q&A — so architect is checked, not a single agent doing everything.

### Agreed refinement (not “strategist on every task”)

| Pattern | Use when |
| --- | --- |
| **Scoped strategist** | 2+ separable concerns (API vs UI vs auth vs migration, etc.) |
| **Red-team strategist** | Challenge assumptions, tests, sequencing, scope, ownership on a **draft** plan |
| **Architect-only** | Easy, obvious, 1–2 files, linear work |
| **Skip scoped + red-team** | Only when **clearly low-risk** (document skip reason) |

**Anti-pattern:** Many strategists all looking at the whole task → duplicated context, merge cost, noise.

**High-value pattern:** 2–5 **scoped** strategists in parallel **plus** one **red-team** pass on the merged draft.

---

## Final policy (implemented)

### Decision rule by Difficulty

| Difficulty | Scoped strategists | Red-team strategist | Architect synthesizes alone |
| --- | --- | --- | --- |
| **easy** | No (default) | Only if a **specific uncertainty** remains | Yes (default) |
| **medium** | When multi-domain, uncertain, or cross-cutting | **Normally yes** unless clearly low-risk | Only when single-domain, investigation sufficient, **and** low-risk |
| **hard** | **2–5** scoped, one per sub-problem, parallel where supported | **Required** on merged draft before scribe | No — must decompose |

### Mandatory artifact section

Every feature plan must include:

```markdown
## Delegation Decision
- **Strategists used:** yes | no
- **Reason:** <why scoped strategists were used or skipped>
- **Sub-problems delegated:** <none | list of sub-problem IDs/titles>
- **Red-team pass:** skipped | requested | applied
- **Red-team reason:** <why the pass ran or why it was safe to skip>
```

This stops silent skipping and makes operator review possible.

### Parallel task strategy (architect)

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

### Specialist routing unchanged

| Plan type | Primary delegate |
| --- | --- |
| Product / PRD | `grill-me` → `to-prd` (spec repo) |
| Implementation feature | Decomposition protocol + strategists per table above |
| Debug | `debugger` |
| Refactor | `refactor` (explicit only) |
| Review / sign-off | `review` (Mode B / F) |
| Prototype design | `designer` |
| Document | `document` |

Mode B / Mode F still restrict architect to `review`, `document`, `scribe` only (no strategist in post-implementation review).

---

## Strategist contract changes

### Two modes (parent must set)

| Mode | Input | Output |
| --- | --- | --- |
| **`mode: scoped`** | Sub-problem ID, title, description, pre-investigated context, constraints | **Sub-Problem Report** (stages, tasks, files, tests, risks) |
| **`mode: red-team`** | Draft plan markdown, context, optional `risk_focus` | **Red-Team Report** (verdict, severity-ordered findings, recommended plan changes) |

If `mode` is omitted: default to `scoped` only when sub-problem fields are clear; otherwise `STRATEGIST_INPUT_ERROR: missing mode`.

### Red-team focus areas

- Missing executable tests / weak `StageAcceptanceChecks`
- Vague or wrong stage `Owner`
- Unsafe stage ordering / hidden cross-domain dependencies
- Over-large stages (> ~15 tool rounds or > ~3 substantive files)
- Scope drift, unaddressed security/performance/data risks
- Gaps in verifier / acceptance evidence

Red-team does **not** rewrite the full plan; architect applies accepted changes.

### Scoped strategist Task prompt (unchanged shape + mode)

```text
mode: scoped
Sub-problem ID: <sp-id>
Title: <short title>
Description: <specific question/concern>
Context: <claude-context findings for this slice only>
Constraints: <in-scope / out-of-scope>
Global context: <framework, slug, conventions>

Produce your Sub-Problem Report and return immediately. Do not iterate or loop.
```

### Red-team Task prompt (new)

```text
mode: red-team
draft_plan: <full merged or synthesized markdown>
context: <investigation summary>
risk_focus: <optional>

Produce your Red-Team Report and return immediately. Do not iterate or loop.
```

### Skill dispatch (architect → strategist)

- Default: `load: auto` per existing architect **Skill dispatch hints**
- Scoped decomposition: launch multiple Tasks **in parallel** where supported
- One red-team Task after merge (sequential)

---

## Files changed in this chat

| File | Change |
| --- | --- |
| `agents/architect.md` | Decomposition Protocol steps: **Delegation Decision**, medium red-team default, hard 2–5 scoped + red-team; Hard Rules #7 updated |
| `skills/architect-plan/SKILL.md` | Difficulty table; Medium synthesize path runs red-team; Step 3 `mode: scoped` + parallel; Step 4 red-team; **Delegation Decision Structure**; specialist delegation bullets |
| `agents/strategist.md` | Dual mode intro; Input Mode Contract; scoped vs red-team responsibilities; mode-bound Hard Rules |
| `skills/strategist/SKILL.md` | Mode inputs; Red-Team Report format; workflow split for scoped vs red-team |
| `docs/plan-artifact-schema.md` | **Delegation Decision** in required sections + example skeleton |
| `docs/RUNBOOK.md` | Architect may use scoped/red-team strategists; implementation feature path mentions Delegation Decision + red-team |
| `README.md` | Short note: architect records delegation, scoped strategists, red-teams medium/hard when warranted |

### Validation

```bash
bash scripts/validate-opencode-config.sh
# Expected: validate-opencode-config: OK
```

---

## Operator expectations after this change

### What you should see on the next medium+ feature plan

1. After grill-me, architect investigates and classifies Difficulty.
2. Plan file contains **`## Difficulty`** and **`## Delegation Decision`**.
3. For a typical multi-surface site feature: several scoped strategist reports (or documented skip) and **red-team: applied** (or documented skip with reason).
4. Scribe writes the final artifact; architect prompts orchestrate.

### How to force more delegation in chat

- Say the work is **multi-domain** or **hard** if it is.
- Ask for **`@strategist`** or “run scoped strategists in parallel.”
- Ask for a **red-team pass** on the draft before scribe.
- If the plan lacks **`## Delegation Decision`**, ask architect to add it before accepting the artifact.

### What did not change

- `grill-me` still runs before planning discovery (when Mode A routing applies).
- `scribe` remains the only write path.
- `orchestrate` still owns execution; architect does not Task `developer` / `frontend-dev`.
- Post-implementation **Mode B** still does not invoke strategists.

---

## Re-apply checklist (if edits missing from repo)

Search the codebase:

```bash
rg -l "Delegation Decision|mode: red-team" agents skills docs
```

If zero hits, apply the sections in **Final policy** and **Files changed** above to the listed paths, then run `bash scripts/validate-opencode-config.sh`.

---

## Related references

- `agents/architect.md` — Feature Planning: Decomposition Protocol, Skill routing, Task targets
- `skills/architect-plan/SKILL.md` — Feature Decomposition Protocol (Steps 0–5)
- `agents/strategist.md` — Scoped Sub-Problem Contract, modes
- `skills/strategist/SKILL.md` — Sub-Problem Report and Red-Team Report formats
- `docs/plan-artifact-schema.md` — Required headings for `.plan` artifacts
- `docs/RUNBOOK.md` — Canonical flow, agent matrix
- `README.md` — Daily use / how it works (short)

---

## Conversation arc (for audit)

1. **Explained** current architect → grill-me → (optional strategists by Difficulty) → scribe flow and why strategists were skipped on a typical site plan.
2. **Discussed** whether parallel strategists help on every task → recommended scoped + red-team, not universal fan-out.
3. **User approved** implementation (“ok lets do that”).
4. **Implemented** policy and docs listed above; config validation passed.

---

*Document created for `TO REVIEW/` — filename prefix `2026-05-17` matches the date this chat session completed the strategist delegation work (session opened 2026-05-17).*
