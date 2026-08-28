---
name: orchestrate-completion
description: "Queue-exhaustion completion: one-shot CodeRabbit, difficulty gates, PR stabilization, and implementation-architect handoff. Not for per-stage verification or issue claiming."
modelTier: "fast"
roleReminder: "Load only after the queue reports exhausted and every ticket has code-review approval."
---

## Queue Exhaustion

1. Confirm every ticket/stage passed ticket-mode `code-review`. After all sub-PRs merge into the feature worktree, run feature-mode `code-review` for full regression, integration, and e2e checks. Do not run CodeRabbit for easy work; for medium/hard, Task `review` once with `execution_mode: orchestrate_coderabbit_gate`, `load: full`, implementation path, base branch, aggregate files/commits, and code-review evidence.
2. Parse the complete CodeRabbit inventory. `PASS` requires no critical/major/minor findings and resolution of trivial/info findings. On `BLOCKED`, create remediation tickets and child worktrees; never reopen merged tickets. `SKIPPED` is not completion without explicit user waiver.
3. Task `developer` with `load: minimal` to run `feature-finish-pr.sh <slug>` with checkout expectations. Preserve opt-out and protected-branch skips and report PR URL or exact skip reason.
4. For medium difficulty, Task `review` for the post-execution assessment. For hard difficulty, Task `senior-dev` in read-only `scheduled_review`, then `helper` for strategy conformance. Easy has no additional gate.
5. Enter bounded `pr_stabilization`: collect current checks/comments and user feedback, classify findings as `fix-now`, `defer`, `not-applicable`, or `awaiting-external-review`, and execute only clear fix-now items through new remediation tickets and child worktrees. Never re-run CodeRabbit.
6. Finalize a sealed report containing PR/branch/base, CI and mergeability, comments and resolutions, CodeRabbit inventory, verifier/security/sandbox evidence, user feedback, open remediation issues, `stabilization_status`, and `feedback_cutoff_at`.

## Mandatory Handoff

Completion output uses tables or keyed lists and names the exact `feature:<slug>` (or explicit local-plan artifact), implementation repo, PR/skip reason, completed gates, CodeRabbit status, risks, and this next action:

```text
impl architect option 4 → A (or R for a remediation session) for <feature:<slug>>; re-check PR feedback, tickets, and user acceptance before Phase 1/2.
```

Implementation architect owns final sign-off, issue acceptance, documentation, and spec feature-complete close-at-merge.
