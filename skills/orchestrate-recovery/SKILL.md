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

**Precise mid-stage escalation path:**
- developer/frontend-dev/ux-dev returns `blocker_code: STAGE_STUCK`, a repeated functional failure occurs, or verifier identifies a criterion failure that cannot be resolved by a narrow retry;
- orchestrate first invokes `helper` to produce the minimal recovery strategy;
- orchestrate escalates to senior-dev only when the operator explicitly requests it and confirms the escalation;
- senior-dev receives the stage contract, checkout contract, diff base, failure output, verifier evidence, helper recovery strategy, and retry history;
- senior-dev may edit only the minimal unblocker, then returns `HANDOFF_TO_DEVELOPER` with changed files, commands, and remaining work; developer resumes the stage and verifier runs again.

**Procedure:**
1. **Stop the current process.** Do not invoke senior-dev yet.
2. First invoke `helper` to produce the minimal recovery strategy.
3. **Ask the user to confirm:** "Senior-dev is available for escalation. Do you want to use senior-dev to diagnose and fix this blocker? Reply yes to confirm."
4. **Wait for explicit user confirmation.** Do not proceed until the user confirms (e.g. "yes", "confirm", "go ahead").
5. After confirmation, invoke `senior-dev` via Task with `execution_mode: escalation_fix`, artifact path, stage_id, failure evidence (blocker report), helper recovery strategy, and retry history.
6. Senior-dev diagnoses, implements fix, and reports with `HANDOFF_TO_DEVELOPER` when blocker is fixed.
7. When senior-dev reports `HANDOFF_TO_DEVELOPER`, grade the report, then **resume with developer** for remaining stage work. Do not re-invoke senior-dev for the same stage.
8. Developer resumes the stage and verifier runs again.

### Verifier-driven escalation (bounded to high-risk defects)

A third optional escalation route for `verifier` findings:
- Trigger only when verifier finds a cross-cutting correctness/security/design concern that cannot be assessed from the stage contract, or when the same criterion fails two implementation-verification cycles;
- Require the same explicit operator confirmation as mid-stage escalation;
- Do not use it for ordinary test failures, missing evidence, lint issues, or environment blockers.

**Do not** use this confirmation flow for the **hard** Difficulty scheduled post-implementation review (see **`orchestrate-execution`** Difficulty-based completion gates).

Senior-dev is **not** auto-invoked for mid-stage work without operator request + user confirmation—except for the **hard** completion gate after all stages pass verifier.

## Environment Blocker Policy

If a subagent reports `ENV_BLOCKED`:

1. Stop current stage immediately.
2. **Bootstrap (no artifact yet):** If **worktree-env** or **`preflight`** reports Blocked **after** the repair-first flow in **`orchestrate-execution`** has completed (including one auto-retry where applicable), do **not** invoke `helper`/`scribe` for artifact amendments. Report **one** `recommended_env_fix` — no multi-option menus. Do **not** re-Task **`worktree-env`** if it already returned `worktree_env: ok` with canonical evidence unless canonical verification contradicts that report. Re-run the full env gate only when the user confirms remediation or asks to rerun preflight (clear `worktree_env_checked` / `preflight_repair_attempted`).
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

## Provider Fallback Dispatch (additional recovery path)

Provider fallback is layered **on top of** the recovery paths above. It is **not** a replacement for helper / senior-dev escalation and **does not** reduce operator-confirmation requirements.

### When a fallback is appropriate

Dispatch `kilo-fallback` (then `openrouter-fallback`) only after the recovery paths above have run for the **same** bounded child Task and the failure pattern is not recoverable inside the original role. Typical cases:

- Transient provider failure (`timeout`, `429`, `5xx`) on the original role's provider, with the one same-agent retry already exhausted.
- Logic-class failure (`STAGE_STUCK`, loop, unresolved blocker, verifier strategy failure) where the helper amendment was applied and the same role still cannot finish the Task on the original provider.

A fallback is **not** appropriate for primary-agent work, for fresh planning that has not been delegated yet, or when the helper path was skipped. Senior-dev remains operator-confirmed (see **Senior-Dev Escalation** above); the fallback does not bypass that confirmation.

### Building `fallback_context`

When dispatching a fallback, build a complete `fallback_context` (the child report's contract, not vibes):

- `original_agent` — the child whose Task failed (never a primary).
- `original_skill` — the exact skill name to load; do **not** infer from transcript.
- `task_contract` — the verbatim original Task prompt (or faithful restatement) with all required fields (checkout, branch policy, stage fields for implement/verify tasks, sandbox fields when applicable, etc.).
- `failure_evidence` — concise failure summary (error class, retry count, unfinished work).
- `attempt_history` — providers and load levels already tried for this Task.
- `recovery_strategy` (when present) — short summary of the helper / scribe amendment applied.
- `requested_provider` — operator's selection when explicit (`use Kilo fallback` / `use OpenRouter fallback`); else default to the chain.

Only one attempt per provider per bounded Task. Track `attempted_providers` per Task; do not retry Kilo twice or loop between providers.

### Grading fallback reports

A fallback completion report is graded with the **same `report_grade: PASS | NEEDS_RETRY | BLOCKED` rubric** as the original role's report. The `fallback_used` envelope (original role, skill, fallback agent, provider, model, attempt number, recovered_from) is metadata only — never lowers the bar or excuses missing evidence. Provider-level failure envelopes (`fallback_used.provider_failure`) are `BLOCKED`, not `PASS`.

### Exhaustion (`FALLBACK_EXHAUSTED`)

After both `kilo-fallback` and `openrouter-fallback` fail for the same Task, halt the stage/issue with `FALLBACK_EXHAUSTED` and ask the operator how to proceed (retry with fresh context, accept partial work, abandon, or relax a constraint). Do not invent a third provider.

## Manual Handoff Recovery (when Task does not return)

If the user reports that a subagent (developer, frontend-dev, ux-dev, scribe, verifier, helper, senior-dev) completed and produced a report but the Task did not return control:

1. Ask the user to paste the completion report here.
2. Grade the report using the Child Report Grading Gate from **`orchestrate-execution`** (PASS/NEEDS_RETRY/BLOCKED).
3. If PASS, proceed to the next stage (or verifier if stage complete). Do not re-invoke the same subagent for the same stage.
4. If NEEDS_RETRY or BLOCKED, follow the normal decision policy.

Do not ask the user to message the subagent again—the subagent has already completed. Accept the pasted report and continue.
