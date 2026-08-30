# Stage-Based Orchestration Runbook

**Config precedence:** `opencode.json` is the sole runtime authority for models, `steps` caps, MCP, and global `permission` / `instructions`. Agent markdown frontmatter describes behavior; numeric limits in frontmatter are superseded by `opencode.json` when both exist.

## Two-mode workflow

| Mode | Planning | Execution source of truth |
|------|----------|----------------------------|
| **Spec / GitHub** (default) | Spec: PRD + fanout + **issue-expand** (architect option 1, same session) | GitHub child issues (`feature:<slug>`, `opencode-task-yaml` + `stages[]`) |

See [FEATURE-PIPELINE.md](FEATURE-PIPELINE.md) for the numbered pipeline. **Fanout alone does not populate `stages[]`** — issue-expand runs in the spec architect session before orchestrate.

## GitHub-always principle (spec path)

After `opencode-run spec fanout`, **GitHub issues are the execution source of truth**. Do not create parallel `.plan/issue.*` files for spec-driven features. Orchestrate reads **issue bodies** (`opencode_meta`, `stages[]`, Implementation planning markdown), not the full PRD, unless a subagent explicitly needs PRD context. Ephemeral caches (`tmp/feature-context.md`) are not authoritative.

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
- **Push/open PR only once** after the full feature queue is complete, the one-shot local CodeRabbit CLI review has run, and all CodeRabbit findings have been fixed or explicitly resolved locally.
- **Do not** treat “code already exists in the tree” as “ticket done” — map acceptance to tests and yaml `stages[]`.

## Overview

- **Built-in agents:** `plan` uses DeepSeek V4 Flash; `build` uses DeepSeek V4 Flash for generic/quick tasks.
- **Primary planning mode** (`architect`) — read-only with **allow-by-default bash** (explicit deny for destructive/mutating shell): exploration, `gh`, `opencode-run`, `setup-project --check-only`; artifact writes via **scribe** / **stack-bootstrap** Tasks only.
- **Primary execution mode** (`orchestrate`) runs delegated stage execution and recovery flow. Reads `## Difficulty` from the artifact (`easy` \| `medium` \| `hard`; default `medium` if missing). After **all** stages/issues pass the final code-review (one gate per artifact or `feature:<slug>`): **medium/hard** — **CodeRabbit gate** via `review` + `code-review` skill (single CLI review of accumulated changes against `develop` by default; no CodeRabbit validation reruns); **easy** — skips CodeRabbit. **Never** runs CodeRabbit per GitHub issue, mid-stage, or after CodeRabbit remediation. Then: **easy** — no further gates; **medium** — `review` post-execution check; **hard** — `senior-dev` (scheduled review, no user confirmation) then `helper` (strategy conformance). On completion, prints a table-based sign-off handoff naming the exact feature/artifact, PR, work completed, gates, CodeRabbit, findings/risks, and the copy/paste prompt for architect. **Skills:** `orchestrate-execution` (bootstrap: preflight yes/no, optional env gate, work selection, stage loop, grading, completion gates); `orchestrate-recovery` (helper triggers, loops, env, escalation, manual paste). The monolithic `orchestrate` skill package is removed.
- **Planning specialists** (`debugger`, `refactor`, `review`, `designer`) — read-only subagents of architect; return plan drafts, never write code. `designer` synthesizes design briefs for Prototype Design using Gemini 3 Flash. The **`review`** agent may Task **`security-reviewer`**, **`performance-reviewer`**, and **`doc-reviewer`** when change scope warrants (see `skills/review/SKILL.md`). `review` may also be invoked by orchestrate on **medium** Difficulty after execution.
- **Documentation generator** (`document`) — read-only; generates changelog/guides/architecture content; architect invokes, then scribe writes.
- **Execution subagents** (`developer`, `frontend-dev`, `ux-dev`) — coding agents invoked by orchestrate only; architect never invokes them. `frontend-dev` uses MiniMax M3 for JSX/CSS/visual output. `ux-dev` generates HTML-only framework-agnostic prototypes from design briefs into `.prototype/<slug>/`.
- **Senior-dev** (`senior-dev`) — orchestrator subagent with two explicit modes: `escalation_fix` (mid-stage unblocker, operator-triggered) and `scheduled_review` (hard-difficulty read-only gate). Orchestrator asks user to confirm before escalation; scheduled review runs without confirmation.
- **Artifact writer** (`scribe`) — only write path; writes plan artifacts, docs, `README.md`, and `.env.example` when delegated (invoked by architect and orchestrate).
- **Recovery replanner** (`helper`) diagnoses stuck/failed states and amends existing artifacts through `scribe`. On **hard** Difficulty, orchestrate may also invoke helper for **strategy conformance** (reasoning-only compare plan vs implementation summary).
- **Code-review** (`code-review`) is an independent acceptance gate, never writes code, and may conditionally delegate to `security-reviewer` when security triggers fire.
- **Mentor** (`mentor`) is optional and explanatory only.

## Agent Matrix

| Role                    | Agents                                       | Model Tier | Responsibility                                                                                                                                                       |
| ----------------------- | -------------------------------------------- | ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Primary (planning)      | `architect`                                  | smart      | Read-only: explore, report, draft. Plan mode: scribe writes artifact → switch to orchestrate. Post-implementation: review → sign-off → document → scribe writes docs → scribe archives plan to `.plan/<type>.<slug>.completed.md` |
| Coordinator             | `orchestrate`                                | smart      | Execute stages, grade children, helper recovery, optional `review` (medium) / `senior-dev`+`helper` (hard) after final code-review, dispatch scribe. Plan picker lists **active** `.plan/*.md` only (excludes `*.completed.md`). Startup: optional preflight prompt; **checkout identity gate always**; **`worktree-env`** + **`preflight`** only when user opts in.                       |
| Planning specialists    | `debugger`, `refactor`, `review`, `designer` | smart      | Return type-specific plan drafts to architect. `designer` uses Gemini 3 Flash. `review` may also be invoked by orchestrate on **medium** Difficulty after execution.    |
| Documentation generator | `document`                                   | fast       | Generate changelog/guides/architecture content; architect invokes, scribe writes                                                                                     |
| Artifact writer         | `scribe`                                     | fast       | Write/update plan artifacts, docs, `README.md`, `.env.example` from architect/orchestrate content                                                                     |
| Recovery                | `helper`                                     | fast       | Replan minimal strategy deltas and trigger artifact amendment                                                                                                        |
| Execution               | `developer`, `frontend-dev`, `ux-dev`        | smart/fast | Execute assigned `stage_id` tasks. `ux-dev` uses `google/gemini-3-flash-preview` (see `opencode.json`) for HTML-only prototype generation into `.prototype/<slug>/`.                                            |
| Operator escalation     | `senior-dev`                                 | smart      | Escalation: operator + user confirm when stuck. **Hard** completion gate: auto-invoked post-code-review for scheduled review.                                                                                    |
| Code review             | `code-review`                                | fast       | Verify acceptance criteria with traceable evidence                                                                                                                   |

Both primaries (`architect`, `orchestrate`) are non-writing (`edit: deny`). Only `scribe` writes plan artifacts, docs, `README.md`, and `.env.example` in allowed paths.

## Skill loading policy (Task prompts)

Parents **`architect`** and **`orchestrate`** must include **exactly one** of the following in **every** Task prompt to a subagent:

- **`load: full`** — subagent loads its namesake skill before acting (protocol-heavy or high-risk work).
- **`load: minimal`** — subagent uses Hard Rules only; does not load its skill.
- **`load: auto`** — subagent applies **Auto-load triggers** in its own agent file (safe default when unsure).

Rules:

- Skill load **never blocks** completion. If loading fails, the subagent reports `SKILL_UNAVAILABLE: <skill>`; if the parent used `load: full`, treat the path as blocked until resolved.
- **Dispatch hints** (which default to use per target) live in [`agents/architect.md`](../agents/architect.md) and [`agents/orchestrate.md`](../agents/orchestrate.md) under **Skill dispatch hints**.
- Each subagent’s **Execution readiness** section defines how `load:` and auto-triggers interact (including `scribe` **`operation: archive_plan`** always loading the `scribe` skill).

## Permission Conventions (skill creep prevention)

- **Skill:** Each agent may load only its core skill(s). No `skill: { "*": "allow" }`. Explicit allow per skill (e.g. `architect-plan` + `architect-review` for architect; `orchestrate-execution` + `orchestrate-recovery` for orchestrate; `developer` for developer; `preflight` for **`preflight`**; `worktree-env` for **`worktree-env`**).
- **Architect subagents** (`debugger`, `refactor`, `review`, `document`, `designer`): `task: { "*": deny }` — they cannot invoke scribe or any other agent. Return content only to parent; architect handles scribe handoff.

## Model routing policy (Go-first, cost-tiered)

Go subscription allowance is consumed first before paid Zen fallbacks. Route by task shape, not agent prestige. Keep one deliberate fallback per important role.

## Canonical Flow

1. `architect` asks for plan type (Feature/Debug/Refactor/Review/Document/Prototype Design) when request is greeting/unspecified.
2. **Features:** architect classifies **`## Difficulty`** (`easy` \| `medium` \| `hard`), runs a Claude Context readiness check (`get_indexing_status` → `index_codebase` if needed), then investigates with `claude-context`. **Strategist** is mandatory when any feature has cross-repo dependencies, non-trivial data/domain-model changes, auth/payments/security boundaries, external provider integration, migration/rollback needs, or uncertain architectural ownership. **Architecture-auditor** (feature-impact assessment via `opencode-go/gpt-5.6-luna`) is invoked for hard features or medium features that change service boundaries, shared modules, schemas, public APIs, cross-repo contracts, or introduce a new integration. Not invoked for easy features, isolated UI work, documentation, or local bug fixes. **Hard** features also get a red-team strategist pass before fanout. **Easy** or **medium** (single-domain, sufficient investigation, no mandatory triggers) → architect synthesizes the plan without strategists; **medium** (multi-domain / high uncertainty / cross-cutting) or **hard** → architect decomposes and spawns scoped **`strategist`** subagents. **Strategist** and other planning specialists also run the same Claude Context readiness gate before discovery; bash/glob fallback is allowed only when MCP is unavailable or indexing still fails after retry (`MCP_FALLBACK` in output). Stage sizing: aim **3–7 stages**; split stages that would exceed **~15 developer tool rounds** or **>3 substantive files** each. Other types: architect invokes matching specialist (`debugger`/`refactor`/`review`/`designer`) as needed. Prototype Design uses the required intake → `designer` → GitHub issue implementation plan with `design_delivery: prototype-required` → orchestrate flow.
3. `architect` invokes `scribe` to write artifacts to approved docs paths (mandatory step). Issue-backed paths use `to-issues` / `publish-targeted-issue` — never `.plan/feature.*` files.
4. User switches to `orchestrate`.
5. `orchestrate` ensures issue backlog is available; if missing, dispatches `scribe` to write it.
6. `orchestrate` asks **"Run preflight now? (yes/no)"** unless preflight already passed or was declined this session; does not show work options until answered. **yes** → repair-first bootstrap: **`worktree-env`** (once, with completion trust) then **`preflight`** agent (auto-repair deps/runtime/indexing once); **no** → skip preflight for the session. **Either way:** run **checkout identity gate** (`checkout-contract.sh`) to capture current `impl_repo_path` and `branch` before work selection or implementation. Subagents must not create or switch branches.
7. `orchestrate` runs Claude Context readiness (`get_indexing_status` → `index_codebase` if needed).
8. `orchestrate` shows the **work-selection menu** verbatim (**(1)** GitHub backlog first; **(2)** Sysbox sandbox build/refresh for the current feature branch). On **(1)**, run the GitHub `feature:<slug>` backlog. On **(2)**, run **Sandbox feature build mode** (Task `developer` + `docker-sandbox`; no issue queue; support later **refresh** / **expose** / **destroy**). **(3)** / **(4)** route to `architect` or clarified scope as in the orchestrate agent.
9. Preflight may be re-run only when the user asks or after `ENV_BLOCKED` remediation.
10. `orchestrate` dispatches one stage at a time to `developer`, `frontend-dev`, or `ux-dev` (by stage Owner). Pass `impl_repo_path`, `expected_branch`, and `branch_policy` on every implementation Task. Design artifacts use `Owner: ux-dev`; `ux-dev` outputs HTML-only files to `.prototype/<slug>/`.
11. Execution subagent returns completion report (`stage_id`, files, tests, checks, blockers, risks, next input).
12. `orchestrate` dispatches next stage only after successful handoff.
13. For final completion, run `code-review` per stage; run final code-review when all stages complete.
14. **CodeRabbit gate** (once per orchestration, after final code-review / entire GitHub queue, before difficulty gates and architect): **medium/hard** — orchestrate Tasks **`review`** with `execution_mode: orchestrate_coderabbit_gate` and **`code-review`** skill on **all** changed files against `develop` by default; **never** per stage, per issue, or after remediation. BLOCKED → developer/frontend-dev fixes every non-deferred numbered finding → code-review confirms local fixes. **easy** — skip.
15. **Difficulty completion gates** (after CodeRabbit PASS when applicable): **easy** — none. **medium** — orchestrate invokes **`review`** with artifact + completion summary (+ CodeRabbit findings). **hard** — orchestrate invokes **`senior-dev`** (`execution_mode: scheduled_review`), then **`helper`** (strategy conformance). Remediation from these gates may update review artifact via scribe before handoff.
16. **Post-PR stabilization:** After `feature-finish-pr.sh` creates/updates the PR, orchestrate enters `pr_stabilization`: collects PR checks/comments and user acceptance feedback, classifies findings, executes fix-now items through developer→code-review, and presents checkpoints until the user finalizes stabilization. Produces a sealed PR stabilization report with `ready_for_architect` or `blocked` status and a feedback cutoff timestamp.
17. When stabilization complete: orchestrate prints the mandatory table-based completion handoff pointing to **impl architect option 4 Phase R** (not spec close). The handoff must name the exact `feature:<slug>` or `.plan` artifact, PR/skip reason, stabilization status, and feedback cutoff.
18. **Impl architect** (post-PR): Mode F Phase R distinguishes sealed (`ready_for_architect`) bundles from unsealed — sealed bundles skip routine comment triage and only create remediation for new material issues after the cutoff. Remediation loop with orchestrate; Phase 1 accepts issues (`state:done`, open); Phase 2 docs on feature branch. **Spec feature-complete** closes issues at merge, runs merge gate, closes PRD. Legacy `.plan`: architect Mode B review → docs → `archive_plan`.

At each stage handoff, orchestrate grades child output:

- `PASS` -> continue
- `NEEDS_RETRY` -> corrective feedback and rerun stage
- `BLOCKED` -> helper + scribe amendment path

## Escalation and Recovery (enforced)

Invoke `helper` immediately when any occurs:

- same stage fails verification twice
- unresolved blocker reported by execution subagent
- code-review reports failed criteria requiring strategy change
- execution reports `ENV_BLOCKED` (runtime/toolchain mismatch)

Recovery loop:

1. `helper` diagnoses and proposes minimal amendment.
2. `scribe` updates existing artifact in place.
3. resume with next indicated stage.

Do not advance stages until helper amendment is applied.
Do not allow repeated test-command retries under unresolved environment mismatch.
Preflight is user-opt-in at session start (`yes` / `no`); work selection follows. **Checkout identity is mandatory** even when preflight is declined — orchestrate captures current branch and repo root via `checkout-contract.sh` and passes them to every execution Task. Preflight is **environment-only** (env copies, `mise exec --`, `pnpm install`, indexing); it does not choose branches or checkouts. Preflight is **repair-first** with one auto-retry before a single hard-block message — no multi-option menus. Trust **`worktree-env`** completion evidence; do not re-run the same setup task without canonical contradiction. Do not require artifact writes for preflight output. Claude Context readiness runs after the preflight choice on fresh sessions. Smoke harness: `docs/smoke/preflight-bootstrap-validation.md`.

**Ubuntu Sysbox sandboxes (optional):** When the utilities opencode-server stack enables Sysbox siblings (`OPENCODE_SANDBOX_ENABLED=1`), the `sandbox` CLI is on PATH inside the server container. Preflight probes softly (`sandbox: ready|unavailable`); `unavailable` is not a hard fail (typical Mac / `OPENCODE_SANDBOX_MODE=off`). **Orchestrate does not load skill `docker-sandbox`** — it detects compose/Docker/review-URL need and instructs `developer` / `frontend-dev` / `code-review` Tasks to load it and wrap compose checks as `sandbox exec` (see `orchestrate-execution` Docker sandbox routing). **Menu (2)** runs **Sandbox feature build mode**: compose build/test or live stack for the current feature branch without the GitHub issue queue; user can later say **refresh** / **expose** / **destroy**. Optional web review: ask **“Publish review URL?”** once; on yes, `sandbox expose` publishes Caddy to `127.0.0.1:<hostPort>`; agents upsert a public hostname on the **existing** host cloudflared tunnel (**service type HTTPS**, `https://127.0.0.1:<hostPort>`, **No TLS Verify ON** — never HTTP service type) plus optional DNS for `https://{slug}.{apex}` (**never** create tunnels; **never** cloudflared-in-compose). App Infisical for Compose comes from repo `.env` (`./scripts/setup.sh projects …`, then **worktree-env** on linked worktrees) — not OpenCode server Infisical injection. Do not invent host Docker/Sysbox usage when the probe fails. **Not** Cloudflare Workers Sandbox (`skills/cloudflare/references/sandbox/`).

**Config on the Docker server:** Agents/skills come from `CONFIG_REPO` / `CONFIG_REF` cloned at **image build** (host `~/.config/opencode` is never mounted). After merging orchestrate/`docker-sandbox` wiring to the config branch used by Ubuntu, rebuild: `docker compose build --no-cache opencode && docker compose up -d opencode` (never `down -v`).

**Senior-dev escalation (operator-triggered, user confirmation required):** When developer reports `STAGE_STUCK` and the operator asks to escalate, orchestrate stops, asks the user to confirm, then invokes `senior-dev`. **Exception:** for **`Difficulty: hard`**, after all stages pass the final code-review, orchestrate invokes `senior-dev` for **scheduled post-implementation review** without that confirmation (not the same as mid-stage escalation).

## Subagent Loop Exit Strategy (enforced)

When a subagent repeats the same completion message or stalls:

1. **OpenCode config**: `steps` caps agentic iterations per session — e.g. scribe `8`, developer/frontend-dev `45`, architect `30`, orchestrate `100`, primaries and subagents are bounded. See `opencode.json` `agent` block.
2. **Orchestrator loop detection**: If the same or near-identical child report is received 2+ times, treat as `BLOCKED`, invoke `helper`, and amend the same artifact via `scribe` before any retry.
3. **Scribe exit rule**: Scribe returns exactly once per task. After reporting path + operation + summary, it stops.
4. **Developer anti-loop rule**: Developer must not repeat the same verbal intent (e.g. "Let me create X"); one statement, then execute. If the same failing command repeats twice without meaningful change, return `blocker_code: STAGE_STUCK` and stop.
5. **Manual escape**: Use `Ctrl+C` or session interrupt. Resume in a new session with artifact path if needed.
6. **Manual handoff (Task did not return):** If a subagent completed and produced a report but the Task did not return control to the orchestrator, switch to the `orchestrate` agent and paste the completion report. The orchestrator will grade it and proceed to the next stage. Do not message the subagent again—it has already completed.

Provider-level `timeout` (e.g. 300000ms) and per-model **`temperature` / `top_p` / `frequency_penalty`** are set under `provider.<name>.models.<id>.options` in `opencode.json` to reduce variance and wasted tokens (e.g. lower temp for execution, gentle `frequency_penalty` for DeepSeek).

## Model routing (Go-first, cost-tiered)

| Layer | Agents | Primary model | Fallback |
| --- | --- | --- | --- |
| High-volume execution | `developer`, `frontend-dev`, `orchestrate`, `helper`, `debugger`, `refactor`, `review` | `opencode-go/deepseek-v4-flash` | `opencode/deepseek-v4-flash` when Go quota exhausted |
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
- `code-review` checks conformance against:
  - original feature acceptance criteria (`.plan/feature.<slug>.md`)
  - review remediation criteria (`.plan/review.<slug>.md`) when review path is active.
- If code-review fails:
  - update the same `review.<slug>.md` artifact in place through `scribe`
  - mark completed tasks
  - append remediation tasks
  - append dated `IterationNotes`
  - invoke `helper` when repeated failures or blocker persists
  - repeat `developer` -> `code-review` cycle

## MCP Usage Policy

Primaries and execution agents should use MCP only when it reduces uncertainty:

- **`claude-context`**: Semantic code search keyed by **absolute path** (not only the OpenCode workspace). Pass the absolute path of the repo under investigation to `get_indexing_status`, `index_codebase`, and `search_code`. From the **spec repo**, resolve sibling impl paths via `bin/project/spec/lib/resolve_impl_path.sh` (`../<repo-basename>` beside spec). Use during planning (architect, **strategist**, debugger, refactor, review, document, designer). Discovery-heavy agents must run a readiness gate first (`get_indexing_status` for the target path; if needed `index_codebase`) and may fall back to bash/glob (`rg`, `find` on the sibling path) only when MCP is unavailable or indexing still fails after retry, with `MCP_FALLBACK` recorded in output. `orchestrate` also runs a lightweight readiness check on fresh startup even when full preflight is skipped.

  **Host vs Docker:** Toggle `mcp.claude-context.enabled` in `opencode.json`. Use **`true`** for local-only Desktop/CLI; use **`false`** on the host when Desktop attaches to the Docker OpenCode server (indexing then runs in the container against Milvus). Do not enable both — see [README — Claude Context indexing](../README.md#claude-context-indexing-host-vs-docker-server). Indexing is optional; OpenCode works without it.
- **`mcpjungle`**: The authenticated gateway for every managed upstream MCP server. The OpenCode configuration uses `MCPJUNGLE_OPENCODE_TOKEN` from the server runtime environment; upstream credentials and OAuth grants remain owned by MCPJungle. Context7, `cloudflare-api`, `cloudflare-docs`, and `docs-mcp-server` are available through this gateway. Use Cloudflare Docs instead of Context7 for Cloudflare-specific documentation.
- **`claude-context`**: The only permitted non-MCPJungle integration.

**Cloudflare skills** (narrow set from [cloudflare/skills](https://github.com/cloudflare/skills)): `cloudflare` (DNS/domains + platform guidance for web apps), `wrangler` (local run/deploy), `workers-best-practices`. Allowed on `architect`, `developer`, `senior-dev`, `frontend-dev`, `debugger`. Authentication is managed by MCPJungle; never start Cloudflare OAuth from OpenCode.

**Review-app DNS:** Feature URLs use skill `docker-sandbox` (`sandbox expose` for localhost publish of nested Caddy) plus `cloudflare-api` through MCPJungle for tunnel public hostname → `https://*********:<hostPort>` with **No TLS Verify ON** (never copy expose’s `http://` scheme; never HTTP service type) and optional CNAME upsert to the **existing** host tunnel — never `cloudflared tunnel create`.

If a user says "look at the prototype", check `docs-mcp-server` through `mcpjungle` first and record what was used.

**Execution phase**: Developer and frontend-dev receive `FilesToChange` from the plan; do not use claude-context for discovery unless the plan is ambiguous and the assigned stage requires locating additional files.

## Documentation Gate (Required)

After architect's review sign-off, architect invokes `document` to generate content, then `scribe` to write:

- `docs/changelog/<date>-<slug>.md`
- `docs/guides/<feature-slug>.md`
- `docs/architecture/<feature-slug>.md`

Use templates in:

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

- Architected features include required sections (`Difficulty`, `StagePlan`, `StageAcceptanceChecks`, `CompletionReport`, `CodeReviewInputs`, `DocumentationOutputs`).
- Primary agents cannot edit files directly (`edit: deny`).
- Scribe can write to approved docs markdown paths, `README.md`, and `.env.example` (when parent supplies path and content).
- Helper never writes directly and only amends existing artifacts via `scribe`.
- Helper is invoked on repeated code-review failure or unresolved blockers.
- Environment/toolchain blockers (`ENV_BLOCKED`) halt stage progression and require helper+scribe amendment before retry.
- Stage dispatch is one-at-a-time with completion handoff.
- UI work routes to `frontend-dev`; non-UI work routes to `developer`; prototype generation from design briefs routes to `ux-dev` (outputs to `.prototype/<slug>/`).
- Senior-dev: user confirmation for mid-stage **escalation**; **no** confirmation for **hard** Difficulty scheduled post-code-review review.
- Orchestrate may invoke **`review`** after execution for **medium** Difficulty.
- Orchestrator completion is table-driven and names the exact feature/artifact to sign off; it must include the copy/paste architect prompt, not a generic "Switch to architect" sentence.
- Code-review receives original feature artifact and review artifact (if present).
- Code-review report includes criterion-level evidence.
- Code-review failure updates the existing review artifact (no fragmented review files).
- No stale references to removed agents (`fix`, `pr-reviewer`, `refactorer`). Execution uses `developer` (not built-in `build`) in the custom pipeline.
- MCP lookups are used only when prompt/context indicates need.
- Final docs are generated by architect (document + scribe) after review sign-off.
