---
name: architect-feature-signoff
description: "Feature-architect's bounded job after all tickets merge into opencode/feat-<slug>: full audit, feature-mode code-review, one-shot CodeRabbit (medium/hard), PR stabilization, `feature-finish-pr.sh`, accept (state:done), merge with user confirmation (merge gate), and Phase R remediation if acceptance is unmet."
modelTier: "fast"
roleReminder: "Load only in the **feature-architect session** that the develop orchestrator hands off to. Lives inside the feature worktree (`opencode/feat-<slug>`). The develop orchestrator must not load this skill."
---

> **Owns the feature-mode audit + sign-off.** The develop orchestrator emits `HANDOFF_TO_FEATURE_ARCHITECT` once all tickets merge into `opencode/feat-<slug>`; the user (or spec session) starts a new **architect** session inside the feature worktree, which loads this skill.

## Hard rules

1. You are running inside the **feature worktree** at `opencode/feat-<slug>`. Stay on that branch; do not switch to `develop` or any ticket branch.
2. Never write or edit application code or call `worktree-manager` — this session does not own the worktree lifecycle. The develop orchestrator resumes after merge and tears down the worktree.
3. `state:done` is yours to set (Phase 1 accept). Issues stay **open**; close-at-merge is owned by spec `feature-complete`.
4. The merge gate is a **human confirmation** — never auto-merge the feature PR. Offer human merge or agent-merge-on-behalf, then wait.
5. Use `scripts/feature-finish-pr.sh <slug>` to open the feature PR. Do not run it until the full audit + CodeRabbit + stabilization is green.
6. Phase R remediation: only when something in the merged tickets is **unmet against acceptance criteria**. Cosmetic / refactor / nit items are direct fixes in the feature worktree, not remediation tickets.

## Procedure

### 1. Full audit

1. Confirm `opencode/feat-<slug>` contains every merged ticket (compare `git log opencode/develop..HEAD --oneline` against the develop-orchestrator handoff table).
2. Replay every ticket's acceptance criteria against the merged code (`gh issue view <n> --repo <repo> --json body` + the diff in this worktree).
3. Pull the per-stage `code_review_gate:` comments from each ticket; verify `all_stages: true` + `verdict: APPROVED` + `verified` label for all.
4. Capture evidence: `gh pr list --state merged --base opencode/feat-<slug> --json number,url,title` (sub-PRs), `git diff opencode/develop...HEAD --stat`.

On any unmet acceptance → Phase R (step 6). Otherwise continue.

### 2. Feature-mode code-review

Task `code-review` with `load: full`, `execution_mode: feature_review` (or per `skills/code-review/SKILL.md` feature-mode). Pass the full diff vs `develop`, the rolled-up `issue_rollup`, the `code_review_gate:` summaries, and the security review path. Expect `APPROVED` with full regression / integration / e2e evidence. The feature-mode grading gate (`APPROVED` only when every acceptance criterion has non-missing coverage, manual criteria have evidence or accepted deviation, security resolved; empty/malformed/step-limited report = `BLOCKED`, retry once with `load: full`) is documented in `skills/code-review/SKILL.md` feature mode.

### 3. CodeRabbit (one-shot, medium/hard only)

For difficulty `easy` → skip CodeRabbit. The "skip CodeRabbit for easy" invariant lives here: CodeRabbit is a single feature/artifact-wide gate after the final code-review approval, never per stage or ticket, and never for `easy` work.
For `medium` or `hard` → Task `review` once with `execution_mode: orchestrate_coderabbit_gate`, `load: full`, the feature worktree path, base branch `develop`, aggregate files/commits, and code-review evidence. Parse the inventory: `PASS` requires no critical/major/minor findings and trivial/info resolved. On `BLOCKED`, fix findings **directly in this feature worktree** (do not create remediation tickets for CodeRabbit fixes) — the PR-stabilization loop below owns the bounded fix flow.

### 4. PR stabilization loop (max 3 iterations)

```text
PR stabilization loop (max 3 iterations):

1. Wait for CI: Task developer load: minimal to run:
   gh pr checks <pr_url> --watch --json name,state,conclusion
   (timeout: 30 min via OC_CI_WAIT_TIMEOUT env, default 1800)
   On timeout: report CI_TIMEOUT, set stabilization_status: blocked, pause for human.

2. Collect comments: Task developer load: minimal to run:
   gh pr view <pr_url> --json comments,reviews,statusCheckRollup,mergeable

3. Classify findings:
   - CI failures → fix-now (direct fix in feature worktree)
   - Actionable review comments → fix-now
   - Advisory/suggestion comments → defer (no fix needed)
   - Awaiting external human review → awaiting-external-review (no fix, pause)

4. If fix-now items exist:
   Task developer with execution_mode: pr_stabilization_fix, this feature worktree's
   checkout contract, and the specific fix-now items. Developer fixes, writes tests
   if behavior-changing (TDD), commits with Refs: #<feature-parent-issue>, pushes.
   Loop back to step 1.

5. If CI green and no actionable comments:
   Sealed report: stabilization_status: ready_for_human_merge,
   feedback_cutoff_at: <ISO timestamp now>, CI evidence, comment resolutions.
   Break loop.

6. After max 3 iterations with remaining fix-now items:
   stabilization_status: blocked, pause for human.
```

### 5. Open the feature PR + accept (`state:done`)

1. Task `developer` with `load: minimal` to run `scripts/feature-finish-pr.sh <slug>`. Expect `pr-created` / `pr-exists`. On `skipped-*`, surface verbatim.
2. **Accept each issue.** Use `mode-f-accept-issues.sh` from the existing `architect-review` skill:
   ```bash
   bash "$OC/skills/architect-review/lib/mode-f-accept-issues.sh" "<slug>" "<pr_url>" --repo <owner/name>
   ```
   Issues move to `state:done` and remain **open**.
3. Emit the **Phase 1 complete** table (slug, PR, accepted issue numbers, deferrals) and pause.

### 6. Phase 2 — documentation + merge gate

1. After human doc-scope confirmation, write `docs/changelog/<YYYY-MM-DD>-<slug>.md` plus any requested guides / architecture notes.
2. **Merge gate.** Ask the human exactly:
   ```text
   Feature <slug> is ready. Merge?
   (a) I will merge the feature PR manually
   (b) Merge on my behalf (orchestrate-style: gh pr merge <pr_url> --squash --delete-branch=false)
   ```
3. On `(a)` → emit the merge instructions + PR URL and pause.
4. On `(b)` → Task `developer` with `load: minimal` to run the chosen `gh pr merge` command. Verify `gh pr view <pr_url> --json state` is `MERGED`.
5. After merge (either path) → emit `HANDOFF_TO_DEVELOP_ORCHESTRATOR` with the merge evidence so the develop orchestrator can resume and tear down the feature worktree + remote feature branch.

### 7. Phase R (when acceptance is unmet)

If at any point the audit, feature code-review, or CodeRabbit finds unmet acceptance:

1. Create `remediation:`-prefixed GitHub issues in this impl repo, each linked as a sub-issue of the parent PRD issue.
2. Each remediation issue embeds `opencode-task-yaml` with the same `stages[]` shape as the original ticket.
3. Emit `HANDOFF_TO_DEVELOP_ORCHESTRATOR: REMEDIATION` with the remediation issue numbers. The develop orchestrator resumes and spawns new ticket worktrees through the same bounded-Task path (`execution_mode: github_issue_full`).
4. When remediation tickets merge into `opencode/feat-<slug>`, re-enter this skill from step 1.

## Failure handling

| Failure | Response |
|---|---|
| Audit finds sub-PR not merged | Surface the missing PR, pause for human |
| Feature-mode code-review returns `BLOCKED` | Fix directly in feature worktree (TDD), push, loop |
| CodeRabbit finds critical/major | Direct fix in feature worktree (no remediation ticket) |
| `scripts/feature-finish-pr.sh` returns `skipped-protected-branch` | Surface the message verbatim — the user must have started this session on a non-feature branch; stop |
| CI timeout during stabilization | Surface, pause for human |
| User defers doc scope or merge | Emit `DEFERRED` table; do not set `state:done` on anything that is not accepted |
| Cross-ticket comment discovered late | Direct fix in feature worktree when the touched files are already merged here; otherwise create one remediation issue |

## See also

- `skills/code-review/SKILL.md` — feature-mode grading gate (per-stage focused vs final-gate full-suite split, full regression at sign-off).
- `skills/architect-review/SKILL.md` — `mode-f-accept-issues.sh` lives here; Phase 2 doc schema.
- `skills/orchestrate/SKILL.md` — emits the `HANDOFF_TO_FEATURE_ARCHITECT` block you receive as input.
- `agents/architect.md` — the agent you run under; your context discipline and approval gates come from there.