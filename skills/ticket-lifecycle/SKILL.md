---
name: ticket-lifecycle
description: "Bounded full-ticket execution + self-stabilization contract for `execution_mode: github_issue_full`. Loaded by the **coder** primary agent in the ticket worktree so the coder owns every stage, sub-PR, and PR stabilization loop end-to-end and returns exactly one terminal report."
modelTier: "fast"
roleReminder: "Load on the first message of any coder session whose cwd is a ticket worktree (any first message — injected kickoff, user 'begin', or resume). The post-completion guard in implementer skills only fires after the terminal report, not between stages."
---

> You are operating inside a **coder** session: an OpenCode GUI session that was auto-started by `worktree_create` inside an `opencode/ticket-<issue>-<slug>-<abbrev>` worktree. You are the wrapping coder for one ticket. You never write or edit files yourself; you own every stage, every per-stage `code-review`, the sub-PR, and the PR stabilization loop. You return exactly **one** terminal report (`READY_FOR_HUMAN_REVIEW` or `BLOCKED`) and stop. The develop orchestrator (`orchestrate`) is reached via `session_notify`; the durable channel is the `ticket_report:` issue comment.

## Hard rules

1. **One terminal report.** Either `READY_FOR_HUMAN_REVIEW` (sub-PR URL + green CI + comment-clean) or `BLOCKED` (reason + partial evidence). Do not return success after each stage; do not hand off mid-ticket.
2. **Silent preflight.** Run `worktree-env` + `preflight` once, silently. One auto-repair pass (per `skills/preflight/SKILL.md` repair table). Only on `Status: Blocked` after the single repair pass do you surface to the parent.
3. **Stay on `opencode/ticket-<issue>-<slug>-<abbrev>`.** Do not switch branches, do not push to `develop` or `opencode/feat-<slug>` directly — only to your own ticket branch.
4. **Never delete remote branches.** `git push origin --delete` is owned exclusively by the develop orchestrator (delegated to `developer`). You push your ticket branch only.
5. **One sub-PR per ticket.** Sub-PR is `head=opencode/ticket-<issue>-<slug>-<abbrev>`, `base=opencode/feat-<slug>`. Do not open additional PRs.
6. **No nested fallbacks.** Dispatch `kilo-fallback`/`openrouter-fallback` for failed **children** only — never replace the coder itself, never dispatch one fallback from another.
7. **Context discipline.** Every ~10 tool iterations, compact state to 3 bullets (current stage, files touched, blockers). Discard old RED/GREEN raw outputs once `code-review` APPROVES the stage; keep only concise gate summaries.
8. **Stabilization is bounded.** PR stabilization loop runs **at most 3 iterations**. On exhaustion, return `BLOCKED: STABILIZATION_EXHAUSTED` with the remaining fix-now items.
9. **Cross-ticket review comments are not yours to fix.** If `pr-stabilize-watch.sh` returns comments whose fix would touch files in another ticket's branch, return `BLOCKED: CROSS_TICKET_REVIEW` so the develop orchestrator hands off to `architect-feature-signoff` early.
10. **Issue state transitions** (`state:in-progress` on entry, `state:ready-for-review` when the sub-PR opens) are yours; use `scripts/issue-state-transition.sh` via a delegated `developer` Task.
11. **You are the auto-started GUI session for this worktree.** The develop orchestrator does **not** dispatch you via `task` (cwd inheritance would put you on `develop`); you are reached via the kickoff message injected by the plugin or via any user message. You must self-bootstrap from disk + GitHub — do not depend on inputs from the orchestrator.
12. **Verification backend is containerized only.** Every RED/GREEN/final-gate test run goes through `docker-compose.test.yml` via `sandbox exec` (opencode-server) or direct `docker compose` (local dev) — **never** host-local suite setup. `compose_test_file: none` → `ENV_BLOCKED` with `recommended_env_fix: add docker-compose.test.yml from templates/project-stub/`. No host npm/pip installs to "get tests running".

## §0 Bootstrap (must run before any stage work)

Runs on **any** first message: the injected kickoff pointer, a user "begin", or a resume after a server restart. Never depend on the kickoff message containing the full brief — it is a short pointer by design, and a truncated message must not stall you. The **coder** agent has `bash: false`; reading the brief file uses the read tool, and the verification block is delegated to ONE `developer` Task.

### §0.1 Brief resolution (read tool only)

1. **Read `.git`** — `.git` inside a worktree is a file containing `gitdir: <abs path>`. Read it to get the gitdir path:

   ```text
   read_file: <worktree>/.git
   ```

2. **Read the brief file** at `<gitdir>/opencode-ticket-brief.json` (use the read tool):

   ```text
   read_file: <gitdir>/opencode-ticket-brief.json
   ```

   Capture `execution_mode`, `issue_number`, `repo`, `issue_url`, `feature_slug`, `feature_branch`, `expected_branch`, `agent`, `develop_session_id`, `kickoff_message`, `auto_spawn_consent`, `created_at`.

### §0.2 Fallback reconstruction (no user prompt)

If the brief file is missing or unparseable, **delegate ONE `developer` Task** with `load: minimal` to run the bash block (branch verify, `gh repo view`, `gh issue view --json body` opencode-task-yaml extraction, `merge-base` check) and return the parsed brief. **Never** ask the user to paste the brief — reconstruct from GitHub.

```text
Task developer load: minimal
Resolve the ticket brief for the current worktree.

cwd: <worktree absolute path>            # you ARE the ticket worktree
repo_root: <impl_repo root>
expected_branch: opencode/ticket-<n>-<slug>-<abbrev>

1. git rev-parse --is-inside-work-tree              # expect true
2. git rev-parse --abbrev-ref HEAD                  # expect opencode/ticket-<n>-<slug>-<abbrev>
3. gh repo view --json nameWithOwner -q .nameWithOwner
4. gh issue view <issue_number> --repo <repo> --json body -q .body
5. awk '/^```opencode-task-yaml$/{f=1;next} /^```$/{if(f){f=0;exit}} f' |
   python3 -c 'import sys,json; print(json.dumps(json.load(sys.stdin)))'

Return JSON:
{
  "ok": true,
  "repo": "<OWNER/REPO>",
  "issue_number": <n>,
  "expected_branch": "opencode/ticket-<n>-<slug>-<abbrev>",
  "feature_branch": "opencode/feat-<slug>",
  "opencode_task_yaml": { ... parsed body ... },
  "merge_base_ok": true
}
```

### §0.3 Verification backend (silent preflight — delegated)

After the brief is in hand, delegate ONE `preflight` Task with `load: minimal` to resolve the verification backend. The preflight already reports `compose_test_file`, `docker`, `sandbox`, `verification_gap`. **Hard rule:** `compose_test_file: none` → stop with `BLOCKED: ENV_BLOCKED` + `recommended_env_fix: "Add docker-compose.test.yml (test-suite-sufficient) from templates/project-stub/ at the impl repo root"`. **Never** fall back to host-local test runners — do not install npm/pip/etc. on the host to "get tests running".

After preflight passes, the coder **delegates one `developer` Task** to bring the backend up once before stage 1:

```text
Task developer load: minimal
Bring up the verification backend for this ticket worktree.

cwd: <worktree absolute path>
compose_test_file: <absolute path to docker-compose.test.yml>
sandbox_enabled: true|false

if sandbox_enabled:
  load skill docker-sandbox
  sandbox exec --cwd <worktree absolute path> -- docker compose -f <compose_test_file> build
else:
  docker compose -f <compose_test_file> build

Return: { "ok": true, "compose_test_file": <path>, "compose_built": true, "test_command": <canonical docker compose test invocation> }
```

Subsequent test execution (test-writer RED, developer GREEN, code-review per-stage focused checks, final-gate full suite) uses the same backend. `opencode-task-yaml` `test_commands` execute **inside/through** the compose test service.

Implementer/code-review Tasks **load `docker-sandbox`** when compose applies — the existing RUNBOOK routing is preserved.

### §0.4 Other bootstrap steps

1. **Verify the checkout contract** (delegated `developer` Task with `load: minimal`, or trust the §0.2 result):

   ```bash
   git rev-parse --is-inside-work-tree                # expect true
   git rev-parse --abbrev-ref HEAD                    # expect opencode/ticket-<n>-<slug>-<abbrev>
   git merge-base --is-ancestor "origin/$feature_branch" HEAD   # expect success
   ```

   Mismatch → `BLOCKED: CHECKOUT_CONTRACT_FAILED` (the only bounce-out).

2. **Resume-safe idempotence.** If the issue already has `state:in-progress` and the worktree has commits or a PR is open, **resume, never restart**: jump to §2 stage loop at the current stage (read the most recent `code_review_gate:` comment to find the last APPROVED stage index; advance from `index+1`). Do not re-run RED/GREEN for already-approved stages. Do not re-post duplicate `code_review_gate:` comments.

3. **Set `state:in-progress`** (delegated `developer` Task with `cwd` already on the ticket worktree — no `OPENCODE_EXPECT_*` dance needed because you ARE the ticket worktree):

   ```bash
   bash <OC>/scripts/issue-state-transition.sh "<repo>" "<issue_number>" state:in-progress
   ```

   `state:in-progress` automatically removes `verified` and adds `unverified` — the verification gate will re-arm when this ticket reaches `state:ready-for-review` again.

## Required inputs (truth sources)

You are not dispatched via `task` — the develop orchestrator reaches you via the kickoff pointer. The three sources of truth, in priority order:

1. **Brief file** `<worktree-gitdir>/opencode-ticket-brief.json` — written by the plugin, survives restarts, durable until the worktree gitdir is pruned.
2. **GitHub issue + worktree branch** — `opencode-task-yaml` body, `feature:<slug>` label, `state:*` labels, `Blocked by:` section, branch name shape.
3. **Kickoff message** — a short pointer only; do not require it to contain the full payload. A truncated kickoff is not a failure.

If the brief file is missing but the branch + repo reconstruct cleanly, proceed (reconstruction is the resilience path). Only bounce out on `BLOCKED: CHECKOUT_CONTRACT_FAILED`.

## Procedure

### 1. Silent preflight

Already done in §0.3 — compose-backend resolved + built. Skip if you trust that preflight returned `ok: true`. If you re-run for any reason, run **`worktree-env`** with `load: full` and **`preflight`** with `load: full`, repair-first, **silently**. Surface only if preflight reports `Status: Blocked` after one repair pass.

### 2. Loop every `opencode_meta.stages[]` entry

For each `stage` in `opencode_meta.stages` (in order, **starting from `last_approved_stage_index + 1`** on resume):

1. **RED** — dispatch `test-writer` (or implementer RED for non-test stages) with the stage scope; capture `red_phase` proof of RED from the compose-backend test run (test identifier + failure output). RED evidence is the test-run output, not claims.
2. **GREEN** — execute the stage as `Owner` (developer | frontend-dev | ux-dev) per `stage.owner`. The Owner implements, then **runs the same compose-backend test as part of red→green** and confirms green **before** reporting. Capture `green_phase` and `assertion_delta`. GREEN evidence is the compose test output, not claims.
3. **`code-review` (ticket mode)** — dispatch `code-review` with `load: full`, the stage's `diff_base`, `files_changed`, `red_phase` + `green_phase` evidence, and the issue's acceptance mapping. Focused per-stage checks (design, correctness, stage scope, RED/GREEN replay). **No full regression per stage.**
   - On `APPROVED` → stage done. Compact context, retain only gate summary.
   - On `NEEDS_CHANGES` → fix in-worktree (TDD), re-run code-review (max 2 stage retries).
   - On `BLOCKED` → return `BLOCKED` from the ticket (cross-cutting blocker).
4. After the final stage → run `StageAcceptanceChecks` end-to-end. Commit any remaining stage outputs with `Refs: #<issue_number>`.

#### 2.5 Senior-dev escalation + provider fallback

**Senior-dev escalation** (unattended — no operator confirmation; the only human gate is PR review):

Trigger: stage retry budget exhausted (2 `NEEDS_CHANGES` retries on `code-review`) **OR** the stage is marked hard/senior. Dispatch **once**:

```text
Task senior-dev load: full
execution_mode: escalation_fix
stage_id: <stage.id>
plan_file: <opencode-task-yaml path or stage scope>
failure_evidence: <blocker report + code-review findings + helper strategy>
retry_history: <attempts so far>
checkout_contract: { ... }
```

Senior-dev diagnoses, implements the minimal unblocker, returns `HANDOFF_TO_DEVELOPER`. Resume the Owner for remaining stage work. Still stuck → `BLOCKED: STAGE_STUCK`.

**Provider fallback** (catch-all net for failed children):

For a failed bounded child Task whose failure is not recoverable in-role (provider/router errors, persistent logic-class failure with helper strategy already applied, transient 5xx/timeout after the same-agent retry):

```text
Task <kilo-fallback|openrouter-fallback> load: full
fallback_context: {
  "original_agent": "<developer|frontend-dev|ux-dev|test-writer|code-review|scribe|...>",
  "original_skill": "<exact skill name to load>",
  "task_contract": "<verbatim original Task prompt>",
  "failure_evidence": "<error class, retry count, unfinished work>",
  "attempt_history": "<providers + load levels already tried>",
  "recovery_strategy": "<helper / scribe amendment applied, if any>",
  "requested_provider": "kilo" | "openrouter" | null
}
```

One attempt per provider per bounded Task; track `attempted_providers`. After both fail → `BLOCKED: FALLBACK_EXHAUSTED` and prompt the operator. **Never** dispatch one fallback from another. **Never** replace a primary agent (`coder`, `orchestrate`, `architect`).

### 3. Open the sub-PR

1. Push your branch: `git push -u origin <expected_branch>` (delegated developer).
2. Open the sub-PR via `gh pr create --base opencode/feat-<slug> --head <expected_branch> --title "feat(<slug>): ticket <issue> — <title>" --body <auto-body>` (delegated developer).
3. **Final-gate full-suite verification** — the **final** `all_stages: true` `code-review` gate before `state:ready-for-review` runs the **full test suite** via the compose backend (full regression, integration, e2e). The per-stage code-review stays focused.
4. Post the `code_review_gate:` comment with `all_stages: true`, `verdict: APPROVED`, and add the `verified` label.
5. `state:ready-for-review` on the issue via `scripts/issue-state-transition.sh`.

### 4. PR stabilization loop (max 3 iterations)

For `iter` in 1..3:

```text
report = delegated developer load: minimal \
  bash <OC>/scripts/pr-stabilize-watch.sh <pr_url>

switch report.classify:
  case "ready":
    break loop
  case "awaiting-human":
    # comments explicitly marked WIP / hold / do not merge — exit stabilization,
    # treat as READY_FOR_HUMAN_REVIEW with note
    break loop
  case "fix-now":
    for each fix-now item in (report.ci failing checks (via `gh pr checks <pr_url> --json name,state,conclusion`), report.comments, report.reviews):
      if item spans another ticket's branch files:
        return BLOCKED: CROSS_TICKET_REVIEW { item, evidence }
      fix in-worktree with TDD (RED→GREEN, behavior changes only),
      commit "Refs: #<issue_number>", push branch
    loop back to next iter
```

### 5. Terminal report

Emit the terminal report (in-session, normal prose), **post the `ticket_report:` comment on the issue** (mandatory durable channel — same pattern as `code_review_gate:`), and best-effort `session_notify` the develop orchestrator before stopping. **The coder itself** calls `session_notify` (it holds the tool — no delegated developer framing).

#### §0-completion: tear down the verification backend

Before stopping, lifecycle-aware destroy of the compose test backend (`docker-sandbox` §5 — `sandbox destroy` when the server sandbox is enabled, or `docker compose -f <compose_test_file> down` on local dev). Delegated `developer` Task with `load: minimal`.

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
  blocker_code: ENV_BLOCKED | STAGE_STUCK | STABILIZATION_EXHAUSTED | CROSS_TICKET_REVIEW | CHECKOUT_CONTRACT_FAILED | SKILL_UNAVAILABLE | FALLBACK_EXHAUSTED
  reason:       <one-line>
  partial_evidence:
    stages_completed:  <count>
    last_ci_state:     pass|fail|pending
    last_pr_url:       <url if open>
    failing_checks:    [<names>]
    fix_now_outstanding: <count>
  recommended_helper_request: <one concrete request>
```

#### 5c. Best-effort wake via `session_notify` (the coder holds the tool)

```text
message = "ticket_report: <repo>#<n> | status: READY_FOR_HUMAN_REVIEW | pr: <url> | ci: pass | stages: <n>\nnext_action: merge sub-PR on human approval"
# or, for BLOCKED:
message = "ticket_report: <repo>#<n> | status: BLOCKED | blocker: <code> | reason: <one-line>"

result = session_notify { sessionID: <develop_session_id>, agent: orchestrate, message }

if result.admitted == true: record notify_status: admitted
elif result.status == 404: record notify_status: develop_session_id_stale (the brief file's stored id may be stale after a restart — the ticket_report: comment + poller are the durable wake path)
else:                       record notify_status: <error from result.error>
```

The `ticket_report:` comment is the **mandatory** durable channel. `session_notify` is best-effort; its failure is recorded in the comment but never blocks the terminal report.

Emit the terminal report and stop. The implementer Hard Rules' post-completion guard now fires — any subsequent user message is answered with: "Task complete. Switch to the `orchestrate` agent to continue."

## Code-review grading gate

Per-stage `code-review` (focused): APPROVED requires non-missing criterion coverage, manual criteria with evidence or accepted deviation, security resolved, complete report. Empty/malformed/step-limited report = `BLOCKED`; retry once with `load: full`, then senior-dev escalation.

Final `all_stages: true` gate (before `state:ready-for-review`): same grading, plus the full-suite compose test run is green and `StageAcceptanceChecks` passed. Empty/malformed/step-limited → retry once with `load: full`, then senior-dev escalation.

## Anti-loop

- Do not emit the same verbal statement twice. Move after the first intent statement.
- Do not re-announce file writes or commands.
- After a stage's `code-review` APPROVED, compact: discard raw RED/GREEN outputs; retain only the verdict + commit ref.

## See also

- `agents/coder.md` — host posture + skill/task allow-list.
- `agents/developer.md`, `agents/frontend-dev.md`, `agents/ux-dev.md`, `agents/test-writer.md`, `agents/code-review.md` — stage executors.
- `agents/senior-dev.md` + `skills/senior-dev/SKILL.md` — escalation_fix returns `HANDOFF_TO_DEVELOPER` to resume the wrapping coder.
- `agents/kilo-fallback.md`, `agents/openrouter-fallback.md` — provider fallback for failed children (never replaces the coder).
- `skills/code-review/SKILL.md` — per-stage focused vs final-gate full-suite split.
- `skills/docker-sandbox/SKILL.md` — `sandbox exec` vs direct compose matrix + lifecycle-aware destroy.
- `skills/preflight/SKILL.md` — silent preflight, `compose_test_file`/`verification_gap` reporting.
- `scripts/issue-state-transition.sh`, `scripts/pr-stabilize-watch.sh`, `scripts/dev-loop-watch.sh`, `scripts/checkout-contract.sh` — moved lib scripts.
- `plugins/worktree.js` — `worktree_create` (kickoff params) and `session_notify`.
- `skills/orchestrate/SKILL.md` — the wrapping develop orchestrator.