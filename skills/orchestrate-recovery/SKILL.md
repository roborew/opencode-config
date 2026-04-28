---
name: orchestrate-recovery
description: "Failure paths: helper triggers, env blockers, loops, senior-dev escalation, review remediation, manual Task handoff."
modelTier: "fast"
roleReminder: "Load when blocked, looping, env mismatch, or user pastes a stuck subagent report—not for happy-path stage execution."
---

> **Hard Rules live in the orchestrate agent markdown; this skill adds protocol detail only for recovery and escalation.** Non-negotiables come from the agent, not from this file.

## When to use this skill

Load **`orchestrate-recovery`** when you are handling **helper**-driven recovery, **environment blockers**, **loop/stall**, **senior-dev escalation** (operator-triggered), **review remediation** artifact flow, or **manual handoff** (user pasted a report). For normal stage progression, grading, and completion gates, use **`orchestrate-execution`** (you may load this skill **after** execution skill in the same session when a failure path appears).

## Helper Trigger Conditions (enforced)

Invoke `helper` immediately when any occur:

- same stage fails verification twice
- unresolved blocker reported by execution subagent
- verifier reports failed criteria requiring strategy change
- developer reports `blocker_code: ENV_BLOCKED`
- developer/frontend-dev/ux-dev reports `blocker_code: STAGE_STUCK`
- child report repetition indicates loop/stall

Do not advance stages until helper updates are applied via `scribe`.

## Senior-Dev Escalation (operator-triggered, user confirmation required)

**During stage execution**, when developer reports `STAGE_STUCK` or repeated failures and the **operator asks to escalate**:

1. **Stop the current process.** Do not invoke senior-dev yet.
2. **Ask the user to confirm:** "Senior-dev (Codex) is available for escalation. Do you want to use senior-dev to diagnose and fix this blocker? Reply yes to confirm."
3. **Wait for explicit user confirmation.** Do not proceed until the user confirms (e.g. "yes", "confirm", "go ahead").
4. After confirmation, invoke `senior-dev` via Task with artifact path, stage_id, and failure evidence (blocker report).
5. Senior-dev diagnoses, implements fix, and reports with `handoff_to_developer: true` when blocker is fixed.
6. When senior-dev reports `HANDOFF_TO_DEVELOPER`, grade the report, then **resume with developer** for remaining stage work. Do not re-invoke senior-dev for the same stage.

**Do not** use this confirmation flow for the **hard** Difficulty scheduled post-implementation review (see **`orchestrate-execution`** Difficulty-based completion gates).

Senior-dev is **not** auto-invoked for mid-stage work without operator request + user confirmation—except for the **hard** completion gate after all stages pass verifier.

## Environment Blocker Policy

If a subagent reports `ENV_BLOCKED`:

1. Stop current stage immediately.
2. **Bootstrap (no artifact yet):** If **worktree-env** or **developer** preflight-only reports Blocked, do **not** invoke `helper`/`scribe` for artifact amendments—ask the user to remediate (see `skills/worktree-env/SKILL.md` for symlink issues), then re-Task **`worktree-env`** (if applicable) and **`developer`** (preflight) when the user confirms.
3. **Mid-stage execution:** Invoke `helper` to produce a minimal recovery/update strategy; use `scribe` to amend artifact `IterationNotes` and next-step tasks.
4. Ask user for explicit environment remediation confirmation before retry.

Do not let subagents loop on runtime/toolchain commands when environment is mismatched.

## Review Artifact Recovery (when architect returns remediation)

When you receive a review artifact (`.plan/review.<slug>.md`) from architect with remediation tasks:

- on verifier fail, invoke `helper`
- helper returns minimal amendment strategy
- dispatch `scribe` to update existing `.plan/review.<slug>.md`
- rerun developer stage and verifier
- when verifier passes, prompt user: "Switch to architect for final sign-off and documentation."

## Loop Detection and Halt (mandatory)

If you receive the same or near-identical report from a child (scribe, developer, frontend-dev, ux-dev, verifier) **2 or more times**:

1. Treat the child as `BLOCKED` (loop/stall), not `PASS`.
2. Invoke `helper` immediately with loop evidence and request minimal recovery strategy.
3. Dispatch `scribe` to record the recovery amendment in the same artifact.
4. Halt stage advancement and ask user confirmation if environment/remediation action is required.
5. Do not re-invoke the same child for that stage until helper amendment is applied.

When scribe returns `path`, `operation`, `summary`, and **tool evidence** of a successful write with no `SCRIBE_FAILED`, **trust the write**—do not re-read or list the directory by default. If the file is missing, evidence is absent, or scribe reports `SCRIBE_FAILED: file not written`, re-invoke scribe once with the same content and path. If still missing, treat as `BLOCKED` and invoke helper.

When developer repeats the same intent (e.g. "Let me create X") without new evidence, treat as stuck: halt, report to user, and do not re-invoke developer for the same stage without corrective feedback.
When developer emits repeated completion text without new evidence (for example repeating "tests pass" lines), classify as `BLOCKED` with reason `LOOP_DETECTED` and trigger helper path.

## Manual Handoff Recovery (when Task does not return)

If the user reports that a subagent (developer, frontend-dev, ux-dev, scribe, verifier, helper, senior-dev) completed and produced a report but the Task did not return control:

1. Ask the user to paste the completion report here.
2. Grade the report using the Child Report Grading Gate from **`orchestrate-execution`** (PASS/NEEDS_RETRY/BLOCKED).
3. If PASS, proceed to the next stage (or verifier if stage complete). Do not re-invoke the same subagent for the same stage.
4. If NEEDS_RETRY or BLOCKED, follow the normal decision policy.

Do not ask the user to message the subagent again—the subagent has already completed. Accept the pasted report and continue.
