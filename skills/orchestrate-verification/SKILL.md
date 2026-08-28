---
name: orchestrate-verification
description: "Post-implementer acceptance gate: required Task fields, report grading, verifier dispatch, and per-stage gate evidence. Not for recovery or final CodeRabbit/sign-off."
modelTier: "fast"
roleReminder: "Load immediately after every implementer Task and before any stage or issue advancement."
---

## Required Sequence

1. Grade the implementer report. `PASS` requires the expected stage/issue id, changed files including tests, RED evidence, matching GREEN evidence, explicit `assertion_delta`, complete numbered acceptance mapping, checks, and no blockers. Otherwise use `NEEDS_RETRY` or `BLOCKED`.
2. Task `verifier` with `load: full` and the same checkout contract, `diff_base`, changed-file evidence, implementer evidence, acceptance mapping, security mode, and GitHub `issue_number`/`repo` when applicable. Instruct it to fetch the GitHub issue directly and derive the full checklist from the issue body; implementer scope is evidence, not authority.
3. When `test_commands` are present, include `sandbox: preferred`, `load skill: docker-sandbox`, and `compose_test_file`; run through Sysbox `sandbox exec` when available or the same compose file with Docker Desktop locally. Host verification is eligible only after explicit approval for a confirmed host-runnable project.
4. Grade verifier `APPROVED` only when every criterion has non-missing coverage, manual criteria have evidence or accepted deviation, security is resolved, and the report is complete. An empty or step-limited return is `BLOCKED`; retry once with `load: full`, then load `orchestrate-recovery`.
5. For GitHub stage mode, Task `developer` with `load: minimal` posts the `verifier_gate:` comment and atomically swaps `unverified` to `verified` before the next stage. After the last stage, include `all_stages: true`, `stages_verified`, and `verdict: APPROVED` before `state:ready-for-review`.

Never use an implementer as the verifier. Never advance a stage, transition an issue, or close a todo before this gate passes.
