---
name: ticket-lifecycle
description: "Bounded full-ticket execution + self-stabilization contract for `execution_mode: github_issue_full`. Loaded by the **coder** primary agent in the ticket worktree so the coder owns every stage, sub-PR, and PR stabilization loop end-to-end and returns exactly one terminal report."
modelTier: "fast"
roleReminder: "Load on the first message of any coder session whose cwd is a ticket worktree (any first message — injected kickoff, user 'begin', or resume). The post-completion guard in implementer skills only fires after the terminal report, not between stages."
---

> You are operating inside a **coder** session: an OpenCode GUI session that was auto-started by `worktree_create_ticket` inside an `opencode/ticket-<issue>-<slug>-<abbrev>` worktree. You are the wrapping coder for one ticket. You never write or edit files yourself; you own every stage, every per-stage `code-review`, the sub-PR, and the PR stabilization loop. You return exactly **one** terminal report (`READY_FOR_HUMAN_REVIEW` or `BLOCKED`) and stop. The develop orchestrator (`orchestrate`) is reached via the `session_notify` plugin tool; the durable channel is the `ticket_report:` issue comment.

## Hard rules

1. **One terminal report.** Either `READY_FOR_HUMAN_REVIEW` (sub-PR URL + green CI + comment-clean + complete `human_review_handoff/v1`) or `BLOCKED` (reason + partial evidence). Do not return success after each stage; do not hand off mid-ticket.
2. **Silent verification-backend bring-up.** Run `worktree-sandbox` `mode: probe_and_create` once, silently. One auto-repair pass is allowed through that bounded setup flow. Only on `Status: Blocked` after the single repair pass do you surface to the parent.
3. **Stay on `opencode/ticket-<issue>-<slug>-<abbrev>`.** Do not switch branches, do not push to `develop` or `opencode/feat-<slug>` directly — only to your own ticket branch.
4. **Never delete remote branches.** `git push origin --delete` is owned exclusively by the develop orchestrator (delegated to `developer`). You push your ticket branch only.
5. **One sub-PR per ticket.** Sub-PR is `head=opencode/ticket-<issue>-<slug>-<abbrev>`, `base=opencode/feat-<slug>`. Do not open additional PRs.
6. **No nested fallbacks.** Dispatch `kilo-fallback`/`openrouter-fallback` for failed **children** only — never replace the coder itself, never dispatch one fallback from another.
7. **Context discipline.** Every ~10 tool iterations, compact state to 3 bullets (current stage, files touched, blockers). Discard old RED/GREEN raw outputs once `code-review` APPROVES the stage; keep only concise gate summaries.
8. **Stabilization is bounded.** PR stabilization loop runs **at most 3 iterations**. On exhaustion, return `BLOCKED: STABILIZATION_EXHAUSTED` with the remaining fix-now items.
9. **Cross-ticket review comments are not yours to fix.** If `pr-stabilize-watch.sh` returns comments whose fix would touch files in another ticket's branch, return `BLOCKED: CROSS_TICKET_REVIEW` so the develop orchestrator routes it to the feature coder's remediation flow.
10. **Issue state transitions** (`state:in-progress` on entry, `state:ready-for-ticket-review` when the sub-PR opens) are yours; use `scripts/issue-state-transition.sh` via a delegated `developer` Task.
11. **You are the auto-started GUI session for this worktree.** The develop orchestrator does **not** dispatch you via `task` (cwd inheritance would put you on `develop`); you are reached via `session_kickoff` or via any user message. You must self-bootstrap from your **most recent user message** + the branch + GitHub. The kickoff message is the contract.
12. **Verification backend is containerized only.** Every RED/GREEN/final-gate test run goes through `docker-compose.test.yml` via `sandbox_run_test` from `plugins/sandbox.js` (sandbox exec on opencode-server, or direct `docker compose` on local dev) — **never** host-local suite setup. `compose_test_file: none` after `probe_and_create` → `ENV_BLOCKED` with `recommended_env_fix: add docker-compose.test.yml from templates/project-stub/`. No host npm/pip installs to "get tests running".
13. **Never run `git merge` without `scripts/assert-merge-cwd.sh`.** If a stage ever needs to merge a ref inside your ticket worktree, source `scripts/assert-merge-cwd.sh` immediately before the `git merge` line with `ASSERT_MERGE_CWD=<worktree abs path>`, `ASSERT_MERGE_BRANCH=<expected_branch>`, `ASSERT_MERGE_REF=origin/<feature_branch>`, `ASSERT_BRANCH_CONTEXT=ticket-worktree`, `ASSERT_REPO=<OWNER/REPO>`. The script enforces no PR exists with `head=<feature_branch>, base=develop`. On any `BLOCKED: *` exit, surface the BLOCKED line verbatim and stop. This is the develop-pollution guard (2026-09-02 incident); ticket worktrees do not normally merge during execution but the rule is here as a tripwire.

## §0 Bootstrap (must run before any stage work)

Runs on **any** first message: the injected kickoff pointer (via `session_kickoff`), a user "begin", or a resume after a server restart. **Read your most recent user message first — that message is the kickoff pointer. Treat it as authoritative.** It contains `execution_mode`, the issue url (`OWNER/REPO#<n>`), the feature slug, `expected_branch`, `worktree`, and `develop_session_id` (the develop orchestrator's session id, used by §6c for the terminal `session_notify` injection), plus the inline "Load skill ticket-lifecycle and begin" instruction.

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

### §0.1 Kickoff pointer contract

Use the kickoff message inline as the bootstrap contract. Do not expect any on-disk bootstrap artifact. When you need to confirm `expected_branch`, do it from branch state (`git rev-parse` via delegated `developer`), not from worktree metadata.

### §0.2 GitHub reconstruction (primary fallback — delegated `developer` Task)

If your most recent user message is missing or unparseable, **delegate ONE `developer` Task** with `load: minimal` to reconstruct the kickoff context from the branch + GitHub. This is the primary resilience path — the durable sources of truth are GitHub and branch state.

````text
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
````

Use the returned JSON as your kickoff pointer. If `develop_session_id` is `null`, the durable `ticket_report:` issue comment is the only wake channel (no `session_notify` target); record this and continue — §6c handles the missing-id case.

### §0.3 Verification backend (silent — delegated to worktree-sandbox)

After the brief is in hand, delegate ONE `worktree-sandbox` Task with `load: minimal` and `mode: probe_and_create`. The plugin (`plugins/sandbox.js`) reports `sandbox_id`, `backend` (`sandbox` | `docker`), `compose_test_file`, `build_seconds`, `warm_run_seconds`. **Hard rule:** `compose_test_file: none` after `probe_and_create` → stop with `BLOCKED: ENV_BLOCKED` + `recommended_env_fix: "Add docker-compose.test.yml (test-suite-sufficient) from templates/project-stub/ at the impl repo root"`. **Never** fall back to host-local test runners — do not install npm/pip/etc. on the host to "get tests running".

```text
Task worktree-sandbox load: minimal
mode: probe_and_create
cwd: <worktree absolute path>
sandbox_id: <id>            # optional; if absent, agent derives from worktree basename (DNS-label)
```

The returned `sandbox_id` + `compose_test_file` are the canonical handles every later dispatch uses. Compose-test-backend bring-up is no longer a developer concern — it lives in the plugin. `worktree-sandbox` is entry/exit only; it does not run per-stage tests.

Subsequent test execution (test-writer RED, developer GREEN, code-review per-stage focused checks, final-gate full suite) uses the same backend. `opencode-task-yaml` `test_commands` execute **inside/through** the compose test service via the plugin tool **`sandbox_run_test`** (registered by `plugins/sandbox.js`). Stage implementers and `code-review` call `sandbox_run_test` **directly** from the plugin — they do not write `docker compose` invocations themselves, and they do not route through `worktree-sandbox` for per-stage runs. The `docker-sandbox` skill remains the canonical Sysbox-vs-direct-Docker reference for the plugin's fallback logic, not for agents writing bash.

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

   `state:in-progress` automatically removes `verified` and adds `unverified` — the verification gate will re-arm when this ticket reaches `state:ready-for-ticket-review` again. The swap is enforced centrally in `scripts/issue-state-transition.sh` on **every** state transition; the only inline writer of `verified` is `scripts/issue-verified-transition.sh`, which the coder calls on APPROVED (final-gate step §3 below).

### §0.6 Handshake ack (mandatory, async, do not block)

The kickoff message from the orchestrator carries a return_target
block naming the orchestrator's sessionID. Before the first RED
stage (and as the very first user-visible action after the kickoff
is admitted), send a one-line ack back to the orchestrator:

session_notify({
sessionID: <return_target.sessionID from kickoff>,
directory: "",
agent: "coder",
message: "ack: ticket-lifecycle §0 bootstrap, return channel OK, durable channel OK. Working on stage 1."
})

The ack is admitted on HTTP 204, same as any /prompt_async inject.
Do not wait for a reply from the orchestrator — the ack is a
one-shot registration, not a conversation opener. Move on to stage 1.

If session_notify errors with "requires exactly one of sessionID or
directory", the kickoff message is malformed: re-derive the
return_target from the GitHub issue (orchestrator's most recent
ticket_report: comment on the issue, or the
orchestrator_session_id field on the issue body if present) and
retry once. If still failing, fall back to durable_channel only
and post a status comment on the issue explaining the ack failure.

Rationale: the 2026-09-07 ticket 259 stall was caused by a
sessionID-less resume kickoff where the coder had no return
channel and sat idle after the prior orchestrator's session went
away. The handshake ack makes the channel observable: the
orchestrator can detect a live but silent coder via
handshake_acked: false in its lifecycle log and nudge or
escalate, instead of waiting indefinitely on a one-way
ticket_report: poll.

## Required inputs (truth sources)

You are not dispatched via `task` — the develop orchestrator reaches you via the kickoff pointer. The three sources of truth, in priority order:

1. **Your most recent user message** — the kickoff pointer delivered by `session_kickoff`. Treat it as authoritative; it is the contract. Short by design — do not require it to contain the full payload.
2. **GitHub issue + worktree branch** — `opencode-task-yaml` body, `feature:<slug>` label, `state:*` labels, `Blocked by:` section, branch name shape. This is the durable source; it backs §0.2 reconstruction when the kickoff message is missing.
3. **Worktree branch + GitHub reconstruction** (delegated `developer` Task) — the fallback path for a missing/empty kickoff message.

If the kickoff message is missing but the branch + repo reconstruct cleanly, proceed (reconstruction is the resilience path). Only bounce out on `BLOCKED: CHECKOUT_CONTRACT_FAILED`.

## Procedure

### 1. Silent preflight

Already done in §0.3 — compose-backend resolved + built + warmed via the `worktree-sandbox` agent. Skip if you trust that report. If you re-run for any reason, dispatch ONE `worktree-sandbox` Task (`mode: probe_and_create`) silently. Surface only if `probe_and_create` returns `blocker_code` after one build+warm pass.

### 2. Loop every `opencode_meta.stages[]` entry

For each `stage` in `opencode_meta.stages` (in order, **starting from `last_approved_stage_index + 1`** on resume), enforce one committed vertical slice before advancing:

0. **Stage contract** — require `stage.tdd.test_first: true` (or the accepted flat compatibility flag), `stage.test_commit_message`, `stage.commit_message`, acceptance mapping, and test commands. Capture the stage base SHA and require a clean worktree before RED.
1. **RED test commit** — dispatch `test-writer` with `execution_mode: test_first_red`, the stage scope, `test_commit_message`, issue number, expected branch, and compose handles. The test writer writes exactly one behavior test, runs it through `sandbox_run_test`, and proves the intended failure. It then stages only test/test-support files and creates the test-only RED commit. Require `red_phase`, `test_commit.sha`, `test_commit.files`, and `worktree_clean: true`; missing evidence or a mixed RED commit is `BLOCKED: TEST_COMMIT_INVALID`.
2. **GREEN implementation commit** — dispatch the stage `Owner` (developer | frontend-dev | ux-dev) with `execution_mode: test_first_green`, the complete RED report, and `test_commit.sha`. The owner must verify that HEAD is the RED commit, implement production changes only, run the same compose-backed test, stage only production files, and create the implementation-only GREEN commit using `stage.commit_message` plus `Refs: #<issue_number>`. Require `green_phase`, `implementation_commit.sha`, `implementation_commit.files`, and `worktree_clean: true`; test changes in GREEN are `BLOCKED: IMPLEMENTATION_COMMIT_MIXED`.
3. **`code-review` (ticket mode)** — dispatch `code-review` with `load: full`, the stage's `diff_base`, `test_commit`, `implementation_commit`, any `test_amendments`, `files_changed`, `red_phase` + `green_phase` evidence, and the issue's acceptance mapping. The reviewer must validate commit order, test-only RED scope, production-only GREEN scope, clean worktree, test quality, acceptance coverage, and RED/GREEN replay. **No full regression per stage.** `code-review` reuses the built images via `sandbox_run_test`; destroys the sandbox after `APPROVED` or `ENV_BLOCKED`, keeps alive on `BLOCKED`.
   - On `APPROVED` → record `{ stage_id, red_commit, implementation_commit, test_amendments }`, compact context, and retain the commit refs.
   - On `NEEDS_CHANGES` → classify the finding. Test-quality changes go through a new `test-writer` `execution_mode: test_amendment` task and a separate test-only amendment commit; behavior changes then go through a new GREEN implementation-only commit. Never fix both sides in one commit. Re-run `code-review` with the complete commit history (max 2 stage retries).
   - On `BLOCKED` → return `BLOCKED` from the ticket (cross-cutting blocker).
4. After the final stage → run `StageAcceptanceChecks` end-to-end. Do not create a catch-up mixed commit; every stage output must already be committed and reviewed before the final gate.

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

#### 3.1 `final_gate_post` sub-procedure (mandatory, atomic)

The final gate has exactly one success shape:

```yaml
final_gate_post:
  posted_comment_id: <int>           # numeric GitHub comment id from gh issue view back-resolve
  label_added: true                  # issue-verified-transition wrapper exited 0
  evidence_url: <code_review_gate: comment html_url>
```

Steps in order; no early exit until ALL THREE succeed:

1. Dispatch `code-review` (`load: full`) for the **final** `all_stages: true` gate (full suite via compose backend).
2. On `APPROVED`, dispatch ONE delegated `developer` Task (`load: minimal`) that performs steps 2a–2c atomically:
   a. Post the `code_review_gate:` comment via `gh issue comment`, including `all_stages: true`, `verdict: APPROVED`, and the complete `stage_commit_history` (`stage_id`, `red_commit`, `implementation_commit`, and `test_amendments`) for every approved stage. **Note:** `gh issue comment … --json id` does not exist in the CLI; capture the comment id by back-resolving from the issue's comments list — `gh issue view <n> --repo <repo> --comments --json comments -q '[.comments[]|select(.body|startswith("code_review_gate:"))]|last|.id'` (the coder-as-author identity is implicit because you are operating inside a coder session; the env var `OPENCODE_CODER_AUTHOR` is the strict-precondition contract enforced by `scripts/issue-state-transition.sh`, not by this capture shape).
   b. Run `scripts/issue-verified-transition.sh "<repo>" "<issue_number>" verified` from the same delegated Task. The wrapper is the **only** writer of `verified` — do **not** run `gh issue edit --add-label verified` inline, that leaves a stale `unverified` and creates the duplicate pair.
   c. Verify via `gh issue view <n> --repo <repo> --json labels -q '.labels[].name' | grep -qx verified` inside the same delegated Task.
3. Return `final_gate_post: { posted_comment_id, label_added, evidence_url }` from the delegated Task and record it in the terminal `ticket_report:` (§6a).
4. Anything else (`NEEDS_CHANGES`, missing comment, missing label, wrapper exit ≠ 0) → `BLOCKED: FINAL_GATE_NOT_POSTED`. Do **not** proceed to §4.

Resume-safe idempotence (§0.4 step 2) reads the most recent `code_review_gate:` comment to find `last_approved_stage_index`. The new exact-value matching requires `all_stages: true` — a per-stage comment with `all_stages: false` must **not** match the final-gate selector. Do not weaken the resume check to "contains all_stages: true anywhere".

#### 3.2 Local CodeRabbit pre-flight

1. Dispatch `code-review` once with `load: full`, `execution_mode: ticket_coderabbit_preflight`, the ticket worktree path, `base_branch: opencode/feat-<slug>`, and the per-stage code-review evidence. Scope: correctness, obvious bugs, and risky changes only (narrow rule set — narrow further if this and the PR-side feature gate keep producing duplicate noise).
   - On `PASS` → proceed to §4.
   - On `BLOCKED` → apply each behavior fix through the same protocol: test-only RED/amendment commit first, then production-only GREEN fix commit, then rerun the targeted test and pre-flight. Never combine the test and fix. Push the ticket branch and re-run the pre-flight before the sub-PR opens. Max 2 retries, then `BLOCKED: PREFLIGHT_EXHAUSTED`.
   - On `SKIPPED` (CLI/auth unavailable) → record `coderabbit_preflight: SKIPPED` in the ticket_report and proceed. The PR-side feature gate is the policy blocker; missing the pre-flight does not block the ticket terminal report.

### 4. Open the sub-PR

1. Push your branch: `git push -u origin <expected_branch>` (delegated developer).
2. Open the sub-PR via `gh pr create --base opencode/feat-<slug> --head <expected_branch> --title "feat(<slug>): ticket <issue> — <title>" --body <auto-body>` (delegated developer).
3. Only after `final_gate_post` returned success (§3.1): `state:ready-for-ticket-review` on the issue via `scripts/issue-state-transition.sh` (the sub-PR is now open; the final gate + `verified` label already landed in §3).

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
      fix in-worktree with the TDD commit protocol (test-only RED/amendment commit → production-only GREEN implementation commit, behavior changes only),
      commit each phase separately with `Refs: #<issue_number>`, push branch
    loop back to next iter
```

### 6. Terminal report

Emit the terminal report (in-session, normal prose), **post the `ticket_report:` comment on the issue** (mandatory durable channel — same pattern as `code_review_gate:`), and best-effort call `session_notify` directly to inject the terminal report into the develop orchestrator before stopping. **`session_notify` is a direct plugin tool you hold.**

#### 6.0 `human_review_handoff/v1` readiness contract (mandatory on READY)

`READY_FOR_HUMAN_REVIEW` is valid only when the durable `ticket_report:` contains a complete `human_review_handoff/v1` block. The wake channel (`session_notify`) is transport only; the durable issue comment is the contract the develop orchestrator reads before it surfaces the PR to the human.

Required READY fields:

- `review_handoff_contract.name: human_review_handoff`
- `review_handoff_contract.version: 1`
- `issue_url`
- `pr_url`
- `notify_status`
- `review_handoff.what_was_done`
- `review_handoff.wrap_up`
- `review_handoff.test_report_count`
- `review_handoff.coderabbit_issues_found`
- `review_handoff.coderabbit_issues_solved`
- `review_handoff.local_pr_issues_found`
- `review_handoff.local_pr_issues_solved`
- `review_handoff.fix_now_issues_found`
- `review_handoff.fix_now_issues_resolved`
- `final_gate_post.posted_comment_id`
- `final_gate_post.label_added: true`

READY invariants:

- every count field is an integer `>= 0`
- `review_handoff.test_report_count >= 1`
- `review_handoff.coderabbit_issues_solved <= review_handoff.coderabbit_issues_found`
- `review_handoff.local_pr_issues_solved <= review_handoff.local_pr_issues_found`
- `review_handoff.fix_now_issues_resolved <= review_handoff.fix_now_issues_found`
- `review_handoff.fix_now_issues_found == review_handoff.coderabbit_issues_found + review_handoff.local_pr_issues_found`
- `review_handoff.fix_now_issues_resolved == review_handoff.coderabbit_issues_solved + review_handoff.local_pr_issues_solved`
- if `review_handoff.coderabbit_issues_found > 0`, then `review_handoff.coderabbit_issues_solved > 0`
- if `review_handoff.local_pr_issues_found > 0`, then `review_handoff.local_pr_issues_solved > 0`
- for READY, `review_handoff.fix_now_issues_found == review_handoff.fix_now_issues_resolved`

If the durable report is missing any required field, or the counts do not reconcile, do **not** emit READY. Return `BLOCKED` instead so the develop orchestrator can stop with `REVIEW_HANDOFF_INCOMPLETE` or `REVIEW_HANDOFF_INCONSISTENT` rather than surfacing an ambiguous PR.

#### §0-completion: tear down the verification backend

Before stopping, lifecycle-aware destroy of the compose test backend. Dispatch ONE `worktree-sandbox` Task with `load: minimal`:

```text
Task worktree-sandbox load: minimal
mode: teardown
sandbox_id: <from §0.3 report>
compose_test_file: <from §0.3 report>   # optional; plugin runs docker compose down on direct-Docker backend
```

The agent calls `sandbox_status` (confirm idle) then `sandbox_destroy` from the plugin (unexpose first by default). `worktree-sandbox` is the only owner of the **ticket terminal teardown**; `code-review` still owns its own destroy on `APPROVED` / `ENV_BLOCKED` per `docker-sandbox` §5 (the per-stage and final-gate path is unchanged).

#### 6a. Post the `ticket_report:` comment (mandatory)

```bash
gh issue comment "<issue_number>" --repo "<repo>" --body "$(cat <<'EOF'
ticket_report:
  status: READY_FOR_HUMAN_REVIEW | BLOCKED
  issue: <repo>#<issue_number>
  issue_url: <issue_url>
  prd_url: <url>                       # optional when known
  pr_url: <url>                        # READY only
  ci_state: pass|pending|fail          # READY only
  stages_completed: <count>
  stage_commit_history:
    - stage_id: <stage id>
      red_commit: <sha>
      implementation_commit: <sha>
      test_amendments: [<sha>]
  coderabbit_preflight: PASS | SKIPPED | BLOCKED   # see §3
  coderabbit_preflight_skip_reason: <reason>       # SKIPPED only
  blocker_code: <code>                 # BLOCKED only
  reason: <one-line>                   # BLOCKED only
  next_action: <what the develop orchestrator should do>
  notify_status: admitted|failed|<reason>   # see §6c
  review_handoff_contract:
    name: human_review_handoff
    version: 1
  review_handoff:
    what_was_done: <concise summary of ticket work completed>
    wrap_up: <concise wrap-up for the human reviewer>
    test_report_count: <int>
    coderabbit_issues_found: <int>
    coderabbit_issues_solved: <int>
    local_pr_issues_found: <int>
    local_pr_issues_solved: <int>
    fix_now_issues_found: <int>
    fix_now_issues_resolved: <int>
  final_gate_post:
    posted_comment_id: <int>           # from §3.1 step 2a
    label_added: true                  # from §3.1 step 2c
EOF
)"
```

The develop orchestrator's `dev-loop-watch.sh` parses `ticket_report:` comments to surface state and detect out-of-band GitHub-UI merges; the poller (`scripts/dev-loop-poller.sh`) also diffs them to wake the develop orchestrator when it is idle. Without this comment, the develop orchestrator stays paused and the watch/poller cannot detect the terminal state.

#### 6b. Block shape

Exactly one of:

```yaml
READY_FOR_HUMAN_REVIEW:
  issue_number: <n>
  issue_url: <issue_url>
  prd_url: <url or null>
  pr_url: <url>
  ci_state: pass|pending
  evidence: <pr-stabilize-watch evidence line>
  comment_resolutions: [{ author, classification, action }]
  stages_completed: <count>
  stage_commit_history:
    - stage_id: <stage id>
      red_commit: <sha>
      implementation_commit: <sha>
      test_amendments: [<sha>]
  coderabbit_preflight: PASS | SKIPPED
  review_handoff_contract:
    name: human_review_handoff
    version: 1
  review_handoff:
    what_was_done: <concise summary of ticket work completed>
    wrap_up: <concise wrap-up for the human reviewer>
    test_report_count: <int>
    coderabbit_issues_found: <int>
    coderabbit_issues_solved: <int>
    local_pr_issues_found: <int>
    local_pr_issues_solved: <int>
    fix_now_issues_found: <int>
    fix_now_issues_resolved: <int>
  awaiting_human_notes: <optional list of WIP/hold comments>
  next_action_for_parent: "validate human_review_handoff/v1, present the standard review table, then merge sub-PR into opencode/feat-<slug> on human approval"

BLOCKED:
  blocker_code: ENV_BLOCKED | STAGE_STUCK | STABILIZATION_EXHAUSTED | CROSS_TICKET_REVIEW | CHECKOUT_CONTRACT_FAILED | SKILL_UNAVAILABLE | FALLBACK_EXHAUSTED | PREFLIGHT_EXHAUSTED | HANDSHAKE_PUSH_FAILED | HANDSHAKE_FEATURE_BRANCH_CREATE_FAILED | TICKET_NOT_FORKED_FROM_FEATURE | REVIEW_HANDOFF_INCOMPLETE | REVIEW_HANDOFF_INCONSISTENT
  reason: <one-line>
  partial_evidence:
    stages_completed: <count>
    last_ci_state: pass|fail|pending
    last_pr_url: <url if open>
    failing_checks: [<names>]
    fix_now_outstanding: <count>
  recommended_helper_request: <one concrete request>
```

#### 6c. Best-effort wake via `session_notify` (direct call)

The terminal ticket_report: comment is the MANDATORY durable channel
(no change). The session_notify injection is the FAST channel. By
the time the coder reaches §6, it has already completed the §0.6
handshake ack, so it knows the orchestrator's sessionID. Reuse the
same return_target.sessionID here. If session_notify errors
session_not_found, the durable ticket_report: comment is the fallback
and the poller will wake the orchestrator within one poll interval.
Do not retry the inject; do not poll GitHub from this session; just
post the comment and end the turn.

Use a compact wake message that still carries the contract marker:

```text
message = "ticket_report: <repo>#<n> | status: READY_FOR_HUMAN_REVIEW | contract: human_review_handoff/v1 | pr: <url> | issue: <issue_url> | tests: <int> | coderabbit_found: <int> | coderabbit_solved: <int> | local_pr_found: <int> | local_pr_solved: <int> | fix_now_found: <int> | fix_now_resolved: <int> | stages: <count>"
# or, for BLOCKED:
message = "ticket_report: <repo>#<n> | status: BLOCKED | contract: human_review_handoff/v1 | blocker: <code> | reason: <one-line>"
```

The `ticket_report:` comment is the **mandatory** durable channel. `session_notify` is best-effort; its failure is recorded in the comment but never blocks the terminal report. **A failed wake is never silent:** when `notify_status` is anything other than `admitted`, end your final in-session report with this user instruction (the coder session is a GUI session — the user reads it):

```text
Automation wake failed (<notify_status>). The ticket_report: comment is posted on <repo>#<n>.
If the develop orchestrator has not merged the sub-PR within ~2 poll intervals (~4 min),
send any message to the develop orchestrator session — it runs dev-loop-watch.sh first and
will pick up the report from there.
```

When `notify_status` is `develop_session_id_stale` (the `session_notify` envelope returned `error: "session_not_found"`, `status == 404`, or `blocker_code: "SESSION_NOT_FOUND"`), also emit the **`session-notify-fallback` markdown block** (see `skills/orchestrate/session-notify-fallback.md`) so the operator can paste one curl (or `gh issue comment` one-liner) to forward the wake immediately. Emit the block only on the `SESSION_NOT_FOUND`-shape failures above — generic `SESSION_API_FAILED` is not a fallback trigger. Do not append a second copy on retry; the block is one-shot.

Emit the terminal report and stop. The implementer Hard Rules' post-completion guard now fires — any subsequent user message is answered with: "Task complete. Switch to the `orchestrate` agent to continue."

## Code-review grading gate

Per-stage `code-review` (focused): APPROVED requires non-missing criterion coverage, manual criteria with evidence or accepted deviation, security resolved, complete report, and a valid committed pair: test-only RED commit before production-only GREEN commit, clean worktree, same test RED then GREEN, and separately listed test amendments. Empty/malformed/step-limited or mixed commit scope = `BLOCKED`; retry once with `load: full`, then senior-dev escalation.

Final `all_stages: true` gate (before `state:ready-for-ticket-review`): same grading, plus every stage has a valid committed pair, the full-suite compose test run is green, and `StageAcceptanceChecks` passed. Empty/malformed/step-limited or missing stage commit history → retry once with `load: full`, then senior-dev escalation.

## Anti-loop

- Do not emit the same verbal statement twice. Move after the first intent statement.
- Do not re-announce file writes or commands.
- After a stage's `code-review` APPROVED, compact: discard raw RED/GREEN outputs; retain only the verdict + RED/GREEN commit refs and amendment refs.

## See also

- `agents/coder.md` — host posture + skill/task allow-list.
- `agents/developer.md`, `agents/frontend-dev.md`, `agents/ux-dev.md`, `agents/test-writer.md`, `agents/code-review.md` — stage executors.
- `agents/senior-dev.md` + `skills/senior-dev/SKILL.md` — escalation_fix returns `HANDOFF_TO_DEVELOPER` to resume the wrapping coder.
- `agents/kilo-fallback.md`, `agents/openrouter-fallback.md` — provider fallback for failed children (never replaces the coder).
- `skills/code-review/SKILL.md` — the verification contract: per-stage focused checks, final-gate full suite, local CodeRabbit pre-flight (`ticket_coderabbit_preflight`).
- `skills/docker-sandbox/SKILL.md` — `sandbox exec` vs direct compose matrix + lifecycle-aware destroy contract (referenced by `plugins/sandbox.js`, not by agent bash).
- `skills/worktree-sandbox/SKILL.md` — the subagent that owns §0.3 / §0-completion. Mode matrix + plugin-tool reference.
- `plugins/sandbox.js` — the 8 fine-grained plugin tools (`sandbox_probe` / `env_copy` / `sandbox_create` / `sandbox_build` / `sandbox_warm` / `sandbox_run_test` / `sandbox_status` / `sandbox_destroy`).
- `scripts/issue-state-transition.sh`, `scripts/pr-stabilize-watch.sh`, `scripts/dev-loop-watch.sh`, `scripts/checkout-contract.sh` — moved lib scripts.
- `plugins/worktree.js` — `worktree_create_ticket` is the sibling tool that creates this worktree.
- `plugins/session-manager.js` — `session_notify` is the plugin tool you call directly for the §6c terminal wake injection.
- `skills/orchestrate/SKILL.md` — the wrapping develop orchestrator.
