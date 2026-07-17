---
name: improve-codebase-architecture
description: Periodic codebase architecture audit that finds shallow modules, weak seams, coupling leaks, and deepening opportunities. Use for structure/organization reviews, maintainability audits, testability audits, and optional remediation ticket preparation.
modelTier: "smart"
roleReminder: "Run as read-only audit. Prefer the Terra-backed architecture-auditor subagent. Produce an HTML report plus issue-ready candidate summaries; do not publish issues yourself."
---

# Improve Codebase Architecture

Surface architectural friction and propose **deepening opportunities**: changes that turn shallow modules into deep ones. This is a periodic audit, not a replacement for `grill-me`, PRD planning, or feature fanout.

## Operating mode

- Read-only for application source.
- Use `CONTEXT.md`, `CONTEXT-MAP.md`, and `docs/adr/` as background vocabulary and constraints, not as an interview script.
- Stop after producing the audit report and candidate summary. Parent `architect` decides whether to ask the user about remediation tickets.
- Do not invoke `to-issues`, `to-prd`, `fanout-issues`, `issue-expand`, or implementation agents.
- If the model is not `openrouter/openai/gpt-5.6-terra` or an explicitly approved fallback, report `MODEL_UNAVAILABLE: openrouter/openai/gpt-5.6-terra` to the parent before doing heavy synthesis.

## Glossary

Use these terms exactly in every suggestion. Consistent language is the point. Full definitions live in [LANGUAGE.md](LANGUAGE.md).

- **Module** — anything with an interface and an implementation.
- **Interface** — everything a caller must know to use the module correctly.
- **Implementation** — the code inside a module.
- **Depth** — leverage at the interface.
- **Deep** — large behavior behind a small interface.
- **Shallow** — interface nearly as complex as the implementation.
- **Seam** — where a module's interface lives.
- **Adapter** — a concrete thing satisfying an interface at a seam.
- **Leverage** — what callers get from depth.
- **Locality** — what maintainers get from depth.

Never substitute "component", "service", "API", "signature", "boundary", "layer", or "wrapper" when the glossary term is what you mean.

## Process

### 1. Explore

Read domain and decision context first:

- Root `CONTEXT.md`, or `CONTEXT-MAP.md` plus referenced context files when present.
- `docs/adr/` and nearby `docs/adr/` directories in the audited area.
- Project manifests, test directories, and architecture docs if present.

Use `claude-context` for codebase discovery when available. If unavailable, fall back to read-only shell/search and report `MCP_FALLBACK`.

Explore organically and note where you experience friction:

- Understanding one concept requires bouncing between many small modules.
- Modules are **shallow**: their interface is nearly as complex as their implementation.
- Extracted pure functions exist mainly for testability, but real bugs hide in caller choreography.
- Tightly coupled modules leak across their seams.
- Tests must cross past the interface to assert useful behavior.
- A module fails the **deletion test**: deleting it would make complexity vanish rather than reappear across callers.

### 2. Classify candidates

For each candidate, classify dependency shape using [DEEPENING.md](DEEPENING.md):

- `in-process`
- `local-substitutable`
- `ports & adapters`
- `mock`

Assign a stable id:

- Architecture candidates: `A1`, `A2`, ...
- If parent also passes security findings for combined reporting, leave those as `S1`, `S2`, ... from the security review.

Recommendation strength is one of:

- `Strong`
- `Worth exploring`
- `Speculative`

Only include candidates with real friction. Do not pad the report.

### 3. Produce the HTML report

Render a self-contained HTML report following [HTML-REPORT.md](HTML-REPORT.md). Each candidate card must include:

- Candidate id and title.
- Files/modules involved.
- Problem: one sentence naming the friction.
- Solution: one sentence naming the deepening.
- Benefits in terms of **locality**, **leverage**, and test surface.
- Before/after visualisation.
- Dependency category.
- Recommendation strength.
- ADR conflict callout when relevant.

Prefer `docs/architecture/reviews/architecture-audit-<YYYY-MM-DD>.html` as the target path. If that path cannot be written by `scribe` because the repo lacks the directory or rejects docs writes, fall back to an OS temp HTML file and return its absolute path.

When this skill is running in `architecture-auditor`, either:

1. Task `scribe` with the complete HTML body and target path, then return the written path; or
2. Return the complete HTML body to parent `architect` for scribe handoff when `scribe` is not available.

After writing, parent `architect` opens the report for the user.

### 4. Return an issue-ready summary

Return a concise markdown summary to parent `architect`:

```markdown
## Architecture audit
Report: <path or temp path>

| ID | Strength | Dependency | Files | Summary | AFK/HITL |
|----|----------|------------|-------|---------|----------|
| A1 | Strong | in-process | `src/...` | ... | AFK |

## Top recommendation
<candidate id + one sentence>

## Candidate details for to-issues
### A1: <title>
- Files: ...
- Current friction: ...
- Deepening: ...
- Acceptance checks:
  - ...
- Characterization tests needed:
  - ...
- Risk: Low/Medium/High
- AFK/HITL: ...
```

These details must be sufficient for `to-issues` to create `opencode-task-yaml` issue bodies if the user chooses remediation. Do not create the issues yourself.

### 5. Optional drill-down

Only if the user explicitly picks a candidate to explore, enter a focused design conversation for that candidate.

- Clarify constraints and dependencies.
- Use [INTERFACE-DESIGN.md](INTERFACE-DESIGN.md) when the user wants alternative interfaces.
- Persist `CONTEXT.md` or ADR updates only when a new domain term or load-bearing rejection needs to be recorded. Parent `architect`/`scribe` handles writes using `skills/grill-me/CONTEXT-FORMAT.md` and `skills/grill-me/ADR-FORMAT.md` as format references.

Do not turn drill-down into feature planning unless the user explicitly asks for remediation tickets.
