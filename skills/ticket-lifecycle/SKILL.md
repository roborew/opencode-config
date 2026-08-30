---
name: ticket-lifecycle
description: "Bounded full-ticket execution + self-stabilization contract for `execution_mode: github_issue_full`. Loaded inside the ticket session (developer/frontend-dev/ux-dev) so the ticket owns every stage, sub-PR, and PR stabilization loop end-to-end and returns exactly one terminal report."
modelTier: "fast"
roleReminder: "Load on the first message of any session whose cwd is a ticket worktree (any first message — injected kickoff, user 'begin', or resume). The post-completion guard at the bottom of developer/frontend-dev/ux-dev skills must NOT fire between stages — only after the terminal report."
---

> You are operating inside a **ticket session**: an OpenCode GUI session that was auto-started by `worktree_create` inside an `opencode/ticket-<issue>-<slug>-<abbrev>` worktree. You own every stage, every `code-review` per stage, the sub-PR, and the PR stabilization loop. You return exactly **one** terminal report and stop.

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
11. **You are the auto-started GUI session for this worktree.** The develop orchestrator does **not** dispatch you via `task` (cwd inheritance would put you on `develop`); you are reached via the kickoff message injected by the plugin or via any user message. You must self-bootstrap from disk + GitHub — do not depend on inputs from the orchestrator.

## §0 Bootstrap (must run before any stage work)

Runs on **any** first message: the injected kickoff pointer, a user "begin", or a resume after a server restart. Never depend on the kickoff message containing the full brief — it is a short pointer by design, and a truncated message must not stall you.

1. **Read the brief file.** The plugin wrote `<worktree-gitdir>/opencode-ticket-brief.json`. Resolve gitdir:

   ```bash
   gitdir="$(git rev-parse --path-format=absolute --git-dir)"
   brief="$gitdir/opencode-ticket-brief.json"
   ```

   Read `$brief` if it exists and parses as JSON. Capture `execution_mode`, `issue_number`, `repo`, `issue_url`, `feature_slug`, `feature_branch`, `expected_branch`, `agent`, `develop_session_id`, `kickoff_message`, `auto_spawn_consent`, `created_at`.

2. **If the brief file is missing or unparseable, reconstruct from GitHub + git state — never ask the user to paste anything:**

   ```bash
   # branch shape: opencode/ticket-<issue>-<slug>-<abbrev>
   branch="$(git rev-parse --abbrev-ref HEAD)"
   issue_number="$(printf '%s' "$branch" | sed -nE 's#^opencode/ticket-([0-9]+)-.*$#\1#p')"
   repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
   feature_slug="$(printf '%s' "$branch" | sed -nE 's#^opencode/ticket-[0-9]+-([a-z0-9-]+)-[a-z0-9-]+$#\1#p')"
   # feature_branch from the issue's `feature:<slug>` label
   feature_branch="opencode/feat-${feature_slug}"
   body="$(gh issue view "$issue_number" --repo "$repo" --json body -q .body)"
   opencode_meta="$(printf '%s' "$body" | awk '/^```opencode-task-yaml$/{f=1;next} /^```$/{if(f){f=0;exit}} f' | python3 -c 'import sys,json; print(json.dumps(json.load(sys.stdin)))' 2>/dev/null || echo null)"
   expected_branch="$branch"
   agent="${agent:-developer}"
   develop_session_id="${develop_session_id:-null}"
   kickoff_message="${kickoff_message:-<bootstrap from GitHub>}"
   ```

3. **Verify the checkout contract** (cwd IS the ticket worktree by construction — `worktree_create` made the GUI session there):

   ```bash
   git rev-parse --is-inside-work-tree                # expect true
   git rev-parse --abbrev-ref HEAD                    # expect opencode/ticket-<n>-<slug>-<abbrev>
   git merge-base --is-ancestor "origin/$feature_branch" HEAD   # expect success after the develop orchestrator's post-create reset
   ```

   Mismatch → `BLOCKED: CHECKOUT_CONTRACT_FAILED` (the only bounce-out).

4. **Resume-safe idempotence.** If the issue already has `state:in-progress` and the worktree has commits or a PR is open, **resume, never restart**: jump to §2 stage loop at the current stage (read the most recent `code_review_gate:` comment to find the last APPROVED stage index; advance from `index+1`). Do not re-run RED/GREEN for already-approved stages. Do not re-post duplicate `code_review_gate:` comments.

5. **Set `state:in-progress`** (delegated `developer` Task with `cwd` already on the ticket worktree — no `OPENCODE_EXPECT_*` dance needed because you ARE the ticket worktree):

   ```bash
   bash <OC>/skills/github-issue-run/lib/issue-state-transition.sh "<repo>" "<issue_number>" state:in-progress
   ```

   `state:in-progress` automatically removes `verified` and adds `unverified` — the verification gate will re-arm when this ticket reaches `state:ready-for-review` again.

## Required inputs (truth sources)

The develop orchestrator no longer passes the full payload in the dispatch message (you are not dispatched). The three sources of truth, in priority order:

1. **Brief file** `<worktree-gitdir>/opencode-ticket-brief.json` — written by the plugin, survives restarts, durable until the worktree gitdir is pruned.
2. **GitHub issue + worktree branch** — `opencode-task-yaml` body, `feature:<slug>` label, `state:*` labels, `Blocked by:` section, branch name shape.
3. **Kickoff message** — a short pointer only; do not require it to contain the full payload. A truncated kickoff is not a failure.

If the brief file is missing but the branch + repo reconstruct cleanly, proceed (reconstruction is the resilience path; this is exactly the #245 incident fix). Only bounce out on `BLOCKED: CHECKOUT_CONTRACT_FAILED`.

## Procedure

### 1. Silent preflight

```bash
# delegated developer with load: minimal
git rev-parse --is-inside-work-tree  # expect true
git rev-parse --abbrev-ref HEAD      # expect <expected_branch>
```

Then run **`worktree-env`** with `load: full` and **`preflight`** with `load: full`, repair-first, **silently**. Surface only if preflight reports `Status: Blocked` after one repair pass; otherwise proceed to step 2 without prompting.

### 2. Loop every `opencode_meta.stages[]` entry

For each `stage` in `opencode_meta.stages` (in order, **starting from `last_approved_stage_index + 1`** on resume):

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

Emit the terminal report (in-session, normal prose), **post the `ticket_report:` comment on the issue** (mandatory durable channel — same pattern as `code_review_gate:`), and best-effort `session_notify` the develop orchestrator before stopping.

#### 5a. Post the `ticket_report:` comment (mandatory)

```bash
gh issue comment "<issue_number>" --repo "<repo>" --body "$(cat <<'EOF'
ticket_report:
  status: READY_FOR_HUMAN_REVIEW | BLOCKED
  issue: <repo>#<issue_number>
  pr_url: <url>                    # READY only
  ci_state: pass|pending|fail       # READY only
  stages_completed: <count>
  blocker_code: <code>             # BLOCKED only
  reason: <one-line>                # BLOCKED only
  next_action: <what the develop orchestrator should do>
  notify_status: admitted|failed|<reason>   # see §5c
EOF
)"
```

The develop orchestrator's `dev-loop-watch.sh` parses `ticket_report:` comments to surface state and detect out-of-band GitHub-UI merges; the poller (`scripts/dev-loop-poller.sh`) also diffs them to wake the develop orchestrator when it is idle. Without this comment, the develop orchestrator stays paused and the watch/poller cannot detect the terminal state.

#### 5b. Block shape

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

#### 5c. Best-effort wake via `session_notify`

```text
message = "ticket_report: <repo>#<n> | status: READY_FOR_HUMAN_REVIEW | pr: <url> | ci: pass | stages: <n>\nnext_action: merge sub-PR on human approval"
# or, for BLOCKED:
message = "ticket_report: <repo>#<n> | status: BLOCKED | blocker: <code> | reason: <one-line>"

result = delegated developer load: minimal \
  session_notify { sessionID: <develop_session_id>, agent: orchestrate, message }

if result.admitted == true: record notify_status: admitted
elif result.status == 404: record notify_status: develop_session_id_stale (the brief file's stored id may be stale after a restart — the ticket_report: comment + poller are the durable wake path)
else:                       record notify_status: <error from result.error>
```

The `ticket_report:` comment is the **mandatory** durable channel. `session_notify` is best-effort; its failure is recorded in the comment but never blocks the terminal report.

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
- `skills/github-issue-run/lib/dev-loop-watch.sh` — develop orchestrator's per-issue watcher.
- `skills/orchestrate-develop-loop/SKILL.md` — the parent orchestrator.
- `plugins/worktree.js` — `worktree_create` (kickoff params) and `session_notify`.