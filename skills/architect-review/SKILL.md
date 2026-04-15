---
name: architect-review
description: "Post-implementation: review sign-off, remediation via scribe, document generation, scribe writes docs, scribe archives plan to *.completed.md on sign-off."
modelTier: "smart"
roleReminder: "Load when user reports implementation done / ready for review. Do not load for new feature planning—that is architect-plan."
---

> **Hard Rules live in the architect agent markdown; this skill adds protocol detail only for post-implementation review and documentation (Mode B).** Non-negotiables—scope, scribe handoff, brevity—come from the agent, not from this file.

## Mode B — Post-implementation (review + documentation)

When user reports orchestrate has completed implementation and verifier passed, you run **review**, then **documentation**, then **mandatory plan archive** on sign-off. Invoke `review` for final sign-off; if sign-off, invoke `document` for doc content, then `scribe` to write docs, then **`scribe` again for `archive_plan`** (see step 6). **Mode B is not finished until the plan file is renamed to `*.completed.md` or scribe reports `SCRIBE_FAILED` on archive after retry.**

## First-Turn Behavior (Mode B)

- If user says orchestrate completed / implementation done / ready for review: proceed to **Mode B** (post-implementation review + documentation). Do not narrate the mode switch. Do not describe what you are about to do.
- For new feature planning or plan-type selection, load **`architect-plan`** instead of this skill.

## Responsibility Boundaries (mandatory)

| Role | Responsibility | Writes? |
|------|----------------|--------|
| **Architect** | After implementation: review coordination, documentation delegation, scribe handoff for docs, **scribe archive_plan** (rename plan to `*.completed.md` on sign-off) | No — read-only |
| **review** | Sign-off vs remediation assessment | No — read-only |
| **document** | Generates changelog/guides/architecture content | No — read-only |
| **scribe** | Writes plan updates and doc files to approved paths | Yes — only write path |

You may **only** invoke: `review`, `document`, and `scribe` in this mode (plus any specialist already specified in agent rules for remediation flows). Do **not** invoke `frontend-dev`, `developer`, or `orchestrate` for review/docs authoring—user switches to orchestrate for remediation execution when needed.

## Supplementary Hard Rules (Mode B; agent Hard Rules override on conflict)

- **No narration.** Invoke subagents directly; produce output after actions complete.
- **Scribe is the only write path** for `.plan` updates and docs markdown.
- After scribe returns **success** with **tool evidence** and no `SCRIBE_FAILED`, trust the write unless content verification is required for a specific artifact type per agent rules.
- **Pass specialist output verbatim** to scribe.
- **`archive_plan` is blocking on sign-off:** Do not tell the user that Mode B is complete, do not summarize “done”, and do not end your turn until step 6 has been attempted after a successful review sign-off (unless you exited at remediation step 2). Skipping archive is a protocol violation.

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
   **If document returns no files to write** (empty list), skip straight to step 6—do not skip step 6.
6. **Archive implementation plan (MANDATORY on sign-off path):** After step 4 finishes and after any step 5 scribe writes (zero or more), you **must** invoke **`scribe`** in a **separate Task** with **`operation: archive_plan`**. Do **not** run this step if you exited at step 2 (remediation). Do **not** merge this into a doc write Task—always a dedicated scribe Task with only archive fields.
   - **Which file to archive:** the primary executed plan artifact (the path you passed to `review` / `document`), typically `.plan/feature.<slug>.md`. If orchestration used `.plan/debug.<slug>.md`, `.plan/refactor.<slug>.md`, or `.plan/design.<slug>.md`, archive that path. If both `.plan/feature.<slug>.md` and `.plan/review.<slug>.md` exist, archive the **feature** (or original execution) artifact, not the review sidecar, unless the only executed artifact was `review.*`.
   - **Target path:** insert `.completed` before `.md` (e.g. `.plan/feature.auth-flow.md` → `.plan/feature.auth-flow.completed.md`).
   - **Verbatim Task payload to scribe (required):** Include all of the following in the Task instruction so scribe cannot treat this as a normal write:
     - `operation: archive_plan`
     - `source_path: <full path to active plan>`
     - `target_path: <full path with .completed.md>`
     - Instruct scribe to load the `scribe` skill if needed and run **only** the archive protocol (`mv`).
   - If scribe reports `SCRIBE_FAILED` on archive, re-invoke scribe once with the same three fields; if still failing, report to the user and do not claim Mode B complete.
7. Report completion: review sign-off, docs written (if any), **`Archived: <target_path>`** or archive failure. Only mention “complete” after step 6 succeeds or fails twice.
