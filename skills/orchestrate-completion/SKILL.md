---
name: orchestrate-completion
description: "[LEGACY — superseded by `architect-feature-signoff` on the develop-loop path] Queue-exhaustion completion: one-shot CodeRabbit, difficulty gates, PR stabilization, and implementation-architect handoff."
modelTier: "fast"
roleReminder: "[LEGACY] Load only when `ORCHESTRATE_DEVELOP_LOOP=0` forces the legacy path. On the default develop-loop path, the develop orchestrator hands off to `architect-feature-signoff` instead."
---

> **LEGACY.** This skill is retained for `ORCHESTRATE_DEVELOP_LOOP=0` (one release window). On the default path (`ORCHESTRATE_DEVELOP_LOOP` unset or `1`), the develop orchestrator **does not load this skill** — it hands off to the **feature-architect session** running `architect-feature-signoff` once all tickets are merged into `opencode/feat-<slug>`. The new skill owns the same CodeRabbit + stabilization + handoff responsibilities and adds the `state:done` accept and merge-gate confirmation.

## Queue Exhaustion

1. Confirm every ticket/stage passed ticket-mode `code-review`. After all sub-PRs merge into the feature worktree, run feature-mode `code-review` for full regression, integration, and e2e checks. Do not run CodeRabbit for easy work; for medium/hard, Task `review` once with `execution_mode: orchestrate_coderabbit_gate`, `load: full`, implementation path, base branch, aggregate files/commits, and code-review evidence.
2. Parse the complete CodeRabbit inventory. `PASS` requires no critical/major/minor findings and resolution of trivial/info findings. On `BLOCKED`, fix findings directly in the feature worktree via developer during PR stabilization — do not create remediation tickets or child worktrees. `SKIPPED` is not completion without explicit user waiver.
3. Task `developer` with `load: minimal` to run `feature-finish-pr.sh <slug>` with checkout expectations. Preserve opt-out and protected-branch skips and report PR URL or exact skip reason.
4. For medium difficulty, Task `review` for the post-execution assessment. For hard difficulty, Task `senior-dev` in read-only `scheduled_review`, then `helper` for strategy conformance. Easy has no additional gate.
5. Enter the bounded `pr_stabilization` loop (max 3 iterations). All fixes are direct developer fixes in the feature worktree — no remediation tickets from the orchestrator. Never re-run CodeRabbit.

```
PR stabilization loop (max 3 iterations):

1. Wait for CI: Task developer load: minimal to run:
   gh pr checks <pr_url> --watch --json name,state,conclusion
   (timeout: 30 min via OC_CI_WAIT_TIMEOUT env, default 1800)
   On timeout: report CI_TIMEOUT, set stabilization_status: blocked, hand to architect.

2. Collect comments: Task developer load: minimal to run:
   gh pr view <pr_url> --json comments,reviews,statusCheckRollup,mergeable

3. Classify findings:
   - CI failures → fix-now (direct fix in feature worktree)
   - Actionable review comments (CodeRabbit/Kilo/bot/human requiring code change) → fix-now
   - Advisory/suggestion comments → defer (no fix needed)
   - Awaiting external human review → awaiting-external-review (no fix, pause)

4. If fix-now items exist:
   Task developer with execution_mode: pr_stabilization_fix, the feature worktree
   checkout contract, and the specific fix-now items. Developer fixes, writes tests
   if behavior-changing (TDD), commits with Refs: #<feature-parent-issue>, pushes.
   Loop back to step 1.

5. If CI green and no actionable comments:
   Sealed report: stabilization_status: ready_for_architect,
   feedback_cutoff_at: <ISO timestamp now>, CI evidence, comment resolutions.
   Break loop.

6. After max 3 iterations with remaining fix-now items:
   stabilization_status: blocked, hand to architect with remaining issues.
```

6. Finalize a sealed report containing PR/branch/base, CI and mergeability, comments and resolutions, CodeRabbit inventory, code-review/security/sandbox evidence, user feedback, open remediation issues, `stabilization_status`, `ci_green`, `ci_evidence`, `comment_resolutions`, and `feedback_cutoff_at` (required when `stabilization_status: ready_for_architect`).

## Mandatory Handoff

Completion output uses tables or keyed lists and names the exact `feature:<slug>` (or explicit local-plan artifact), implementation repo, PR/skip reason, completed gates, CodeRabbit status, risks, and this next action:

```text
impl architect option 4 → A (or R for a remediation session) for <feature:<slug>>; re-check PR feedback, tickets, and user acceptance before Phase 1/2.
```

Implementation architect owns final sign-off, issue acceptance, documentation, and spec feature-complete close-at-merge.
