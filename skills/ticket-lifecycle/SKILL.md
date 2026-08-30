---
name: ticket-lifecycle
description: "Bounded full-ticket execution + self-stabilization contract for `execution_mode: github_issue_full`. Loaded inside the ticket session (developer/frontend-dev/ux-dev) so the ticket owns every stage, sub-PR, and PR stabilization loop end-to-end and returns exactly one terminal report."
modelTier: "fast"
roleReminder: "Load only when the parent dispatches a Task with `execution_mode: github_issue_full`. The post-completion guard at the bottom of developer/frontend-dev/ux-dev skills must NOT fire between stages — only after the terminal report."
---

> You are operating inside a **bounded full-ticket Task** dispatched by the develop orchestrator (under `orchestrate-develop-loop`). The orchestrator is **not** present between stages — you own every stage, every `code-review` per stage, the sub-PR, and the PR stabilization loop. You return exactly **one** terminal report and stop.

## Hard rules

1. **One terminal report.** Either `READY_FOR_HUMAN_REVIEW` (sub-PR URL + green CI + comment-clean) or `BLOCKED` (reason + partial evidence). Do not return success after each stage; do not hand off mid-ticket.
2. **Silent preflight.** Run `worktree-env` + `preflight` once, silently. One auto-repair pass (per `skills/preflight/SKILL.md` repair table). Only on `Status: Blocked` after the single repair pass do you surface to the parent.
3. **Stay on `opencode/ticket-<issue>-<slug>-<abbrev>`.** Do not switch branches, do not push to `develop` or `opencode/feat-<slug>` directly — only to your own ticket branch.
4. **Never delete remote branches.** `git push origin --delete` is owned exclusively by the develop orchestrator (delegated to `developer`). You push your ticket branch only.
5. **One sub-PR per ticket.** Sub-PR is `head=opencode/ticket-<issue>-<slug>-<abbrev>`, `base=opencode/feat-<slug>`. Do not open additional PRs.
6. **Post-completion guard override.** The implementer skills' bottom-of-file post-completion guard ("Task complete. Switch to the `orchestrate` agent…") does **not** fire between stages. It only fires after the terminal report. Treat stage completions as internal milestones, not as terminal reports.
7. **Context discipline.** Every ~10 tool iterations, compact state to 3 bullets (current stage, files touched, blockers). Discard old RED/GREEN raw outputs once `code-review` APPROVES the stage; keep only concise gate summaries.
8. **Stabilization is bounded.** PR stabilization loop runs **at most 3 iterations**. On exhaustion, return `BLOCKED: STABILIZATION_EXHAUSTED` with the remaining fix-now items.
9. **Cross-ticket review comments are not yours to fix.** If `pr-stabilize-watch.sh` returns comments whose fix would touch files in another ticket's branch, return `BLOCKED: CROSS_TICKET_REVIEW` so the develop orchestrator hands off to `architect-feature-signoff` early.
10. **Issue state transitions** (`state:in-progress` on entry, `state:ready-for-review` when the sub-PR opens) are yours; use `issue-state-transition.sh` via a delegated `developer` Task.

## Required inputs (from the dispatch)

The develop orchestrator passes:

```text
execution_mode:        github_issue_full
load:                  full
impl_repo_path:        <absolute git root>
expected_branch:       opencode/ticket-<issue>-<slug>-<abbrev>
is_linked_worktree:    true
main_checkout_root:    <root when known>
branch_policy:         do not create, switch, checkout, or rename branches
worktree_directory:    <abs ticket worktree path>
feature_branch:        opencode/feat-<slug>
abbrev:                <derived title slug, may end in -2/-3>
issue_number:          <int>
repo:                  OWNER/REPO
opencode_meta:         { task_id, owner, acceptance, test_commands, stages[], commit_message, ... }
auto_spawn_consent:    true|false
```

If `execution_mode` is missing, you are on the legacy single-stage path — load your agent Hard Rules and behave like the legacy `github-issue-run` flow.

## Procedure

### 1. Silent preflight

```bash
# delegated developer with load: minimal
git -C "<worktree_directory>" rev-parse --is-inside-work-tree  # expect true
git -C "<worktree_directory>" rev-parse --abbrev-ref HEAD      # expect <expected_branch>

# If not on the expected branch -> BLOCKED: CHECKOUT_CONTRACT_FAILED
```

Then run **`worktree-env`** with `load: full` and **`preflight`** with `load: full`, repair-first, **silently**. Surface only if preflight reports `Status: Blocked` after one repair pass; otherwise proceed to step 2 without prompting.

### 2. Loop every `opencode_meta.stages[]` entry

For each `stage` in `opencode_meta.stages` (in order):

1. **RED** — dispatch `test-writer` (or implementer RED for non-test stages) with the stage scope and capture `red_phase`.
2. **GREEN** — execute the stage as `Owner` (developer | frontend-dev | ux-dev) per `stage.owner`. Capture `green_phase` and `assertion_delta`.
3. **`code-review` (ticket mode)** — dispatch `code-review` with `load: full`, the stage's `diff_base`, `files_changed`, `red_phase` + `green_phase` evidence, and the issue's acceptance mapping.
   - On `APPROVED` → stage done. Compact context, retain only gate summary.
   - On `NEEDS_CHANGES` → fix in-worktree (TDD), re-run code-review (max 2 stage retries per `skills/developer/SKILL.md` retry budget).
   - On `BLOCKED` → return `BLOCKED` from the ticket (cross-cutting blocker).
4. After the final stage → run `StageAcceptanceChecks` end-to-end. Commit any remaining stage outputs with `Refs: #<issue_number>`.

### 3. Open the sub-PR

1. Push your branch: `git push -u origin <expected_branch>` (delegated developer).
2. Open the sub-PR via `gh pr create --base opencode/feat-<slug> --head <expected_branch> --title "feat(<slug>): ticket <issue> — <title>" --body <auto-body>` (delegated developer).
3. Post the `code_review_gate:` comment with `all_stages: true`, `verdict: APPROVED`, and add the `verified` label.
4. `state:ready-for-review` on the issue via `issue-state-transition.sh`.

### 4. PR stabilization loop (max 3 iterations)

For `iter` in 1..3:

```text
report = delegated developer load: minimal \
  bash <OC>/skills/github-issue-run/lib/pr-stabilize-watch.sh <pr_url>

switch report.classify:
  case "ready":
    break loop
  case "awaiting-human":
    # comments explicitly marked WIP / hold / do not merge — exit stabilization,
    # treat as READY_FOR_HUMAN_REVIEW with note
    break loop
  case "fix-now":
    for each fix-now item in (report.ci failing checks, report.comments, report.reviews):
      if item spans another ticket's branch files:
        return BLOCKED: CROSS_TICKET_REVIEW { item, evidence }
      fix in-worktree with TDD (RED→GREEN, behavior changes only),
      commit "Refs: #<issue_number>", push branch
    loop back to next iter
```

### 5. Terminal report

Exactly one of:

```yaml
READY_FOR_HUMAN_REVIEW:
  issue_number: <n>
  pr_url:      <url>
  ci_state:    pass|pending
  evidence:    <pr-stabilize-watch evidence line>
  comment_resolutions: [{ author, classification, action }]
  stages_completed:   <count>
  awaiting_human_notes: <optional list of WIP/hold comments>
  next_action_for_parent: "merge sub-PR into opencode/feat-<slug> on human approval, then worktree + remote-branch cleanup"

BLOCKED:
  blocker_code: ENV_BLOCKED | STAGE_STUCK | STABILIZATION_EXHAUSTED | CROSS_TICKET_REVIEW | CHECKOUT_CONTRACT_FAILED | SKILL_UNAVAILABLE
  reason:       <one-line>
  partial_evidence:
    stages_completed:  <count>
    last_ci_state:     pass|fail|pending
    last_pr_url:       <url if open>
    failing_checks:    [<names>]
    fix_now_outstanding: <count>
  recommended_helper_request: <one concrete request>
```

Emit the terminal report and stop. The post-completion guard now fires (per implementer Hard Rules) — any subsequent user message is answered with: "Task complete. Switch to the `orchestrate` agent to continue."

## Anti-loop

- Do not emit the same verbal statement twice. Move after the first intent statement.
- Do not re-announce file writes or commands.
- After a stage's `code-review` APPROVED, compact: discard raw RED/GREEN outputs; retain only the verdict + commit ref.

## See also

- `skills/developer/SKILL.md`, `skills/frontend-dev/SKILL.md`, `skills/ux-dev/SKILL.md` — implementer Hard Rules; only the bottom post-completion guard is overridden by this skill.
- `skills/code-review/SKILL.md` — ticket mode (no full regression / no CodeRabbit).
- `skills/preflight/SKILL.md` — repair pass and output schema.
- `skills/github-issue-run/lib/pr-stabilize-watch.sh` — CI-watch + comment classifier.
- `skills/orchestrate-develop-loop/SKILL.md` — the parent orchestrator.