# Stage-Based Orchestration Runbook

**Config precedence:** `opencode.json` is the sole runtime authority for models, `steps` caps, MCP, and global `permission` / `instructions`. Agent markdown frontmatter describes behavior; numeric limits in frontmatter are superseded by `opencode.json` when both exist.

## Two-mode workflow

| Mode | Planning | Execution source of truth |
|------|----------|----------------------------|
| **Spec / GitHub** (default) | Spec: PRD + fanout + **issue-expand** (architect option 1, same session) | GitHub child issues (`feature:<slug>`, `opencode-task-yaml` + `stages[]`); ticket work happens inside **coder** sessions |

The pipeline splits into two primaries: **orchestrate** owns the outer loop on `develop` (feature worktree, batch kickoff, PR approval, merge + cleanup, feature-architect handoff). **coder** owns the per-ticket inner loop (TDD → code-review → sub-PR → terminal `ticket_report:`). They are separate agent contexts — only coder holds `session_notify`; only orchestrate owns `worktree-manager` and remote-branch deletes.

See [FEATURE-PIPELINE.md](FEATURE-PIPELINE.md) for the numbered pipeline. **Fanout alone does not populate `stages[]`** — issue-expand runs in the spec architect session before orchestrate.

## GitHub-always principle (spec path)

GitHub issues are the execution source of truth for spec-driven features. Orchestrate reads **issue bodies** (`opencode_meta`, `stages[]`, Implementation planning markdown), not the full PRD, unless a subagent explicitly needs PRD context. Ephemeral caches (`tmp/feature-context.md`) are not authoritative. The spec repo holds PRDs, the registry, and product glossary (`CONTEXT.md`, `LANGUAGE.md`).

## Stack bootstrap (`setup-project`)

| Who | Command / action |
|-----|------------------|
| **Human (once per stack)** | `cd ~/code/APP && setup-project` from project parent (`GH_ORG` or `--org` required) |
| **OpenCode (spec repo)** | architect → **setup-project** skill: interview, `docs/agents/repos.md`, Task **stack-bootstrap** per impl repo |

Shell bootstrap aligns docs and GitHub templates; registry **INCOMPLETE** until the OpenCode interview fills TBD fields is normal (`exit 3` / `NEXT:`). Re-run `setup-project` after adding sibling impl repos. Details: [README.md](../README.md) Setup, [skills/setup-project/SKILL.md](../skills/setup-project/SKILL.md).

## Project overview (GitHub Project board)

When `GH_PROJECT` is set in `~/.opencode-agent-env`:

- **`opencode-run spec publish-prd-issue`** registers the PRD parent issue on the org board and writes `parent_issue` into the PRD frontmatter.
- **`opencode-run spec fanout`** creates child issues as sub-issues, labels them `prd-task`, and registers each on the board.
- Sub-issue progress rolls up on the parent card in the project view.
- Spec repo workflow **`prd-parent-auto-close`** closes PRD parents when all sub-issues are done.

Full setup: [GITHUB-PROJECT-BOARD.md](GITHUB-PROJECT-BOARD.md). Requires `gh` >= 2.94.0 and `gh auth refresh -s project`.

## Push cadence (issue-backed execution)

- **Commit locally** after each passing stage using the stage `commit_message` from `opencode-task-yaml` (append `Refs: #<issue_number>`). Local commits are fine; remote pushes are not part of the per-issue loop.
- **Do not push** the feature branch after each issue or stage. Avoid triggering GitHub Actions, hosted CodeRabbit, and other remote checks mid-feature unless the user explicitly requests remote visibility.
- **Push/open the feature PR only once** — after the full feature queue merges and the feature coder's verification loop (including the PR-side CodeRabbit gate on medium/hard) passes with all findings fixed or explicitly resolved locally. Per-ticket sub-PRs open as each ticket's coder session completes its loop (stages → full suite → local CodeRabbit pre-flight → sub-PR).
- **Do not** treat “code already exists in the tree” as “ticket done” — map acceptance to tests and yaml `stages[]`.

## Overview

- **Built-in agents:** `plan` uses DeepSeek V4 Flash; `build` uses DeepSeek V4 Flash for generic/quick tasks.
- **Primary planning mode** (`architect`) — read-only with **allow-by-default bash** (explicit deny for destructive/mutating shell): exploration, `gh`, `opencode-run`, `setup-project --check-only`; artifact writes via **scribe** / **stack-bootstrap** Tasks only.
- **Outer-loop coordinator** (`orchestrate`) runs from `develop`. Reads `## Difficulty` from the artifact (`easy` \| `medium` \| `hard`; default `medium` if missing). Owns `opencode/feat-<slug>`, batch kickoff of one **coder** session per ticket (via `worktree-manager` + `session_notify`), PR approval gate (single human gate), merge + worktree + remote-branch cleanup. When all tickets merge into the feature branch, kicks the **feature coder** (same `coder` agent, loading `feature-review`) in the feature worktree — that session runs the entire final verification loop and posts the terminal `feature_report:`. On READY the orchestrator presents the feature PR and merges on "all reviewed". **Never** executes tickets and **never re-verifies code-review or CodeRabbit evidence** — coder terminal reports plus human approval are its only gates. **Skills:** `orchestrate` (bootstrap + work selection + feature worktree + batch kickoff + wake contract + PR-approval gate + merge/cleanup + feature coder kickoff + feature merge on approval).
- **Planning specialists** (`debugger`, `refactor`, `review`, `designer`) — read-only subagents of **architect**; return plan drafts, never write code. `designer` synthesizes design briefs for Prototype Design using Gemini 3 Flash. The **`review`** agent is the architect's analysis specialist (review-plan drafts, PR-feedback triage, audit security delegation via `security-reviewer`) — never dispatched by coder sessions; machine verification lives in `code-review`.
- **Documentation generator** (`document`) — read-only; generates changelog/guides/architecture content; architect or the feature coder invokes, then scribe writes.
- **Execution subagents** (`developer`, `frontend-dev`, `ux-dev`, `test-writer`) — coding agents dispatched by the **coder** primary agent (ticket or feature mode). Architect and orchestrate never invoke them directly. `frontend-dev` uses MiniMax M3 for JSX/CSS/visual output. `ux-dev` generates HTML-only framework-agnostic prototypes from design briefs into `.prototype/<slug>/`.
- **Coder** (`coder`) — primary agent hosted inside each worktree (auto-started GUI session for tickets, kicked by orchestrator for feature worktrees). Loads `ticket-lifecycle` in a ticket worktree or `feature-review` in the feature worktree. In ticket mode: owns every stage (test-writer RED → owner GREEN → per-stage code-review), runs the **final `all_stages: true` full-suite gate** via the compose test backend (`docker-compose.test.yml` via `sandbox exec` on opencode-server, or direct `docker compose -f <file>` on local dev; see `rules/verification.md` and `skills/docker-sandbox/SKILL.md`), then dispatches `code-review` for the **local CodeRabbit pre-flight** (`ticket_coderabbit_preflight` — correctness/obvious-bugs/risky-changes scope, findings applied as fix-now suggestions) before the sub-PR opens, escalates to senior-dev unattended (no operator confirmation — the only human gate is PR review), falls back failed children to kilo/openrouter via `fallback-dispatch`. In feature mode: dispatches `code-review` for the full suite + **PR-side CodeRabbit gate** (`feature_coderabbit_gate`, medium/hard) + medium completion summary, inside the feature verification loop. Holds `session_notify` to inject the terminal `ticket_report:` (ticket mode) or `feature_report:` (feature mode) back into the develop orchestrator session. Never writes files directly — delegates everything.
- **Senior-dev** (`senior-dev`) — subagent with two explicit modes: `escalation_fix` (mid-stage unblocker; the **ticket coder** dispatches this unattended when a stage exhausts its retry budget or is marked hard/senior — no user confirmation) and `scheduled_review` (hard-difficulty read-only gate inside `feature-review`). `escalation_fix` returns `HANDOFF_TO_DEVELOPER` to the wrapping coder, which resumes with `developer` for remaining stage work.
- **Artifact writer** (`scribe`) — only write path; writes docs (changelog/guides/architecture/adr/agents), `CONTEXT.md`, `CONTEXT-MAP.md`, root `README`, optional `AGENTS.md`, `.env.example`, and spec PRDs/registry/delivery records when delegated (invoked by architect, the feature coder, and orchestrate).
- **Code-review** (`code-review`) is an independent acceptance gate, never writes code, and may conditionally delegate to `security-reviewer` when security triggers fire.
- **Mentor** (`mentor`) is optional and explanatory only.

## Agent Matrix

| Role                    | Agents                                       | Model Tier | Responsibility                                                                                                                                                       |
| ----------------------- | -------------------------------------------- | ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Primary (planning)      | `architect`                                  | smart      | Read-only: explore, report, draft. Delegates PRD/docs/registry writes to `scribe`; never executes implementation. Sign-off duty removed — feature coder owns `feature-review`; spec `feature-complete` closes at merge. |
| Coordinator             | `orchestrate`                                | smart      | Outer loop on `develop`: feature worktree, batch kickoff of coder sessions, PR approval gate, merge + cleanup, feature coder kickoff (`feature-review`), feature PR merge on "all reviewed". **Checkout identity gate always**; never prompts for preflight; never re-verifies code-review/CodeRabbit evidence. |
| Ticket executor wrapper | `coder`                                      | smart      | Per-ticket inner loop: §0 Bootstrap (brief file + GitHub) → silent preflight (compose test backend) → every `stages[]` entry → final-gate full suite via `docker-compose.test.yml` → local CodeRabbit pre-flight → sub-PR + stabilization → terminal `ticket_report:` + `session_notify`. Senior-dev escalation unattended; provider fallback layered on top. Non-writing (`edit: deny`). Feature mode: full verification loop incl. PR-side CodeRabbit (medium/hard), difficulty gates, docs, `state:done`, feature PR, bounded stabilization, terminal `feature_report:`. |
| Planning specialists    | `debugger`, `refactor`, `review`, `designer` | smart      | Return type-specific plan drafts to **architect**. `designer` uses Gemini 3 Flash. `review` is architect-only analysis (review-plan drafts, PR-feedback triage, security delegation) — never dispatched by coder sessions.    |
| Documentation generator | `document`                                   | fast       | Generate changelog/guides/architecture content; architect or the feature coder invokes, scribe writes                                                                                     |
| Artifact writer         | `scribe`                                     | fast       | Write/update docs (changelog/guides/architecture/adr/agents), `CONTEXT.md`, `README.md`, `.env.example`, spec PRD/registry/delivery records from parent content                                                                     |
| Execution               | `developer`, `frontend-dev`, `ux-dev`, `test-writer` | smart/fast | Execute assigned `stage_id` tasks (dispatched by **coder**, not orchestrate). `ux-dev` uses `google/gemini-3-flash-preview` (see `opencode.json`) for HTML-only prototype generation into `.prototype/<slug>/`.                                            |
| Operator escalation     | `senior-dev`                                 | smart      | Escalation: unattended when dispatched from coder (mid-stage retry-budget exhaustion or hard/senior stage); operator + user confirm only when dispatched from architect/orchestrate. **Hard** completion gate: dispatched by the feature coder on hard Difficulty for scheduled review.                                                                                    |
| Code review             | `code-review`                                | fast       | The single verification gate for both coder loops: ticket mode (per-stage focused + final `all_stages: true` full suite + local CodeRabbit pre-flight) and feature mode (full diff vs `develop` + full suite + PR-side CodeRabbit gate + medium completion summary). Never dispatched by the orchestrator.                                                                                                                   |

Both primaries (`architect`, `orchestrate`) are non-writing (`edit: deny`). Only `scribe` writes plan artifacts, docs, `README.md`, and `.env.example` in allowed paths.

## Skill loading policy (Task prompts)

Parents **`architect`** and **`orchestrate`** must include **exactly one** of the following in **every** Task prompt to a subagent:

- **`load: full`** — subagent loads its namesake skill before acting (protocol-heavy or high-risk work).
- **`load: minimal`** — subagent uses Hard Rules only; does not load its skill.
- **`load: auto`** — subagent applies **Auto-load triggers** in its own agent file (safe default when unsure).

Rules:

- Skill load **never blocks** completion. If loading fails, the subagent reports `SKILL_UNAVAILABLE: <skill>`; if the parent used `load: full`, treat the path as blocked until resolved.
- **Dispatch hints** (which default to use per target) live in [`agents/architect.md`](../agents/architect.md) and [`agents/orchestrate.md`](../agents/orchestrate.md) under **Skill dispatch hints**.
- Each subagent’s **Execution readiness** section defines how `load:` and auto-triggers interact.

## Permission Conventions (skill creep prevention)

- **Skill:** Each agent may load only its core skill(s). No `skill: { "*": "allow" }`. Explicit allow per skill (e.g. `to-tickets` / `issue-expand` for architect; `orchestrate` for orchestrate; `ticket-lifecycle` + `feature-review` for coder; `developer` for developer).
- **Architect subagents** (`debugger`, `refactor`, `review`, `document`, `designer`): `task: { "*": deny }` — they cannot invoke scribe or any other agent. Return content only to parent; architect handles scribe handoff.

## Model routing policy (Go-first, cost-tiered)

Go subscription allowance is consumed first before paid Zen fallbacks. Route by task shape, not agent prestige. Keep one deliberate fallback per important role.

## Canonical Flow

1. `architect` asks for plan type (Feature/Debug/Refactor/Review/Document/Prototype Design) when request is greeting/unspecified.
2. **Features:** architect classifies **`## Difficulty`** (`easy` \| `medium` \| `hard`), runs a Claude Context readiness check (`get_indexing_status` → `index_codebase` if needed), then investigates with `claude-context`. **Strategist** is mandatory when any feature has cross-repo dependencies, non-trivial data/domain-model changes, auth/payments/security boundaries, external provider integration, migration/rollback needs, or uncertain architectural ownership. **Architecture-auditor** (feature-impact assessment via `opencode-go/gpt-5.6-luna`) is invoked for hard features or medium features that change service boundaries, shared modules, schemas, public APIs, cross-repo contracts, or introduce a new integration. Not invoked for easy features, isolated UI work, documentation, or local bug fixes. **Hard** features also get a red-team strategist pass before fanout. **Easy** or **medium** (single-domain, sufficient investigation, no mandatory triggers) → architect synthesizes the plan without strategists; **medium** (multi-domain / high uncertainty / cross-cutting) or **hard** → architect decomposes and spawns scoped **`strategist`** subagents. **Strategist** and other planning specialists also run the same Claude Context readiness gate before discovery; bash/glob fallback is allowed only when MCP is unavailable or indexing still fails after retry (`MCP_FALLBACK` in output). Stage sizing: aim **3–7 stages**; split stages that would exceed **~15 developer tool rounds** or **>3 substantive files** each. Other types: architect invokes matching specialist (`debugger`/`refactor`/`review`/`designer`) as needed. Prototype Design uses the required intake → `designer` → GitHub issue implementation plan with `design_delivery: prototype-required` → orchestrate flow.
3. `architect` invokes `scribe` to write artifacts to approved docs paths (mandatory step). Issue-backed paths use `to-issues` / `publish-targeted-issue`; never local plan files.
4. User switches to `orchestrate`.
5. `orchestrate` runs §0 Bootstrap: dispatch ONE `developer` Task (`load: minimal`) running `scripts/checkout-contract.sh`; require `status: ok` and capture `is_linked_worktree` + `branch_policy`. The orchestrator itself has no bash — every shell invocation is a delegated Task. `CHECKOUT_CONTRACT_FAILED` is surfaced verbatim and stops the session (no improvised alternative menu). Preflight belongs to coder sessions (`ticket-lifecycle` §0.3 runs it silently); the orchestrator never prompts for preflight.
6. `orchestrate` runs Claude Context readiness (`get_indexing_status` → `index_codebase` if needed), delegated to a `developer` Task. Record `MCP_FALLBACK` when MCP is unavailable or indexing fails after retry.
7. `orchestrate` presents the **work-selection menu** verbatim. On `develop`/`main`/`master` (Menu A): **(1)** Start a new feature — `feature:<slug>` then run every ticket end-to-end to a ready-for-review PR; **(2)** Resume a feature — reattach to an existing `feature:<slug>` or ticket worktree; **(3)** Remediation loop — re-check PR feedback / CI; **(4)** Something else. (A ticket worktree belongs to its coder session — switch the session's agent to `coder` and say `begin`; the orchestrator here owns routing only.)
8. `orchestrate` runs the readiness check delegated to a `developer` Task (`opencode-run impl orchestrate-readiness-check <slug>`). PASS requires non-empty `stages[]` on every open ticket and a `compose_test_file` for every impl repo in `docs/agents/repos.md`; FAIL stops and returns to spec architect option 1. On PASS, `orchestrate` asks the user exactly once for `auto_spawn_consent`. With consent `yes`, the loop dispatches every DAG-respecting ticket with no further prompts; the only human gate is the per-PR approval.
9. Preflight is coder-owned. The orchestrator never prompts for preflight and never dispatches `preflight`/`worktree-env`. Per-ticket preflight is rerun only when the ticket surfaces `ENV_BLOCKED` remediation in its coder session.
10. `orchestrate` creates the feature worktree via a `worktree-manager` Task (`create_feature`) and pushes `opencode/feat-<slug>` via a delegated `developer` Task. It then kicks coder sessions — one per runnable ticket — via `worktree-manager` `create_ticket` with `kickoff_agent: "coder"` and a short pointer `kickoff_message`. The plugin writes `<gitdir>/opencode-ticket-brief.json` and injects the pointer into the auto-started GUI session (which IS the coder session). Ticket work is **never** dispatched via the `task` tool — subagents inherit the `develop` cwd and `scripts/checkout-contract.sh --verify` would reject them.
11. Each coder session owns the full inner loop for one ticket: `ticket-lifecycle` §0 Bootstrap (brief file + GitHub reconstruction) → silent preflight (compose test backend) → every `stages[]` entry → final-gate full suite (`all_stages: true` via compose) → **local CodeRabbit pre-flight** (`ticket_coderabbit_preflight` — findings applied as fix-now suggestions before the sub-PR) → sub-PR + stabilization → terminal `ticket_report:` + `session_notify`. Stages + per-stage focused `code-review` are dispatched inside the coder session, not by the orchestrator.
12. The coder session holds `session_notify`; it injects the terminal `ticket_report:` pointer back into the develop orchestrator session. The develop orchestrator wakes via: (i) in-session `session_notify` (primary), (ii) poller `scripts/dev-loop-poller.sh` firing `DEV_LOOP_WAKE`, (iii) any user message — dispatch a `developer` Task (`load: minimal`) to run `scripts/dev-loop-watch.sh` first.
13. PR-approval gate: per `READY_FOR_HUMAN_REVIEW`, the orchestrator notifies the user ("PR ready for review: <pr_url>") and waits for "yes, happy with that ticket" — the single human gate per PR. The orchestrator then dispatches a `developer` Task with explicit `cd`/`git -C` to `gh pr merge --squash --delete-branch=false` and fast-forwards `opencode/feat-<slug>`. It dispatches `worktree-manager` `delete` for the ticket worktree and a `developer` Task for `git push origin --delete opencode/ticket-<issue>-<slug>-<abbrev>` (the only branch-deleting actor).
14. **CodeRabbit — two runs, two roles, both coder-owned and dispatched via `code-review`** (the orchestrator never dispatches CodeRabbit and never checks its verdict): (a) **local pre-flight per ticket** — the ticket coder dispatches `code-review` (`ticket_coderabbit_preflight`) after the final-gate full suite and before the sub-PR opens; scope is correctness, obvious bugs, and risky changes; findings are fix-now suggestions applied in-worktree (narrow the rule set further if this and the PR-side gate produce duplicate noise); (b) **PR-side gate per feature** — the feature coder dispatches `code-review` (`feature_coderabbit_gate`) inside `feature-review` after the last ticket merges into `opencode/feat-<slug>` (medium/hard on all changed files vs `develop`; easy skips; never after a remediation push) — style, regressions, cross-branch context, and policy; `PASS` is required before the feature PR is ready for review.
15. **Difficulty completion gates** run in the feature coder session (`feature-review`), not in the develop orchestrator: **easy** — none; **medium** — `review` completion-summary pass; **hard** — `senior-dev` `scheduled_review`.
16. **Feature PR stabilization:** `scripts/feature-finish-pr.sh` runs in the feature coder session, then bounded stabilization (max 3 iterations) collects PR checks/comments and classifies findings, executes fix-now items through developer→code-review, and presents checkpoints. The develop orchestrator's role is the **feature PR merge** after "all reviewed" — it does not re-verify the gates.
17. When stabilization completes and the feature coder posts `feature_report: READY_FOR_HUMAN_REVIEW`, orchestrate prints the merge prompt: "Feature <slug> ready for final review: <pr_url>" and waits for the user to say **"all reviewed"** — single human gate at the feature level. Then merges the feature PR and emits the spec-handoff string (`feature:<slug> complete in <OWNER/REPO>; ready for spec feature-complete`).
18. **Spec `feature-complete`** (post-merge): verify-only ceremony — confirm every `feature:<slug>` issue is `state:done` + `verified` and the impl feature PRs are **MERGED** (merged by the develop orchestrator on "all reviewed"), then close child issues + PRD parent + delivery record. The feature coder runs the post-merge sign-off loop.

The coder session grades child output at each stage handoff (per-stage `code-review` APPROVED / NEEDS_CHANGES / BLOCKED). The develop orchestrator surfaces terminal reports (`ticket_report:` from ticket coders, `feature_report:` from the feature coder) and merges on human approval — it never re-verifies code-review or CodeRabbit evidence.

## Escalation and Recovery (enforced)

When a coder session reports `BLOCKED` (preflight-after-repair, CI-exhaustion, fallback-exhaustion, cross-ticket review, or stabilization exhaustion), the orchestrator surfaces the blocker verbatim and pauses the batch.

When a `BLOCKED: CROSS_TICKET_REVIEW` lands from a ticket coder, the develop orchestrator surfaces it and waits for the user's "remediation" message — then re-batches the feature coder's `remediation:` issues through the normal ticket pipeline and re-kicks the feature coder once they merge (`feature-review` §8). The feature coder creates `remediation:` GitHub issues (`to-tickets` with `--parent-issue`), and when the remediation tickets merge, the feature coder re-runs verification.

Do not advance the batch until the blocker is resolved. Do not allow repeated test-command retries under unresolved environment mismatch. Smoke harness: `docs/smoke/feature-worktree-fanout-validation.md`.

**Ubuntu Sysbox sandboxes (optional):** When the utilities opencode-server stack enables Sysbox siblings (`OPENCODE_SANDBOX_ENABLED=1`), the `sandbox` CLI is on PATH inside the server container. Preflight probes softly (`sandbox: ready|unavailable`); `unavailable` is not a hard fail (typical Mac / `OPENCODE_SANDBOX_MODE=off`). **Orchestrate does not load skill `docker-sandbox`** — it detects compose/Docker need and instructs `developer` / `frontend-dev` / `code-review` Tasks to load it and wrap compose checks as `sandbox exec` (see `skills/orchestrate/SKILL.md`, `skills/ticket-lifecycle/SKILL.md` §0.3, and `skills/feature-review/SKILL.md` §0.3 for the routing). App Infisical for Compose comes from repo `.env` (`./scripts/setup.sh projects …`, then **worktree-env** on linked worktrees) — not OpenCode server Infisical injection. Do not invent host Docker/Sysbox usage when the probe fails. **Not** Cloudflare Workers Sandbox (`skills/cloudflare/references/sandbox/`).

**Config on the Docker server:** Agents/skills come from `CONFIG_REPO` / `CONFIG_REF` cloned at **image build** (host `~/.config/opencode` is never mounted). After merging orchestrate/`docker-sandbox` wiring to the config branch used by Ubuntu, rebuild: `docker compose build --no-cache opencode && docker compose up -d opencode` (never `down -v`).

**Senior-dev escalation (coder: unattended; architect: operator-confirmed):** When a **coder** stage exhausts its retry budget (2 `NEEDS_CHANGES` from `code-review`) or the stage is marked hard/senior, the coder dispatches `senior-dev` `escalation_fix` **unattended** (no user confirmation — the only human gate is PR review). When **architect** dispatches `senior-dev` mid-stage, the operator must confirm before the escalation. **Exception:** for **`Difficulty: hard`**, after every stage passes the final code-review, the feature coder session dispatches `senior-dev` `scheduled_review` (no confirmation — that's the feature coder's hard gate).

## Subagent Loop Exit Strategy (enforced)

When a subagent repeats the same completion message or stalls:

1. **OpenCode config**: `steps` caps agentic iterations per session — e.g. scribe `8`, developer/frontend-dev `45`, architect `30`, orchestrate `100`, primaries and subagents are bounded. See `opencode.json` `agent` block.
2. **Orchestrator loop detection**: If the same or near-identical child report is received 2+ times, treat as `BLOCKED` and route to the feature coder's remediation flow (`feature-review` §8 — `remediation:` GitHub issues). The develop orchestrator re-batches them through the normal ticket pipeline.
3. **Scribe exit rule**: Scribe returns exactly once per task. After reporting path + operation + summary, it stops.
4. **Developer anti-loop rule**: Developer must not repeat the same verbal intent (e.g. "Let me create X"); one statement, then execute. If the same failing command repeats twice without meaningful change, return `blocker_code: STAGE_STUCK` and stop.
5. **Manual escape**: Use `Ctrl+C` or session interrupt. Resume in a new session with artifact path if needed.
6. **Manual handoff (Task did not return):** If a subagent completed and produced a report but the Task did not return control to the orchestrator, switch to the `orchestrate` agent and paste the completion report. The orchestrator will grade it and proceed to the next stage. Do not message the subagent again—it has already completed.

Provider-level `timeout` (e.g. 300000ms) and per-model **`temperature` / `top_p` / `frequency_penalty`** are set under `provider.<name>.models.<id>.options` in `opencode.json` to reduce variance and wasted tokens (e.g. lower temp for execution, gentle `frequency_penalty` for DeepSeek).

## Model routing (Go-first, cost-tiered)

| Layer | Agents | Primary model | Fallback |
| --- | --- | --- | --- |
| High-volume execution | `developer`, `frontend-dev`, `coder`, `orchestrate`, `helper`, `debugger`, `refactor`, `review` | `opencode-go/deepseek-v4-flash` (developer/frontend-dev/helper/debugger/refactor/review); `kilo/minimax/minimax-m3` (coder, orchestrate) | `opencode/deepseek-v4-flash` when Go quota exhausted; same model retained on Kilo when coder/orchestrate runs on Kilo |
| Fast utility / setup | `preflight`, `worktree-env`, `document`, `doc-reviewer`, `stack-bootstrap` | `opencode-gpt/gpt-5-nano` | `opencode-go/deepseek-v4-flash` if GPT-5 Nano fails |
| Docs/PRD writer | `scribe` | `opencode/deepseek-v4-flash` | `opencode-go/deepseek-v4-flash` (alt route) if primary fails |
| Independent code-review gate | `code-review` | `kilo/minimax/minimax-m3` | `opencode/go-gpt-5.6-luna` for escalation/high-risk only |
| Architecture assessment | `architecture-auditor` | `opencode-go/gpt-5.6-luna` (feature-impact) | `opencode-gpt/gpt-5.6-terra` for full audits |
| Feature decomposition | `strategist` | `opencode-go/deepseek-v4-pro` | `opencode-go/gpt-5.6-luna` for hard cross-repo |
| Senior escalation / review | `senior-dev` | `opencode/kimi-k3` | `opencode-gpt/gpt-5.6-terra` when Kimi K3 is unavailable |
| Security analysis | `security-reviewer` | `opencode-go/gpt-5.6-luna` | `opencode/claude-opus-4-8` only for user-approved high-severity escalation |
| Vision / visual | `vision`, `designer`, `ux-dev` | `opencode/gemini-3-flash` (retained) | Current configured |
| Teaching | `mentor` | `opencode-go/qwen3.7-max` | — |
| Generic / built-in | `plan`, `build` | `opencode-go/deepseek-v4-flash` | — |

Runtime authority: `opencode.json`. Agent frontmatter `model:` should match for changed agents.

`default_agent` is set to `orchestrate` so execution sessions start with the coordinator as the active primary context.

## Review and Code-Review Interaction

- `review` focuses on bug/correctness/security risks and fix planning.
- `code-review` (per-ticket and per-stage): verifies against the issue's `opencode-task-yaml` acceptance criteria + per-stage scope + RED/GREEN replay. Returns `APPROVED` / `NEEDS_CHANGES` / `BLOCKED`.
- `code-review` (feature mode): dispatched by the feature coder inside `feature-review` — verifies the full diff vs `develop` against the rolled-up acceptance from every ticket and the full compose test suite.
- If `code-review` returns `NEEDS_CHANGES` or `BLOCKED`, the wrapping coder session fixes in-worktree (TDD) or escalates to `senior-dev` (`escalation_fix`) for a mid-stage unblocker. Cross-ticket findings return `BLOCKED: CROSS_TICKET_REVIEW` and surface to the develop orchestrator, which routes them to the feature coder's `remediation:` flow.

## MCP Usage Policy

Primaries and execution agents should use MCP only when it reduces uncertainty:

- **`claude-context`**: Semantic code search keyed by **absolute path** (not only the OpenCode workspace). Pass the absolute path of the repo under investigation to `get_indexing_status`, `index_codebase`, and `search_code`. From the **spec repo**, resolve sibling impl paths via `bin/project/spec/lib/resolve_impl_path.sh` (`../<repo-basename>` beside spec). Use during planning (architect, **strategist**, debugger, refactor, review, document, designer). Discovery-heavy agents must run a readiness gate first (`get_indexing_status` for the target path; if needed `index_codebase`) and may fall back to bash/glob (`rg`, `find` on the sibling path) only when MCP is unavailable or indexing still fails after retry, with `MCP_FALLBACK` recorded in output. `orchestrate` also runs a lightweight readiness check on fresh startup.

  **Host vs Docker:** Toggle `mcp.claude-context.enabled` in `opencode.json`. Use **`true`** for local-only Desktop/CLI; use **`false`** on the host when Desktop attaches to the Docker OpenCode server (indexing then runs in the container against Milvus). Do not enable both — see [README — Claude Context indexing](../README.md#claude-context-indexing-host-vs-docker-server). Indexing is optional; OpenCode works without it.
- **`mcpjungle`**: The authenticated gateway for every managed upstream MCP server. The OpenCode configuration uses `MCPJUNGLE_OPENCODE_TOKEN` from the server runtime environment; upstream credentials and OAuth grants remain owned by MCPJungle. Context7, `cloudflare-api`, `cloudflare-docs`, and `docs-mcp-server` are available through this gateway. Use Cloudflare Docs instead of Context7 for Cloudflare-specific documentation.
- **`claude-context`**: The only permitted non-MCPJungle integration.

**Cloudflare skills** (narrow set from [cloudflare/skills](https://github.com/cloudflare/skills)): `cloudflare` (DNS/domains + platform guidance for web apps), `wrangler` (local run/deploy), `workers-best-practices`. Allowed on `architect`, `developer`, `senior-dev`, `frontend-dev`, `debugger`. Authentication is managed by MCPJungle; never start Cloudflare OAuth from OpenCode.

**Review-app DNS:** Feature URLs use skill `docker-sandbox` (`sandbox expose` for localhost publish of nested Caddy) plus `cloudflare-api` through MCPJungle for tunnel public hostname → `https://*********:<hostPort>` with **No TLS Verify ON** (never copy expose’s `http://` scheme; never HTTP service type) and optional CNAME upsert to the **existing** host tunnel — never `cloudflared tunnel create`.

If a user says "look at the prototype", check `docs-mcp-server` through `mcpjungle` first and record what was used.

**Execution phase**: Developer and frontend-dev receive `FilesToChange` from the plan; do not use claude-context for discovery unless the plan is ambiguous and the assigned stage requires locating additional files.

## Documentation Gate (Required)

The feature coder runs docs inside `feature-review`: `document` generates changelog (required) plus optional guides/architecture content per the doc scope, then `scribe` writes:

- `docs/changelog/<date>-<slug>.md`
- `docs/guides/<feature-slug>.md` (when in scope)
- `docs/architecture/<feature-slug>.md` (when in scope)

Docs commit on the feature branch **before** `scripts/feature-finish-pr.sh` opens the feature PR. Use templates in:

- `docs/changelog/TEMPLATE.md`
- `docs/guides/TEMPLATE.md`
- `docs/architecture/TEMPLATE.md`
- `docs/prototypes/HTML_PROTOTYPE_TEMPLATE.md`

## Stage Dispatch Template

Use this when dispatching execution:

```text
impl_repo_path: <absolute verified git root>
expected_branch: <current verified branch>
is_linked_worktree: true|false
branch_policy: do not create, switch, checkout, or rename branches unless user explicitly requests in this turn
Scope in: <paths/components>
Scope out: <explicit exclusions>
Acceptance checks: <commands>
Completion report required: stage_id, files_changed, `changes` [{ file, summary, strategy_step }], tests_run, acceptance_check_status, blockers, residual_risks, next_stage_input
```

Use this when dispatching markdown writes to `scribe`:

```text
Target path: docs/<section>/<name>.md, README.md, or .env.example
Operation: create|update
Content: full body from parent (markdown or .env.example template lines)
Constraints: approved paths only; markdown or .env.example only
```

## Troubleshooting: CRLF / `env: bash\r`

On macOS/Linux, **CRLF** line endings in shell scripts break the shebang (`env: bash\r: No such file or directory`). OpenCode config scripts use LF.

**Agents:** Do not fix CRLF file-by-file with sed/Python. Project automation runs from `OPENCODE_CONFIG_DIR` via **`opencode-run`** — update the config checkout if scripts fail with `env: bash\r`.

**Prevention:** Spec repos receive [`.gitattributes`](../templates/spec-repo/.gitattributes) on align for doc paths. Config-repo CI runs `scripts/check-crlf.sh` on `bin/`, `bin/project/`, `scripts/`, `templates/`, and `.gitattributes`.

## Ticket-session poller (`scripts/dev-loop-poller.sh`)

The develop orchestrator's primary wake for terminal ticket reports is in-session `session_notify` (the ticket session injects the `ticket_report:` message directly into the develop orchestrator's session). For out-of-band events — GitHub-UI merges, missed in-session notifies, poller-disabled intervals — `scripts/dev-loop-poller.sh` runs as a cron or systemd timer on the opencode-server host (Linux; this config repo lives on macOS but the server runs on a Linux host with loopback `127.0.0.1:4098`).

**Install (systemd timer, ~2-min interval):**

```ini
# /etc/systemd/system/opencode-dev-loop-poller.service
[Unit]
Description=OpenCode develop-loop poller (ticket_report wakes)
After=opencode-server.service

[Service]
Type=oneshot
Environment=OPENCODE_SERVER_USERNAME=opencode
Environment=OPENCODE_SERVER_PASSWORD=<from secrets>
Environment=OPENCODE_SERVER_PORT=4098
Environment=OPENCODE_CONFIG=/home/opencode/.config/opencode
Environment=DEV_LOOP_REPOS=BlocShed/BlocShed-web,BlocShed/BlocShed-api
ExecStart=/home/opencode/.config/opencode/scripts/dev-loop-poller.sh
User=opencode
```

```ini
# /etc/systemd/system/opencode-dev-loop-poller.timer
[Unit]
Description=Run opencode-dev-loop-poller every 2 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
AccuracySec=15s
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now opencode-dev-loop-poller.timer
sudo journalctl -u opencode-dev-loop-poller.service -f
```

**Cron alternative:**

```cron
*/2 * * * * OPENCODE_SERVER_USERNAME=opencode OPENCODE_SERVER_PASSWORD='<from secrets>' OPENCODE_CONFIG=/home/opencode/.config/opencode DEV_LOOP_REPOS=BlocShed/BlocShed-web,BlocShed/BlocShed-api /home/opencode/.config/opencode/scripts/dev-loop-poller.sh >> /var/log/opencode-dev-loop-poller.log 2>&1
```

The poller is idempotent — state files in `~/.local/state/opencode/dev-loop/<owner-repo>.json` dedupe wake messages per `(repo, issue, ticket_report)` tuple. A `DEV_LOOP_WAKE` for a feature with no active loop in the develop orchestrator's lifecycle log is silently ignored ("ignore if not yours").

## Smoke Checklist

- Architect issues include the GitHub-issue body schema (`## Difficulty`, `stages[]`, acceptance, test commands) — work executes from GitHub, not local plan files.
- Primary agents cannot edit files directly (`edit: deny`).
- Scribe can write to approved docs markdown paths, `README.md`, `.env.example`, and spec PRD/registry/delivery records (when parent supplies path and content).
- Scribe never writes runnable plan artifacts.
- Environment/toolchain blockers (`ENV_BLOCKED`) halt stage progression in the coder session.
- Stage dispatch is one-at-a-time with completion handoff.
- UI work routes to `frontend-dev`; non-UI work routes to `developer`; prototype generation from design briefs routes to `ux-dev` (outputs to `.prototype/<slug>/`).
- Senior-dev: from **ticket coder**, unattended mid-stage **escalation** (no user confirmation; only human gate is PR review); from **feature coder**, **no** confirmation for **hard** Difficulty `scheduled_review`.
- The feature coder's **medium** Difficulty gate is the `completion_summary` field in the feature-mode `code-review` report (`feature-review` §3); `review` is never dispatched by coder sessions.
- Orchestrator completion merges the feature PR after "all reviewed" and emits the spec-handoff string (`feature:<slug> complete in <OWNER/REPO>; ready for spec feature-complete`).
- Code-review report includes criterion-level evidence.
- No stale references to removed agents (`fix`, `pr-reviewer`, `refactorer`, `helper`). Execution uses `developer` (not built-in `build`) in the custom pipeline.
- MCP lookups are used only when prompt/context indicates need.
- Final docs are generated by the feature coder (`document` + `scribe`) before the feature PR opens.
