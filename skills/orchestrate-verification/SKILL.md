---
name: orchestrate-verification
description: "Feature-mode verification: required Task fields, code-review dispatch, and per-stage gate evidence. NOT for ticket-mode work — ticket sessions self-dispatch code-review inside ticket-lifecycle."
modelTier: "fast"
roleReminder: "Load only from `architect-feature-signoff` (post-merge audit on the feature worktree). The develop-loop orchestrator does NOT load this skill for ticket work."
---

> **Scope:** This skill is **feature-mode only**. Under the develop loop (`ORCHESTRATE_DEVELOP_LOOP` unset or `1`), the develop orchestrator never loads it for ticket work. Ticket-mode per-stage code-review runs *inside* the bounded full-ticket Task (`ticket-lifecycle` skill) where each implementer self-dispatches `code-review` and reports only one terminal `READY_FOR_HUMAN_REVIEW` or `BLOCKED`.
>
> **Legacy path:** When `ORCHESTRATE_DEVELOP_LOOP=0` (legacy `github-issue-run`), the develop orchestrator still loads this skill after every implementer Task — preserve the legacy behavior below for that one release.

## Required Sequence (feature mode)

1. Grade the implementer report. `PASS` requires the expected stage/issue id, changed files including tests, RED evidence, matching GREEN evidence, explicit `assertion_delta`, complete numbered acceptance mapping, checks, no blockers, and `sandbox_id` when a sandbox was created. Otherwise use `NEEDS_RETRY` or `BLOCKED`.
2. Task `code-review` with `load: full` and the same checkout contract, `diff_base`, changed-file evidence, implementer evidence, acceptance mapping, security mode, `sandbox_id` (from the implementer's completion report), and GitHub `issue_number`/`repo` when applicable. Instruct it to fetch the GitHub issue directly and derive the full checklist from the issue body; implementer scope is evidence, not authority.
3. When `test_commands` are present, include `sandbox: preferred`, `load skill: docker-sandbox`, and `compose_test_file`; reuse the developer's sandbox via `sandbox status --id <sandbox_id>` (or Direct Docker with existing built images). Destroy after `APPROVED` or `ENV_BLOCKED`. Keep alive on `BLOCKED` for developer retry. Host verification is eligible only after explicit approval for a confirmed host-runnable project.
4. Grade code-review `APPROVED` only when every criterion has non-missing coverage, manual criteria have evidence or accepted deviation, security is resolved, and the report is complete. An empty or step-limited return is `BLOCKED`; retry once with `load: full`, then load `orchestrate-recovery`.
5. For GitHub stage mode, Task `developer` with `load: minimal` posts the `code_review_gate:` comment and atomically swaps `unverified` to `verified` before the next stage. After the last stage, include `all_stages: true`, `stages_verified`, and `verdict: APPROVED` before `state:ready-for-review`.

Never use an implementer as the code-review gate. Never advance a stage, transition an issue, or close a todo before this gate passes.