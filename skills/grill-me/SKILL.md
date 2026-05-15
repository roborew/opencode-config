---
name: grill-me
description: Grilling session (grill-with-docs) that challenges your plan against the existing domain model, sharpens terminology, and updates CONTEXT.md and ADRs as decisions crystallise — persisted via scribe. Architect Mode A loads this after plan type + first substantive requirements and before architect-plan. Also when the user wants stress-test against project language, documented decisions, or says "grill me".
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time, waiting for feedback on each question before continuing.

If a question can be answered by exploring the codebase, explore the codebase instead.

## Domain awareness

During codebase exploration, also look for existing documentation:

### File structure

Most repos have a single context:

```
/
├── CONTEXT.md
├── docs/
│   └── adr/
│       ├── 0001-event-sourced-orders.md
│       └── 0002-postgres-for-write-model.md
└── src/
```

If a `CONTEXT-MAP.md` exists at the root, the repo has multiple contexts. The map points to where each one lives:

```
/
├── CONTEXT-MAP.md
├── docs/
│   └── adr/                          ← system-wide decisions
├── src/
│   ├── ordering/
│   │   ├── CONTEXT.md
│   │   └── docs/adr/                 ← context-specific decisions
│   └── billing/
│       ├── CONTEXT.md
│       └── docs/adr/
```

**Lazy creation (OpenCode):** Create `CONTEXT.md`, `CONTEXT-MAP.md`, or `docs/adr/` only when you have substantive content to persist. Do **not** create empty stubs. **You do not write these files yourself** — the Architect agent is read-only. After each resolved term or ADR body is ready, **Task `scribe`** with explicit `target_path` and full file `content` (and `mode: create` or `update`). Scribe is the only write path.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `CONTEXT.md`, call it out immediately. "Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account' — do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible — which is right?"

### Persist CONTEXT.md via scribe (do not write inline yourself)

When a term is resolved, produce the **complete updated** `CONTEXT.md` body for the active context (root `CONTEXT.md` or the path indicated by `CONTEXT-MAP.md`) **immediately** — do not batch many unresolved terms into one silent update. Use the format in [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).

Then **invoke `scribe` via Task** with:

- `target_path`: the context file (e.g. `CONTEXT.md` or `src/ordering/CONTEXT.md`)
- `content`: full markdown file body
- `mode`: `create` or `update`

`CONTEXT.md` should be totally devoid of implementation details. Do not treat `CONTEXT.md` as a spec, a scratch pad, or a repository for implementation decisions. It is a glossary and nothing else.

### Offer ADRs sparingly

Only offer to create an ADR when all three are true:

1. **Hard to reverse** — the cost of changing your mind later is meaningful
2. **Surprising without context** — a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons

If any of the three is missing, skip the ADR. Use the format in [ADR-FORMAT.md](./ADR-FORMAT.md).

When an ADR is warranted, determine the next filename under `docs/adr/` (or context-specific `docs/adr/` per CONTEXT-MAP) per ADR-FORMAT numbering, then **Task `scribe`** with `target_path` (e.g. `docs/adr/0003-choose-postgres.md`) and full `content`.
