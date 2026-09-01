---
name: ticket-lifecycle
description: "Bounded full-ticket execution + self-stabilization contract for `execution_mode: github_issue_full`. Loaded by the **coder** primary agent in the ticket worktree so the coder owns every stage, sub-PR, and PR stabilization loop end-to-end and returns exactly one terminal report."
modelTier: "fast"
roleReminder: "Load on the first message of any coder session whose cwd is a ticket worktree (any first message — injected kickoff, user 'begin', or resume). The post-completion guard in implementer skills only fires after the terminal report, not between stages."
---

> You are operating inside a **coder** session: an OpenCode GUI session that was auto-started by `worktree_create_ticket` inside an `opencode/ticket-<issue>-<slug>-<abbrev>` worktree. You are the wrapping coder for one ticket. You never write or edit files yourself; you own every stage, every per-stage `code-review`, the sub-PR, and the PR stabilization loop. You return exactly **one** terminal report (`READY_FOR_HUMAN_REVIEW` or `BLOCKED`) and stop. The develop orchestrator (`orchestrate`) is reached via `session-manager.notify`; the durable channel is the `ticket_report:` issue comment.

## Hard rules

1. **One terminal report.** Either `READY_FOR_HUMAN_REVIEW` (sub-PR URL + green CI + comment-clean) or `BLOCKED` (reason + partial evidence). Do not return success after each stage; do not hand off mid-ticket.
2. **Silent preflight.** Run `worktree-env` + `preflight` once, silently. One auto-repair pass (per `skills/preflight/SKILL.md` repair table). Only on `Status: Blocked` after the single repair pass do you surface to the parent.
3. **Stay on `opencode/ticket-<issue>-<slug>-<abbrev>`.** Do not switch branches, do not push to `develop` or `opencode/feat-<slug>` directly — only to your own ticket branch.
4. **Never delete remote branches.** `git push origin --delete` is owned exclusively by the develop orchestrator (delegated to `developer`). You push your ticket branch only.
5. **One sub-PR per ticket.** Sub-PR is `head=opencode/ticket-<issue>-<slug>-<abbrev>`, `base=opencode/feat-<slug>`. Do not open additional PRs.
6. **No nested fallbacks.** Dispatch `kilo-fallback`/`openrouter-fallback` for failed **children** only — never replace the coder itself, never dispatch one fallback from another.
7. **Context discipline.** Every ~10 tool iterations, compact state to 3 bullets (current stage, files touched, blockers). Discard old RED/GREEN raw outputs once `code-review` APPROVES the stage; keep only concise gate summaries.
8. **Stabilization is bounded.** PR stabilization loop runs **at most 3 iterations**. On exhaustion, return `BLOCKED: STABILIZATION_EXHAUSTED` with the remaining fix-now items.
9. **Cross-ticket review comments are not yours to fix.** If `pr-stabilize-watch.sh` returns comments whose fix would touch files in another ticket's branch, return `BLOCKED: CROSS_TICKET_REVIEW` so the develop orchestrator routes it to the feature coder's remediation flow.
10. **Issue state transitions** (`state:in-progress` on entry, `state:ready-for-review` when the sub-PR opens) are yours; use `scripts/issue-state-transition.sh` via a delegated `developer` Task.
11. **You are the auto-started GUI session for this worktree.** The develop orchestrator does **not** dispatch you via `task` (cwd inheritance would put you on `develop`); you are reached via the kickoff message injected by `session-manager` (which calls `session.promptAsync`) or via any user message. You must self-bootstrap from your **most recent user message** + the branch + GitHub — there is no brief file written; the kickoff message IS the contract.
12. **Verification backend is containerized only.** Every RED/GREEN/final-gate test run goes through `docker-compose.test.yml` via `sandbox exec` (opencode-server) or direct `docker compose` (local dev) — **never** host-local suite setup. `compose_test_file: none` → `ENV_BLOCKED` with `recommended_env_fix: add docker-compose.test.yml from templates/project-stub/`. No host npm/pip installs to "get tests running".

## §0 Bootstrap (must run before any stage work)

Runs on **any** first message: the injected kickoff pointer (via `session-manager.kickoff`), a user "begin", or a resume after a server restart. **Read your most recent user message first — that message is the kickoff pointer. Treat it as authoritative.** It contains `execution_mode`, the issue url (`OWNER/REPO#<n>`), the feature slug, `expected_branch`, `worktree`, and `develop_session_id` (the develop orchestrator's session id, used by §6c for the terminal `session-manager.notify` injection), plus the inline "Load skill ticket-lifecycle and begin" instruction.

If the message is empty, unparseable, or was truncated, fall back to §0.2 GitHub reconstruction — that is now the primary resilience path. The kickoff message is short by design and a truncated message must never stall you. The **coder** agent has `bash: false`; reading the kickoff pointer uses the read tool, and the reconstruction block is delegated to ONE `developer` Task.

### §0.0 Handshake (push the feature branch from this worktree — runs before §0.1 / §0.2)

The coder session's cwd IS the ticket worktree directory. You own the handshake push: ensure `opencode/feat-<slug>` exists remotely, push it from your worktree cwd, then push your own ticket branch. **worktree-manager does not push** (local-only `/experimental/worktree` plumbing), and the orchestrator never pushes a branch it didn't delete. Delegate ONE `developer load: minimal` Task from the worktree cwd:

```text
Task developer load: minimal
Run the §0.0 Handshake push for the current ticket worktree.

cwd: <worktree absolute path>            # you ARE the ticket worktree
repo_root: <impl_repo root>
feature_branch: opencode/feat-<slug>
expected_branch: opencode/ticket-<n>-<slug>-<abbrev>

1. default_branch=$(gh repo view <OWNER>/<REPO> --json defaultBranchRef -q .defaultBranchRef.name)
2. git fetch origin <feature_branch> || true
3. if ! git rev-parse --verify "origin/<feature_branch>" >/dev/null 2>&1; then
     sha=$(gh api repos/<OWNER>/<REPO>/git/ref/heads/<default_branch> -q .object.sha)
     gh api -X POST repos/<OWNER>/<REPO>/git/refs \
       -f ref="refs/heads/<feature_branch>" -f sha="$sha"
     # 422 (already exists) is treated as success
   fi
4. git push -u origin <feature_branch>                  # BLOCKED: HANDSHAKE_PUSH_FAILED on failure (stderr verbatim)
5. git push -u origin <expected_branch>                # BLOCKED: HANDSHAKE_PUSH_FAILED on failure (stderr verbatim)
6. [ "$(git rev-parse --abbrev-ref HEAD)" = "<expected_branch>" ] || { echo "BLOCKED: CHECKOUT_CONTRACT_FAILED"; exit 1; }
   git rev-parse --verify "origin/<expected_branch>" >/dev/null 2>&1 || { echo "BLOCKED: CHECKOUT_CONTRACT_FAILED"; exit 1; }
   git merge-base --is-ancestor "origin/<feature_branch>" HEAD || { echo "BLOCKED: TICKET_NOT_FORKED_FROM_FEATURE"; exit 1; }

Return JSON:
{
  "ok": true,
  "feature_branch": "opencode/feat-<slug>",
  "expected_branch": "opencode/ticket-<n>-<slug>-<abbrev>",
  "remote_feature_branch_created": true|false,
  "remote_expected_branch_created": true|false,
  "merge_base_ok": true
}
```

Step ordering is load-bearing: `gh api create_ref` MUST run before `git push` so a missing remote branch surfaces as `BLOCKED: HANDSHAKE_FEATURE_BRANCH_CREATE_FAILED` (or simply succeeds and falls through to `git push`) rather than a confusing `fatal: could not read Username` from `git push`. Step 3 checks `rev-parse --verify origin/<feature_branch>` first so `create_ref` is unreachable when the branch exists (422 means "already exists" — treat as success). Step 4's `git push -u origin <feature_branch>` is naturally idempotent across parallel coder sessions (fast-forward or up-to-date). On any non-zero exit, surface the developer's `blocker_code` verbatim — do not retry from here. Subsequent steps (§0.1 / §0.2 / §0.3 / §0.4) depend on the handshake succeeding.

### §0.1 Brief resolution — REMOVED

The brief file (`<worktree-gitdir>/opencode-ticket-brief.json`) is **no longer written**. There is no file on disk to read. The kickoff message inline is the brief. Skip this section entirely; do not look for `<gitdir>/opencode-ticket-brief.json` on disk. The worktree's `.git` file is irrelevant to bootstrap — `git rev-parse` (via delegated `developer`) is how you confirm `expected_branch`.

### §0.2 GitHub reconstruction (primary fallback — delegated `developer` Task)

If your most recent user message is missing or unparseable, **delegate ONE `developer` Task** with `load: minimal` to reconstruct the kickoff context from the branch + GitHub. This is now the primary resilience path — the durable source of truth is GitHub, not a brief file.

```text
Task developer load: minimal
Resolve the ticket kickoff context for the current worktree from GitHub.

cwd: <worktree absolute path>            # you ARE the ticket worktree
repo_root: <impl_repo root>
expected_branch: opencode/ticket-<n>-<slug>-<abbrev>

1. git rev-parse --is-inside-work-tree              # expect true
2. git rev-parse --abbrev-ref HEAD                  # expect opencode/ticket-<n>-<slug>-<abbrev>
3. git rev-parse --abbrev-ref HEAD | sed 's|^opencode/ticket-||' | awk -F- '{print $1}'   # derive <n>
4. git rev-parse --abbrev-ref HEAD | sed 's|^opencode/ticket-<n>-||' | sed 's|-[^-]*$||'   # derive <slug>
5. gh repo view --json nameWithOwner -q .nameWithOwner
6. gh issue view <issue_number> --repo <repo> --json body -q .body
7. awk '/^```opencode-task-yaml$/{f=1;next} /^```$/{if(f){f=0;exit}} f' |
   python3 -c 'import sys,json; print(json.dumps(json.load(sys.stdin)))'
8. (best-effort) gh issue view <issue_number> --repo <repo> --json comments -q '.comments[] | select(.body | startswith("develop_session_id:")) | .body' | head -1
   # last develop_session_id the develop orchestrator posted on the issue; fall back to the
   # current develop session id (opencode-run orchestrator session --current) if absent

Return JSON:
{
  "ok": true,
  "repo": "<OWNER/REPO>",
  "issue_number": <n>,
  "expected_branch": "opencode/ticket-<n>-<slug>-<abbrev>",
  "feature_branch": "opencode/feat-<slug>",
  "opencode_task_yaml": { ... parsed body ... },
  "develop_session_id": "<id or null>",
  "merge_base_ok": true
}
```

Use the returned JSON as your kickoff pointer. If `develop_session_id` is `null`, the durable `ticket_report:` issue comment is the only wake channel (no `session-manager.notify` target); record this and continue — §6c handles the missing-id case.

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

1. **Your most recent user message** — the kickoff pointer injected by `session-manager.kickoff` via `session.promptAsync`. Treat it as authoritative; it is the contract. Short by design — do not require it to contain the full payload.
2. **GitHub issue + worktree branch** — `opencode-task-yaml` body, `feature:<slug>` label, `state:*` labels, `Blocked by:` section, branch name shape. This is the durable source; it backs §0.2 reconstruction when the kickoff message is missing.
3. **Worktree branch + GitHub reconstruction** (delegated `developer` Task) — the fallback path for a missing/empty kickoff message.

If the kickoff message is missing but the branch + repo reconstruct cleanly, proceed (reconstruction is the resilience path). Only bounce out on `BLOCKED: CHECKOUT_CONTRACT_FAILED`.

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

### 3. Final gate — full suite + CodeRabbit pre-flight (before push/PR)

1. **Final-gate full-suite verification** — dispatch `code-review` (`load: full`) for the **final** `all_stages: true` gate: the **full test suite** via the compose backend (full regression, integration, e2e). The per-stage code-review stays focused. On `APPROVED` → post the `code_review_gate:` comment with `all_stages: true`, `verdict: APPROVED`, and add the `verified` label. On `NEEDS_CHANGES` → fix in-worktree (TDD), re-run (grading + retry rules: the "Code-review grading gate" section below).

2. **Local CodeRabbit pre-flight** — dispatch `code-review` once with `load: full`, `execution_mode: ticket_coderabbit_preflight`, the ticket worktree path, `base_branch: opencode/feat-<slug>`, and the per-stage code-review evidence. Scope: correctness, obvious bugs, and risky changes only (narrow rule set — narrow further if this and the PR-side feature gate keep producing duplicate noise).

   - On `PASS` → proceed to §4.
   - On `BLOCKED` → apply the fix-now suggestions in-worktree (TDD, behaviour changes only), commit `Refs: #<issue_number>`, push the ticket branch, re-run the pre-flight before the sub-PR opens. Max 2 retries, then `BLOCKED: PREFLIGHT_EXHAUSTED`.
   - On `SKIPPED` (CLI/auth unavailable) → record `coderabbit_preflight: SKIPPED` in the ticket_report and proceed. The PR-side feature gate is the policy blocker; missing the pre-flight does not block the ticket terminal report.

### 4. Open the sub-PR

1. Push your branch: `git push -u origin <expected_branch>` (delegated developer).
2. Open the sub-PR via `gh pr create --base opencode/feat-<slug> --head <expected_branch> --title "feat(<slug>): ticket <issue> — <title>" --body <auto-body>` (delegated developer).
3. `state:ready-for-review` on the issue via `scripts/issue-state-transition.sh` (the sub-PR is now open; the final gate + `verified` label already landed in §3).

### 5. PR stabilization loop (max 3 iterations)

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

### 6. Terminal report

Emit the terminal report (in-session, normal prose), **post the `ticket_report:` comment on the issue** (mandatory durable channel — same pattern as `code_review_gate:`), and best-effort `session-manager.notify` the develop orchestrator before stopping. **The coder dispatches the `session-manager` subagent** for the injection (the `session-manager` subagent owns `session_notify` — the coder does not hold the plugin tool directly).

#### §0-completion: tear down the verification backend

Before stopping, lifecycle-aware destroy of the compose test backend (`docker-sandbox` §5 — `sandbox destroy` when the server sandbox is enabled, or `docker compose -f <compose_test_file> down` on local dev). Delegated `developer` Task with `load: minimal`.

#### 6a. Post the `ticket_report:` comment (mandatory)

```bash
gh issue comment "<issue_number>" --repo "<repo>" --body "$(cat <<'EOF'
ticket_report:
  status: READY_FOR_HUMAN_REVIEW | BLOCKED
  issue: <repo>#<issue_number>
  pr_url: <url>                    # READY only
  ci_state: pass|pending|fail       # READY only
  stages_completed: <count>
  coderabbit_preflight: PASS | SKIPPED | BLOCKED   # see §3
  coderabbit_preflight_skip_reason: <reason>  # SKIPPED only
  blocker_code: <code>             # BLOCKED only
  reason: <one-line>                # BLOCKED only
  next_action: <what the develop orchestrator should do>
  notify_status: admitted|failed|<reason>   # see §6c
EOF
)"
```

The develop orchestrator's `dev-loop-watch.sh` parses `ticket_report:` comments to surface state and detect out-of-band GitHub-UI merges; the poller (`scripts/dev-loop-poller.sh`) also diffs them to wake the develop orchestrator when it is idle. Without this comment, the develop orchestrator stays paused and the watch/poller cannot detect the terminal state.

#### 6b. Block shape

Exactly one of:

```yaml
READY_FOR_HUMAN_REVIEW:
  issue_number: <n>
  pr_url:      <url>
  ci_state:    pass|pending
  evidence:    <pr-stabilize-watch evidence line>
  comment_resolutions: [{ author, classification, action }]
  stages_completed:   <count>
  coderabbit_preflight: PASS | SKIPPED
  awaiting_human_notes: <optional list of WIP/hold comments>
  next_action_for_parent: "merge sub-PR into opencode/feat-<slug> on human approval, then worktree + remote-branch cleanup"

BLOCKED:
  blocker_code: ENV_BLOCKED | STAGE_STUCK | STABILIZATION_EXHAUSTED | CROSS_TICKET_REVIEW | CHECKOUT_CONTRACT_FAILED | SKILL_UNAVAILABLE | FALLBACK_EXHAUSTED | PREFLIGHT_EXHAUSTED | HANDSHAKE_PUSH_FAILED | HANDSHAKE_FEATURE_BRANCH_CREATE_FAILED | TICKET_NOT_FORKED_FROM_FEATURE
  reason:       <one-line>
  partial_evidence:
    stages_completed:  <count>
    last_ci_state:     pass|fail|pending
    last_pr_url:       <url if open>
    failing_checks:    [<names>]
    fix_now_outstanding: <count>
  recommended_helper_request: <one concrete request>
```

#### 6c. Best-effort wake via `session-manager.notify` (the coder dispatches the subagent)

When the explicit `develop_session_id` is passed and `session_list` does not return it, `session-manager.notify` returns `error: "session_not_found"` (hard stop — no silent create) — the durable `ticket_report:` comment + `scripts/dev-loop-poller.sh` are the wake channel.

```text
message = "ticket_report: <repo>#<n> | status: READY_FOR_HUMAN_REVIEW | pr: <url> | ci: pass | stages: <n>\nnext_action: merge sub-PR on human approval"
# or, for BLOCKED:
message = "ticket_report: <repo>#<n> | status: BLOCKED | blocker: <code> | reason: <one-line>"

# The develop_session_id is supplied in the kickoff message inline (see §0 preamble).
# If it's missing (kickoff truncated, §0.2 reconstruction found no develop_session_id on
# the issue), pass `directory: <this worktree dir>` instead — the session-manager falls
# back to the newest no-parent session under that directory.
develop_target = { sessionID: <develop_session_id> } if develop_session_id else { directory: <worktree abs path> }

result = dispatch session-manager notify {
  ...develop_target,
  agent: "orchestrate",
  message,
}

if result.admitted == true: record notify_status: admitted
elif result.error == "session_not_found" and result.session_id == develop_session_id: record notify_status: develop_session_id_stale (the kickoff message's stored id may be stale after a restart — the ticket_report: comment + poller are the durable wake path)
elif result.status == 404: record notify_status: develop_session_id_stale (the kickoff message's stored id may be stale after a restart — the ticket_report: comment + poller are the durable wake path)
else:                       record notify_status: <error from result.error>
```

The `ticket_report:` comment is the **mandatory** durable channel. `session-manager.notify` is best-effort; its failure is recorded in the comment but never blocks the terminal report. **A failed wake is never silent:** when `notify_status` is anything other than `admitted`, end your final in-session report with this user instruction (the coder session is a GUI session — the user reads it):

```text
Automation wake failed (<notify_status>). The ticket_report: comment is posted on <repo>#<n>.
If the develop orchestrator has not merged the sub-PR within ~2 poll intervals (~4 min),
send any message to the develop orchestrator session — it runs dev-loop-watch.sh first and
will pick up the report from there.
```

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
- `skills/code-review/SKILL.md` — the verification contract: per-stage focused checks, final-gate full suite, local CodeRabbit pre-flight (`ticket_coderabbit_preflight`).
- `skills/docker-sandbox/SKILL.md` — `sandbox exec` vs direct compose matrix + lifecycle-aware destroy.
- `skills/preflight/SKILL.md` — silent preflight, `compose_test_file`/`verification_gap` reporting.
- `scripts/issue-state-transition.sh`, `scripts/pr-stabilize-watch.sh`, `scripts/dev-loop-watch.sh`, `scripts/checkout-contract.sh` — moved lib scripts.
- `plugins/worktree.js` — `worktree_create_ticket` is the sibling tool that creates this worktree.
- `plugins/session-manager.js` — `session_notify` is the underlying tool `session-manager.notify` dispatches for the terminal wake injection.
- `agents/session-manager.md` — the subagent the coder dispatches for the §6c terminal-report injection.
- `skills/orchestrate/SKILL.md` — the wrapping develop orchestrator.