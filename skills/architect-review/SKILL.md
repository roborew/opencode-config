---
name: architect-review
description: "Post-implementation: review sign-off, remediation via scribe, document generation, scribe writes docs."
modelTier: "smart"
roleReminder: "Load when user reports implementation done / ready for review. Do not load for new feature planning—that is architect-plan."
---

> **Hard Rules live in the architect agent markdown; this skill adds protocol detail only for post-implementation review and documentation (Mode B).** Non-negotiables—scope, scribe handoff, brevity—come from the agent, not from this file.

## Mode B — Post-implementation (review + documentation)

When user reports orchestrate has completed implementation and verifier passed, you run **review**, then **documentation**. Invoke `review` for final sign-off; if sign-off, invoke `document` for doc content, then `scribe` to write docs.

## First-Turn Behavior (Mode B)

- If user says orchestrate completed / implementation done / ready for review: proceed to **Mode B** (post-implementation review + documentation). Do not narrate the mode switch. Do not describe what you are about to do.
- For new feature planning or plan-type selection, load **`architect-plan`** instead of this skill.

## Responsibility Boundaries (mandatory)

| Role | Responsibility | Writes? |
|------|----------------|--------|
| **Architect** | After implementation: review coordination, documentation delegation, scribe handoff for docs | No — read-only |
| **review** | Sign-off vs remediation assessment | No — read-only |
| **document** | Generates changelog/guides/architecture content | No — read-only |
| **scribe** | Writes plan updates and doc files to approved paths | Yes — only write path |

You may **only** invoke: `review`, `document`, and `scribe` in this mode (plus any specialist already specified in agent rules for remediation flows). Do **not** invoke `frontend-dev`, `developer`, or `orchestrate` for review/docs authoring—user switches to orchestrate for remediation execution when needed.

## Supplementary Hard Rules (Mode B; agent Hard Rules override on conflict)

- **No narration.** Invoke subagents directly; produce output after actions complete.
- **Scribe is the only write path** for `.plan` updates and docs markdown.
- After scribe returns **success** with **tool evidence** and no `SCRIBE_FAILED`, trust the write unless content verification is required for a specific artifact type per agent rules.
- **Pass specialist output verbatim** to scribe.

**Brevity:** Concise headings and bullets; deltas only when repeating status to the user.

## Completion Flow — Mode B (post-implementation review + documentation)

1. **Review:** Invoke `review` subagent with artifact path and completion context. Review returns either sign-off or remediation tasks.
2. **If remediation needed:** Invoke `scribe` to write `.plan/review.<slug>.md` with the review plan. Prompt user: "Switch to `orchestrate` to apply fixes."
3. **If sign-off:** Proceed to **Document** (mandatory task after review).
4. **Document:** Invoke `document` with artifact path and completion context. Document returns changelog, guides, and architecture doc content.
5. **Write docs:** For each doc in document output, invoke `scribe` with `target_path` and `content` to write:
   - `docs/changelog/<date>-<slug>.md`
   - `docs/guides/<slug>.md`
   - `docs/architecture/<slug>.md`
   - When needed for onboarding or env setup: `README.md` and/or `.env.example` at the project root (or package subdirectory), same `target_path` + verbatim `content` contract as other scribe writes.
   After each scribe call: if success with tool evidence and no `SCRIBE_FAILED`, trust the write; otherwise re-invoke scribe once. If scribe reports `SCRIBE_FAILED`, re-invoke once.
6. Report completion: review sign-off and docs written.
