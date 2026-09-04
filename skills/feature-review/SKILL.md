---
name: feature-review
description: "Bounded feature-mode verification + sign-off contract loaded by the `coder` primary agent in the feature worktree after all ticket sub-PRs merge into `opencode/feat-<slug>`. Sign-off duty migrated from the deleted architect review skill."
modelTier: "fast"
roleReminder: "Loaded by the `coder` agent in the feature worktree after all ticket sub-PRs merge into `opencode/feat-<slug>`. Sign-off duty migrated from the deleted architect review skill."
---

> You are operating inside a **coder** session that was kicked into the feature worktree (`opencode/feat-<slug>`) by the develop orchestrator after the last ticket sub-PR merged. The ticket inner loop has already finished for every ticket in this feature (each ticket ran its own local CodeRabbit pre-flight inside its coder session) — you own the feature-mode verification: full test suite + e2e via the compose backend, acceptance replay, the PR-side CodeRabbit gate (medium/hard), difficulty gates, docs, `state:ready-for-feature-review` on every ticket (the final coder-set label), the feature PR, bounded stabilization, and one terminal `feature_report:` (or `BLOCKED: FEATURE_REMEDIATION` with `remediation:` issues). The develop orchestrator sets `state:done` after human final review and merges the feature PR — the spec `feature-complete` skill later verifies + closes; impl feature PR merge happens in the orchestrator on your READY report + human approval — the orchestrator never re-verifies your evidence.

## Hard rules

1. **Stay on `opencode/feat-<slug>`.** Do not switch branches, do not push to `develop` or any ticket branch — only to the feat branch and its feature PR.
2. **Verifier ≠ implementer.** `code-review` grades, `developer` (delegated) fixes. Never have the same actor both write and grade the same change.
3. **One terminal report.** Either `READY_FOR_HUMAN_REVIEW` (pr_url + full-suite evidence + CodeRabbit verdict + docs paths) or `BLOCKED` (`BLOCKED: FEATURE_REMEDIATION` with issue numbers, or `CHECKOUT_CONTRACT_FAILED` / `ENV_BLOCKED` / `STABILIZATION_EXHAUSTED`). Do not hand off mid-feature.
4. **No nested fallbacks.** Dispatch `kilo-fallback`/`openrouter-fallback` for failed **children** only — never replace the coder itself, never dispatch one fallback from another.
5. **No worktree management.** Never call `worktree-manager` or any `worktree_*` tool; never create/switch/delete branches; never `git push origin --delete` — delegated `developer` is the only branch-deleting actor.
6. **Stabilization is bounded.** Feature PR stabilization loop runs **at most 3 iterations**. On exhaustion, return `BLOCKED: STABILIZATION_EXHAUSTED`.
7. **Verification backend is containerized only.** Every full-suite / e2e / final-gate run goes through `docker-compose.test.yml` via `sandbox exec` (opencode-server) or direct `docker compose` (local dev) — **never** host-local suite setup. `compose_test_file: none` → `BLOCKED: ENV_BLOCKED` with `recommended_env_fix`.
8. **Sandbox lifecycle.** `code-review` destroys the sandbox after `APPROVED` or `ENV_BLOCKED`, keeps it alive on `BLOCKED` for developer retry.
9. **Skill load failure is fatal.** `SKILL_UNAVAILABLE: <skill>` halts the feature review — never substitute implementer output for a missing required skill.
10. **Context discipline.** Every ~10 tool iterations, compact state to 3 bullets (current step, files touched, blockers). Discard old per-stage outputs after the final `code-review` APPROVES the full-suite gate; keep only concise gate summaries.

## §0 Bootstrap (must run before any verification work)

Runs on **any** first message: the injected kickoff pointer, a user `begin`, or a resume after a server restart. The pointer is a short by design; a truncated message must not stall you. The **coder** agent has `bash: false`; reading the kickoff pointer uses the read tool, every shell invocation is delegated to ONE `developer` Task with `load: minimal`.

### §0.0 Handshake (push the feature branch from this worktree — runs before §0.1 / §0.2)

The feature coder's cwd IS the feature worktree directory. You own the handshake push for `opencode/feat-<slug>`: ensure it exists remotely, push it from your worktree cwd, and verify the branch is on the remote. **worktree-manager does not push** (local-only `/experimental/worktree` plumbing), and the orchestrator never pushes a branch it didn't delete. Delegate ONE `developer load: minimal` Task from the worktree cwd. The ticket-branch push (step 5 of `ticket-lifecycle` §0.0) is **skipped** in feature mode — your worktree branch IS the feature branch.

```text
Task developer load: minimal
Run the §0.0 Handshake push for the feature worktree.

cwd: <feature worktree absolute path>      # you ARE the feature worktree
repo_root: <impl_repo root>
feature_branch: opencode/feat-<slug>
expected_branch: opencode/feat-<slug>      # = feature_branch in feature mode

1. default_branch=$(gh repo view <OWNER>/<REPO> --json defaultBranchRef -q .defaultBranchRef.name)
2. git fetch origin <feature_branch> || true
3. if ! git rev-parse --verify "origin/<feature_branch>" >/dev/null 2>&1; then
     sha=$(gh api repos/<OWNER>/<REPO>/git/ref/heads/<default_branch> -q .object.sha)
     gh api -X POST repos/<OWNER>/<REPO>/git/refs \
       -f ref="refs/heads/<feature_branch>" -f sha="$sha"
     # 422 (already exists) is treated as success
   fi
4. git push -u origin <feature_branch>                  # BLOCKED: HANDSHAKE_PUSH_FAILED on failure (stderr verbatim)
5. [ "$(git rev-parse --abbrev-ref HEAD)" = "<expected_branch>" ] || { echo "BLOCKED: CHECKOUT_CONTRACT_FAILED"; exit 1; }
   git rev-parse --verify "origin/<expected_branch>" >/dev/null 2>&1 || { echo "BLOCKED: CHECKOUT_CONTRACT_FAILED"; exit 1; }
   git merge-base --is-ancestor "origin/<feature_branch>" HEAD || { echo "BLOCKED: TICKET_NOT_FORKED_FROM_FEATURE"; exit 1; }

Return JSON:
{
  "ok": true,
  "feature_branch": "opencode/feat-<slug>",
  "expected_branch": "opencode/feat-<slug>",
  "remote_feature_branch_created": true|false,
  "merge_base_ok": true
}
```

On any non-zero exit, surface the developer's `blocker_code` verbatim — do not retry from here.

### §0.1 Pointer resolution

The kickoff message names the feature slug, the feature branch `opencode/feat-<slug>`, and (optionally) the absolute feature worktree directory. Reconstruct anything missing:

```text
Task developer load: minimal
Reconstruct the feature-review kickoff pointer.

cwd: <feature worktree absolute path>          # you ARE the feature worktree
repo_root: <impl_repo root>
expected_branch: opencode/feat-<slug>

1. git rev-parse --is-inside-work-tree          # expect true
2. git rev-parse --abbrev-ref HEAD              # expect opencode/feat-<slug>
3. gh repo view --json nameWithOwner -q .nameWithOwner
4. gh issue list --repo <repo> -l "feature:<slug>" --state all -L 200 --json number,title,url,labels,state
5. for each feature:<slug> issue: gh issue view <n> --repo <repo> --json body,labels -q '{body: .body, labels: [.labels[].name]}'
6. gh pr list --repo <repo> --state merged --base opencode/feat-<slug> --json number,url,title,headRefName

Return JSON:
{
  "ok": true,
  "repo": "<OWNER/REPO>",
  "feature_slug": "<slug>",
  "feature_branch": "opencode/feat-<slug>",
  "expected_branch": "opencode/feat-<slug>",
  "issues": [{ "number": <n>, "title": <t>, "labels": [...], "state": "open|closed" }],
  "merged_sub_prs": [{ "number": <n>, "url": <u>, "title": <t> }]
}
```

### §0.2 Checkout contract

Mismatch → `BLOCKED: CHECKOUT_CONTRACT_FAILED` (the only bounce-out from §0).

```bash
git rev-parse --is-inside-work-tree              # expect true
git rev-parse --abbrev-ref HEAD                  # expect opencode/feat-<slug>
git merge-base --is-ancestor origin/opencode/feat-<slug> HEAD   # expect success (feat branch contains its own history)
```

### §0.3 Verification backend (silent — delegated to worktree-sandbox)

After the pointer is in hand, delegate ONE `worktree-sandbox` Task with `load: minimal` and `mode: probe_and_create`. The plugin (`plugins/sandbox.js`) reports `sandbox_id`, `backend` (`sandbox` | `docker`), `compose_test_file`, `build_seconds`, `warm_run_seconds`. **Hard rule:** `compose_test_file: none` after `probe_and_create` → stop with `BLOCKED: ENV_BLOCKED` + `recommended_env_fix`. **Never** fall back to host-local test runners.

```text
Task worktree-sandbox load: minimal
mode: probe_and_create
cwd: <feature worktree absolute path>
sandbox_id: <id>            # optional; if absent, agent derives from worktree basename (DNS-label)
```

The returned `sandbox_id` + `compose_test_file` are the canonical handles every later dispatch uses. Compose-test-backend bring-up is no longer a developer concern — it lives in the plugin. `worktree-sandbox` is entry/exit only; it does not run per-stage tests.

Subsequent full-suite / e2e / per-stage code-review runs use the same backend via the plugin tool **`sandbox_run_test`** (registered by `plugins/sandbox.js`). Stage implementers and `code-review` call `sandbox_run_test` **directly** from the plugin — they do not write `docker compose` invocations themselves, and they do not route through `worktree-sandbox` for per-suite runs. The `docker-sandbox` skill remains the canonical Sysbox-vs-direct-Docker reference for the plugin's fallback logic, not for agents writing bash.

### §0.4 Reconstruct feature state

For each `feature:<slug>` issue, parse the `opencode-task-yaml` block from the issue body. Roll up acceptance criteria from every ticket. Build the per-ticket `code_review_gate:` summary from issue comments (last comment per ticket carrying `code_review_gate: ... all_stages: true ... verdict: APPROVED ... verified`). Every ticket must show:

- `state:ready-for-ticket-review` (or `state:ticket-reviewed` after sub-PR merge) and `verified`
- `code_review_gate: all_stages: true verdict: APPROVED`
- `merged_sub_prs` confirms each ticket's sub-PR is merged

Any missing → surface `BLOCKED: CHECKOUT_CONTRACT_FAILED` with the offending ticket(s) — do not proceed into the verification loop on a broken foundation.

## Required inputs (truth sources)

In priority order:

1. **Kickoff pointer** — feature slug, feat branch, feature worktree directory.
2. **GitHub issue bodies + comments** — `feature:<slug>` label, `opencode-task-yaml`, per-ticket `code_review_gate:` comments.
3. **Branch state** — `opencode/feat-<slug>` and its merged sub-PRs.

If the kickoff pointer is missing but the branch + GitHub reconstruct cleanly, proceed. Only bounce out on `BLOCKED: CHECKOUT_CONTRACT_FAILED`.

## Procedure

### 1. Feature-mode `code-review` (full suite)

Dispatch `code-review` (`load: full`) with the full diff vs `develop` (delegated `developer` to capture `git diff origin/develop...HEAD --stat` and the per-ticket merged-PR list), the rolled-up acceptance mapping (every ticket's acceptance criteria, every per-ticket `code_review_gate: APPROVED`), and the compose test backend handles from §0.3 (`sandbox_id`, `compose_test_file`). The feature-mode gate runs the **full regression, integration, and e2e** suite via the plugin tool **`sandbox_run_test`** (the per-stage focused gate already passed during each ticket's inner loop). `code-review` calls `sandbox_run_test` directly — `worktree-sandbox` is not in this path.

- On `APPROVED` → compact, retain only the verdict + commit refs + full-suite evidence summary. Continue.
- On `NEEDS_CHANGES` → fix in this feature worktree (TDD), re-run `code-review`. Max 2 retries, then `BLOCKED: FEATURE_REMEDIATION`.
- On `BLOCKED` (cross-cutting blocker) → return `BLOCKED` (cross-ticket / cross-cutting).
- `code-review` destroys the sandbox after `APPROVED` or `ENV_BLOCKED` (via the plugin `sandbox_destroy`), keeps alive on `BLOCKED`.

### 2. PR-side CodeRabbit gate (medium / hard only)

For **easy** → skip the PR-side gate (easy features skip it; each ticket already ran its local pre-flight inside its own coder session). For **medium** or **hard** → dispatch `code-review` once with `load: full`, `execution_mode: feature_coderabbit_gate`, the feature worktree path, `base_branch: develop`, aggregate files/commits, and the `code-review` evidence from step 1. This is the **PR-side policy gate** — style, regressions, cross-branch context, and policy (the run contract, severities, and report shape live in `skills/code-review/SKILL.md`). On `PASS` → continue. On `BLOCKED` → fix findings directly in this feature worktree (do not create `remediation:` tickets for CodeRabbit fixes); the PR-stabilization loop below owns the bounded fix flow. The develop orchestrator never dispatches CodeRabbit and never checks this verdict — `PASS` is reported in your terminal `feature_report:`.

### 3. Difficulty gates

- **easy** → none (the full-suite + acceptance evidence from step 1 completes the gate).
- **medium** → the `completion_summary: Merge-ready | Needs changes` field from the step-1 feature-mode `code-review` report is the medium gate. Merge-ready → continue; Needs changes → fix-now in this feature worktree, then continue.
- **hard** → dispatch `senior-dev` once with `execution_mode: scheduled_review`, the feature worktree path, the rolled-up acceptance + per-ticket `code_review_gate:` summaries, the CodeRabbit inventory, and the feature completion context. Senior-dev's `APPROVED` / `NEEDS_CHANGES` / `BLOCKED` feeds into the final report. Hard completes the bounded gate.

### 4. Documentation (before the PR opens)

1. Dispatch `document` with `load: full`, `execution_mode: feature_docs`, `feature_slug`, `doc_scope` (changelog required; guides/architecture per scope), the rolled-up acceptance mapping, and the CodeRabbit inventory. `document` returns changelog (required) plus optional guides/architecture content per `doc_scope`.
2. Dispatch `scribe` (`load: full`) to write the docs to the approved paths:
   - `docs/changelog/<YYYY-MM-DD>-<slug>.md` (required)
   - `docs/guides/<slug>.md` (when in scope)
   - `docs/architecture/<slug>.md` (when in scope)
3. Commit the docs on the feat branch via delegated `developer` (`load: minimal`) — `git add <docs paths>`, `git commit -m "docs(<slug>): changelog + guides", git push origin opencode/feat-<slug>`. Do **not** open a PR yet.

### 5. `state:ready-for-feature-review` on every ticket

For each `feature:<slug>` issue in this repo, dispatch a `developer` Task (`load: minimal`) to run:

```bash
bash "$OC/scripts/issue-state-transition.sh" "<repo>" "<issue_number>" state:ready-for-feature-review
```

`state:ready-for-feature-review` is the final coder-set label — the human-review gate for the integrated feature PR. The **develop orchestrator** sets `state:done` after human "all reviewed" (see `skills/orchestrate/SKILL.md` §8c-i). Issues **stay open** — close-at-merge is owned by spec `feature-complete`. Skip tickets already `state:ready-for-feature-review` or `state:done`.

### 6. Open the feature PR

Dispatch `developer` (`load: minimal`) to run `scripts/feature-finish-pr.sh <slug>`. Expect `pr-created` / `pr-exists`. On `skipped-*`, surface verbatim and stop. Capture `pr_url` for the terminal report.

### 7. PR stabilization loop (max 3 iterations)

```text
for iter in 1..3:
  ci = delegated developer load: minimal: gh pr checks <pr_url> --watch --json name,state,conclusion
  comments = delegated developer load: minimal: gh pr view <pr_url> --json comments,reviews,statusCheckRollup,mergeable

  fix_now = []
  for each ci failure or actionable review comment:
    if it spans files already merged across multiple tickets here:
      return BLOCKED: FEATURE_REMEDIATION [the offending comment + evidence]
    fix_now.append(item)

  if fix_now:
    for each item in fix_now:
      fix in this feature worktree with TDD (RED → GREEN, behavior changes only),
      commit "Refs: #<feature-parent-issue>", push branch
    loop back to next iter

  if no fix_now and ci green and no actionable comments:
    sealed report: stabilization_status: ready_for_human_merge,
    feedback_cutoff_at: <ISO timestamp now>, CI evidence, comment resolutions.
    break loop

  on iter == 3 with remaining fix_now:
    return BLOCKED: STABILIZATION_EXHAUSTED
```

After **any** stabilization fix, re-run step 1 (full-suite `code-review`) before continuing — the gate must reflect the post-fix tree. Bounded at 3 full-suite re-runs total.

### 8. Remediation path

When step 1, step 2, step 3, or step 7 surface unmet acceptance criteria that cannot be fixed directly in the feature worktree (e.g. cross-cutting defects, repeated `NEEDS_CHANGES`, gate `BLOCKED`):

1. Dispatch `to-tickets` (`load: full`) via `developer` to publish one or more `remediation:`-prefixed GitHub issues in the impl repo, linked as sub-issues of the PRD parent (`--parent-issue <prd_parent_issue_url>` from `docs/prd/<slug>.md` frontmatter in the spec sibling). Title prefix: `remediation: <short title>`. Labels: `feature:<slug>`, `prd-task`, `state:ready-for-agent`, `category:chore`. Body must include `opencode-task-yaml` with `stages[]` (same shape as the original ticket) and acceptance criteria.
2. Return `BLOCKED: FEATURE_REMEDIATION` with the remediation issue numbers. The develop orchestrator re-batches them through the normal ticket pipeline (new `coder` sessions, new ticket worktrees off `opencode/feat-<slug>`). When those remediation tickets merge, the develop orchestrator re-kicks this `feature-review` loop from §0.
3. Do not open `remediation:` tickets for CodeRabbit findings (those are direct fixes in this worktree) or for in-scope acceptance nits (those are also direct fixes).

### 9. Terminal report

Emit the terminal report (in-session, normal prose), **post the `feature_report:` comment on the PRD parent issue** (mandatory durable channel), and best-effort call `session_notify` directly to inject the terminal report into the develop orchestrator before stopping. **`session_notify` is a plugin tool you hold directly** — the `session-manager` subagent layer was removed.

#### §9-completion: tear down the verification backend

Before stopping, lifecycle-aware destroy of the compose test backend. Dispatch ONE `worktree-sandbox` Task with `load: minimal`:

```text
Task worktree-sandbox load: minimal
mode: teardown
sandbox_id: <from §0.3 report>
compose_test_file: <from §0.3 report>   # optional; plugin runs docker compose down on direct-Docker backend
```

The agent calls `sandbox_status` (confirm idle) then `sandbox_destroy` from the plugin (unexpose first by default). `worktree-sandbox` is the only owner of the **feature terminal teardown**; `code-review` still owns its own destroy on `APPROVED` / `ENV_BLOCKED` per `docker-sandbox` §5 (the full-suite and PR-side gate path is unchanged).

#### 9a. Post the `feature_report:` comment (mandatory)

```bash
gh issue comment "<prd_parent_number>" --repo "<spec_owner/spec_repo>" --body "$(cat <<'EOF'
feature_report:
  status: READY_FOR_HUMAN_REVIEW | BLOCKED
  feature: feature:<slug>
  implementation_repo: <OWNER/REPO>
  pr_url: <url>                          # READY only
  ci_state: pass|pending|fail             # READY only
  full_suite_evidence: <compose test invocation + pass line>
  coderabbit_verdict: PASS | SKIPPED | BLOCKED  # SKIPPED only when difficulty=easy
  docs_paths:
    - docs/changelog/<YYYY-MM-DD>-<slug>.md
    - <other paths written by scribe>
  tickets_state_feature_review: [<n1>, <n2>, ...]
  notify_status: admitted|failed|<reason>
EOF
)"
```

The develop orchestrator parses `feature_report:` comments to wake when the feature coder finishes. Without this comment, the orchestrator stays paused and the watch/poller cannot detect the terminal state.

#### 9b. Block shape

Exactly one of:

```yaml
READY_FOR_HUMAN_REVIEW:
  feature_slug: feature:<slug>
  pr_url: <url>
  ci_state: pass|pending
  full_suite_evidence: <compose test invocation + pass line>
  coderabbit_verdict: PASS | SKIPPED
  docs_paths: [...]
  tickets_state_feature_review: [<n1>, <n2>, ...]
  awaiting_human_notes: <optional list of WIP/hold comments>
  next_action_for_parent: "feature PR is open and ready for review; merge is the develop orchestrator's gate on 'all reviewed'"

BLOCKED:
  blocker_code: FEATURE_REMEDIATION | STABILIZATION_EXHAUSTED | ENV_BLOCKED | CHECKOUT_CONTRACT_FAILED | SKILL_UNAVAILABLE | HANDSHAKE_PUSH_FAILED | HANDSHAKE_FEATURE_BRANCH_CREATE_FAILED | TICKET_NOT_FORKED_FROM_FEATURE
  reason: <one-line>
  remediation_issues: [<n1>, <n2>, ...]      # FEATURE_REMEDIATION only
  partial_evidence:
    full_suite_state: pass|fail|pending
    failing_checks: [<names>]
    fix_now_outstanding: <count>
  recommended_helper_request: <one concrete request>
```

#### 9c. Best-effort wake via `session_notify` (direct call)

When the explicit `develop_session_id` is passed and `session_list` does not return it, `session_notify` returns `error: "session_not_found"` (hard stop — no silent create) — the durable `feature_report:` comment is the wake channel.

```text
message = "feature_report: feature:<slug> | status: READY_FOR_HUMAN_REVIEW | pr: <url> | ci: pass | tickets: <n>"
# or, for BLOCKED:
message = "feature_report: feature:<slug> | status: BLOCKED | blocker: <code> | reason: <one-line>"

# The develop_session_id is supplied in the feature coder kickoff message inline.
# If it's missing (kickoff truncated), pass `directory: <feature worktree dir>` instead —
# session_notify falls back to the newest no-parent session under that directory.
develop_target = { sessionID: <develop_session_id> } if develop_session_id else { directory: <feature worktree abs path> }

result = session_notify({
  ...develop_target,
  agent: "orchestrate",
  message,
})

if result.admitted == true: record notify_status: admitted
elif result.error == "session_not_found" and result.session_id == develop_session_id: record notify_status: develop_session_id_stale
elif result.status == 404: record notify_status: develop_session_id_stale
else:                       record notify_status: <error from result.error>
```

The `feature_report:` comment is the **mandatory** durable channel. `session_notify` is best-effort; its failure is recorded in the comment but never blocks the terminal report.

Emit the terminal report and stop. The coder agent Hard Rules' post-completion guard now fires — any subsequent user message is answered with: "Task complete. Switch to the `orchestrate` agent to continue."

## Anti-loop

- Do not emit the same verbal statement twice. Move after the first intent statement.
- Do not re-announce file writes or commands.
- After the feature-mode `code-review` APPROVES, compact: discard raw full-suite outputs; retain only verdict + commit refs + pass line.
- Do not re-run the same compose invocation without a code change.

## See also

- `agents/coder.md` — host posture + skill/task allow-list.
- `agents/developer.md`, `agents/frontend-dev.md`, `agents/ux-dev.md`, `agents/code-review.md`, `agents/senior-dev.md`, `agents/document.md`, `agents/scribe.md` — bounded children.
- `skills/ticket-lifecycle/SKILL.md` — the per-ticket inner loop whose `code_review_gate: all_stages: true APPROVED` outputs feed step 1's rolled-up acceptance.
- `skills/code-review/SKILL.md` — feature-mode verification contract: full suite, PR-side CodeRabbit gate (`feature_coderabbit_gate`), medium completion summary.
- `skills/docker-sandbox/SKILL.md` — `sandbox exec` vs direct compose matrix + lifecycle-aware destroy contract (referenced by `plugins/sandbox.js`, not by agent bash).
- `skills/worktree-sandbox/SKILL.md` — the subagent that owns §0.3 / §9-completion. Mode matrix + plugin-tool reference.
- `plugins/sandbox.js` — the 8 fine-grained plugin tools (`sandbox_probe` / `env_copy` / `sandbox_create` / `sandbox_build` / `sandbox_warm` / `sandbox_run_test` / `sandbox_status` / `sandbox_destroy`).
- `skills/to-tickets/SKILL.md` — `remediation:` issue publishing (`--parent-issue`).
- `scripts/issue-state-transition.sh`, `scripts/feature-finish-pr.sh`, `scripts/dev-loop-watch.sh` — shared lib scripts.
- `plugins/worktree.js` — `worktree_create_feature` is the sibling tool that creates this worktree.
- `plugins/session-manager.js` — `session_notify` is the plugin tool you call directly for the §9c terminal wake injection.
- `skills/orchestrate/SKILL.md` — the develop orchestrator that kicks this loop and merges the feature PR after "all reviewed".
