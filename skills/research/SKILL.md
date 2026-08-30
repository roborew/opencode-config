---
name: research
description: "Optional pre-planning cache: write .research/<slug>.md (question, sources, findings, implications, stale-by). grill-me and to-prd load if present."
modelTier: fast
roleReminder: "Invoke scribe to write .research/<slug>.md only — not a substitute for grill-me or PRD."
---

# Research

Optional **pre-planning research cache** before **`grill-me`** or **`to-prd`**.

## When

- User asks to research a topic, spike, or external API before committing to a PRD.
- Architect loads this skill for a bounded question — not for full feature delivery.

## Workflow

1. Define **research question** and **stale-by** date (default: 30 days).
2. Gather sources (docs MCP, context7, web when allowed).
3. Task **`scribe`** to write **`.research/<slug>.md`** using `skills/research/templates/research.md` structure:
   - Question
   - Sources (with links)
   - Findings
   - Implications for product/engineering
   - Stale-by date
4. Tell user: cite this file in PRD **Linked artifacts**; re-run research if stale.

## Hard rules

- **Scribe** is the only writer for `.research/*.md`.
- Do not invoke **`to-prd`**, **`fanout`**, or **`orchestrate`** from this skill.
- GitHub issues are the source of truth; this skill produces a pre-planning cache only.
