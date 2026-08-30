# Feature pipeline

Spec-driven path from PRD to merge. You choose only **architect** or **orchestrate**; open the right repo; for architect start with **`hi`** and pick the menu line shown. Shell bootstrap once (`setup-project`); after that, use OpenCode menus.

User overview (diagram + how-to): [../README.md#feature-flow-prd--sign-off](../README.md#feature-flow-prd--sign-off).

## Flow (what you do)

| Stage | Repo | Select | Your choice | Your job | This stage owns |
|-------|------|--------|-------------|----------|-----------------|
| Plan / PRD | **spec** (`*-spec`) | **architect** → `hi` | **1. Product feature / PRD — …** | Answer grill; **approve** `docs/prd/<slug>.md`; **approve** issue plans | Planning + per-work-repo handoffs only — not code, not PR polish |
| Build | **each work repo** | **orchestrate** on `develop` (new session) | Paste handoff / `feature:<slug>` | Wait until the feature PR exists | Develop orchestrator owns `opencode/feat-<slug>` + per-ticket worktrees; for each ticket it dispatches `worktree-manager create_ticket` with `kickoff_agent: "coder"` + `kickoff_message`. The plugin writes `<worktree-gitdir>/opencode-ticket-brief.json` and injects the kickoff into the auto-started GUI session via `session.promptAsync`. That auto-started session IS the **coder** primary agent (loading `ticket-lifecycle`), self-bootstraps from the brief file + GitHub, runs every `stages[]` entry + sub-PR stabilization, and posts one `ticket_report:` comment. |
| Review / verify / docs / PR | **same work repo, feature worktree** | **coder** (new session, kicked by orchestrator) → loads `feature-review` | (no menu — kicks the loop automatically) | Full-suite `code-review`, PR-side CodeRabbit (medium/hard), difficulty gates, docs, `state:done` accept, feature PR, bounded stabilization, one `feature_report:` | All PR readiness, ticket acceptance, and feature PR open + stabilization. |
| Final close | **spec** | **architect** → `hi` | **3. Feature complete — …** | After every work repo's feature coder loop completes and the develop orchestrator merged the feature PR | Verify-only close ceremony: confirms `state:done` + `verified` + MERGED, closes child issues + PRD parent + delivery record |

Shape:

```text
SPEC (start)          WORK REPO develop (build → feature coder → merge)         SPEC (finish)
architect / 1    →    develop orchestrator (develop branch)                    architect / 3
                        └─→ create_ticket + kickoff coder (per ticket, auto)
                             (auto-started GUI session IS the coder session;
                              brief file in <gitdir> + GitHub = source of truth)
                             (sub-PRs self-stabilize inside the coder session)
                        └─→ sub-PRs merge into opencode/feat-<slug>
                         →  coder / feature-review (in feature worktree)
                            full-suite code-review + PR-side CodeRabbit + docs
                            + state:done + feature PR + stabilization
                            → one feature_report: comment
                         →  orchestrator "all reviewed" → feature PR merge
PRD + handoffs        build → verify → docs → merge                            close + verify
```

### Develop-loop details (orchestrator → coder split)

- The **develop orchestrator** (`orchestrate`) is the *only* persistent session in the impl repo. It lives in the `develop` branch, owns all `worktree-manager` calls and remote-branch deletes, and never executes tickets itself. For each runnable ticket it dispatches `worktree-manager create_ticket` with `kickoff_agent: "coder"` + `kickoff_message`; the plugin writes `<worktree-gitdir>/opencode-ticket-brief.json` and injects the kickoff message into the auto-started GUI session via `session.promptAsync`. There is **no** `task`-tool ticket dispatch — subagents would inherit the develop cwd and `scripts/checkout-contract.sh --verify` would reject them.
- **Coder sessions** are auto-started GUI sessions for each ticket worktree, running the `coder` primary agent loading `ticket-lifecycle`. They own the full inner loop: §0 Bootstrap (read brief file via the read tool + reconstruct from GitHub) → silent preflight (delegated `developer` Task; resolves the compose test backend — `compose_test_file: none` → `BLOCKED: ENV_BLOCKED`) → every `stages[]` entry (test-writer RED → owner GREEN → per-stage focused code-review) → **final `all_stages: true` full-suite gate via `docker-compose.test.yml`** → **local CodeRabbit pre-flight (`ticket_coderabbit_preflight` — correctness/obvious-bugs/risky-changes scope; findings applied as fix-now suggestions before the sub-PR)** → sub-PR open → PR stabilization (max 3 iterations) → tear down the compose backend → one terminal `ticket_report:` comment (mandatory durable channel) + best-effort `session_notify` to `develop_session_id`. Mid-stage escalation to `senior-dev` is unattended (no operator confirmation — the only human gate is PR review); provider fallback (`kilo-fallback` → `openrouter-fallback`) is layered on top for failed children with a complete `fallback_context`.
- The develop orchestrator merges each sub-PR after human approval, deletes the ticket worktree + remote ticket branch, and re-batches until `scripts/dev-loop-batch.sh` exits 1. Then it **kicks the feature coder** in the feature worktree (same `coder` agent, loading `feature-review`).
- The **feature coder** (`feature-review`) owns the post-batch loop: §0 Bootstrap → full-suite + PR-side CodeRabbit gate + medium completion summary (all dispatched to `code-review`, `feature_coderabbit_gate` for the gate) → difficulty gates (medium → `code-review` completion summary; hard → `senior-dev scheduled_review`) → docs (`document` `feature_docs` + `scribe`) → `state:done` on every ticket → feature PR via `scripts/feature-finish-pr.sh` → bounded stabilization (max 3 iterations) → tear down the compose backend → one terminal `feature_report:` comment on the PRD parent (mandatory durable channel) + best-effort `session_notify` to `develop_session_id`. Unmet acceptance → `remediation:` GitHub issues via `to-tickets` (`--parent-issue`), returns `BLOCKED: FEATURE_REMEDIATION`; the develop orchestrator re-batches those through the normal ticket pipeline.
- After the feature coder's `READY_FOR_HUMAN_REVIEW`, the develop orchestrator prints the merge prompt and merges the feature PR on "all reviewed" (`gh pr merge --squash --delete-branch=false`). It does **not** re-verify code-review or CodeRabbit evidence — the feature coder's terminal report plus the human approval are its only gates. Then it emits the spec-handoff string.

### Hard reminders

- Sign-off of the **work** (full-suite verification, `state:done`, docs, PR merge-ready) = **feature coder** in the feature worktree, kicked by `orchestrate`.
- Merge of the **feature PR** = **orchestrator** on "all reviewed" (after the feature coder's `feature_report:`).
- Close of the **feature across the stack** (close + verify) = **architect in spec**, menu **3. Feature complete**.
- Spec merge closes **done-state** tickets; getting them to done and getting the PR ready is **feature coder** work.

### Session boundaries (recommended)

- **Planning:** `cd` into **spec** → **architect** → `hi` → **1. Product feature / PRD …** (one session through handoffs). Example: `cd ~/code/myapp/myapp-spec`.
- **Build:** `cd` into each **work repo** → **new** session → **orchestrate** on the **`develop` branch** → paste `feature:<slug>` (parallel OK when handoff says so). The develop orchestrator creates `opencode/feat-<slug>` and dispatches bounded full-ticket Tasks. Example: `cd ~/code/myapp/myapp-web`.
- **Review / merge:** stay in the work repo. The develop orchestrator kicks the feature coder in the feature worktree automatically when all tickets merge; on `READY_FOR_HUMAN_REVIEW` say **"all reviewed"** to merge the feature PR.
- **Complete:** back in **spec** → **architect** → `hi` → **3. Feature complete …** only after every work repo's feature PR merged and the orchestrator emitted the spec-handoff string.

Same-session handoff is optional (`/compact` after a short table HANDOFF block); use a new session if the provider errors on tool history.

### Sign-off and ticket closure

| Label / state | Set when | Meaning |
|---------------|----------|---------|
| `state:in-progress` | During **orchestrate** in the work repo | Actively executing issue/stages |
| `state:ready-for-review` | After **orchestrate** finishes an issue | Implementation done; awaiting work-repo architect |
| `state:done` | Feature coder inside `feature-review` | You accepted the work; issue **stays open** until spec merge |
| Issue **closed** on GitHub | Spec **3. Feature complete** at merge | Ticket complete |

**Orchestrate** does not accept tickets, write sign-off docs, close issues, or merge the feature PR. One **feature PR** per work repo after the queue is empty; then the orchestrator kicks the feature coder (`feature-review`) for the verification loop.

#### Feature coder — sign-off + feature PR (work repo only)

| Step | Done when |
|------|-----------|
| Full-suite `code-review` | Full diff vs `develop` approved; full compose suite green |
| PR-side CodeRabbit | medium/hard only — `PASS` or `BLOCKED` (easy skips); never after a remediation push |
| Difficulty gate | easy — none; medium — `code-review` completion summary; hard — `senior-dev scheduled_review` |
| Docs | changelog + (scope) guides / architecture written on the feat branch |
| `state:done` on every ticket | Issues stay **open** until spec merge |
| Feature PR open | `scripts/feature-finish-pr.sh <slug>` returns `pr-created` / `pr-exists` |
| Stabilization | bounded 3 iterations; `READY_FOR_HUMAN_REVIEW` or `BLOCKED: FEATURE_REMEDIATION` with `remediation:` issues |
| Terminal `feature_report:` | posted on the PRD parent + best-effort `session_notify` |

Skill detail: [skills/orchestrate/SKILL.md](../skills/orchestrate/SKILL.md) (develop orchestrator outer loop), [skills/feature-review/SKILL.md](../skills/feature-review/SKILL.md) (feature coder sign-off + feature PR), and [skills/ticket-lifecycle/SKILL.md](../skills/ticket-lifecycle/SKILL.md) (per-ticket inner loop loaded by the `coder` primary agent).

## Execution mode

| Mode | Where | Source of truth | What you select |
|------|--------|-----------------|-----------------|
| **Spec / GitHub** (default) | spec + work repos | GitHub issues with `feature:<slug>` after planning | Spec **architect** → **1**; work **orchestrate**; work **architect** → **4**; spec **architect** → **3** |

Fanout alone is not enough for the stage loop — planning must finish issue-expand before **orchestrate** on the spec path. Orchestrate blocks at bootstrap if expansion is incomplete.

## One human shell command (stack bootstrap)

From the **project parent** (folder containing `*-spec` and work repos):

```bash
export GH_ORG=your-github-login-or-org
cd ~/code/APP && setup-project
```

`GH_ORG` is the GitHub **owner** (`owner/repo`), not the app slug or local folder name. That syncs tooling into spec + work repos. Everything else is OpenCode menus. See [RUNBOOK.md](RUNBOOK.md) and [skills/setup-project/SKILL.md](../skills/setup-project/SKILL.md).

**Project board (optional):** Set `GH_PROJECT` in `~/.opencode-agent-env` before publish/fanout. See [GITHUB-PROJECT-BOARD.md](GITHUB-PROJECT-BOARD.md).

## Canonical issue body

Parent PRD · User stories · Requirements · **Implementation plan** · **opencode-task-yaml** · Description · Blocked by

Details: GitHub issue body schema is documented inline by `skills/issue-expand/SKILL.md`.

## Internal scripts (agents only)

Central in `OPENCODE_CONFIG_DIR` — invoke via **`opencode-run`** (never copied into app repos):

| Command | Used by |
|---------|---------|
| `opencode-run --cwd <impl> impl issue-expand-bundle` | issue-expand from spec (sibling path) |
| `opencode-run impl issue-expand-bundle` | issue-expand from impl (deprecated) |
| `opencode-run impl feature-check` | issue-expand (single impl repo) |
| `opencode-run spec feature-check` | feature-upgrade, fanout-issues, issue-expand (all repos) |
| `opencode-run impl orchestrate-readiness-check` | issue-expand, orchestrate bootstrap |
| `opencode-run impl feature-context` | issue-expand, orchestrate |
| `opencode-run spec fanout` | fanout-issues (spec) |
| `resolve_impl_path.sh` | issue-expand (spec → sibling abs path) |

## See also

- [RUNBOOK.md](RUNBOOK.md)
- [skills/orchestrate/SKILL.md](../skills/orchestrate/SKILL.md)
- [skills/feature-review/SKILL.md](../skills/feature-review/SKILL.md)
- [skills/ticket-lifecycle/SKILL.md](../skills/ticket-lifecycle/SKILL.md)
- [skills/issue-expand/SKILL.md](../skills/issue-expand/SKILL.md)
- [skills/feature-complete/SKILL.md](../skills/feature-complete/SKILL.md)
- [skills/setup-project/SKILL.md](../skills/setup-project/SKILL.md)
