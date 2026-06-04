# Stage-Based Orchestration Runbook

**Config precedence:** `opencode.json` is the sole runtime authority for models, `steps` caps, MCP, and global `permission` / `instructions`. Agent markdown frontmatter describes behavior; numeric limits in frontmatter are superseded by `opencode.json` when both exist.

## Two-mode workflow

| Mode | Planning | Execution source of truth |
|------|----------|----------------------------|
| **Spec / GitHub** (default) | Spec: PRD + fanout; impl: **issue-expand** (architect option 1) | GitHub child issues (`feature:<slug>`, `opencode-task-yaml` + `stages[]`) |
| **Legacy local** | Architect option 2 → scribe writes `.plan/feature.<slug>.md` | Active `.plan/*.md` (excludes `*.completed.md`) |

See [FEATURE-PIPELINE.md](FEATURE-PIPELINE.md) for the numbered pipeline. **Fanout alone does not populate `stages[]`** — run issue-expand in each implementation repo before orchestrate on the spec path.

## GitHub-always principle (spec path)

After `bin/fanout`, **GitHub issues are the execution source of truth**. Do not create parallel `.plan/issue.*` files for spec-driven features. Orchestrate reads **issue bodies** (`opencode_meta`, `stages[]`, Implementation planning markdown), not the full PRD, unless a subagent explicitly needs PRD context. Ephemeral caches (`tmp/feature-context.md`) are not authoritative.

## Stack bootstrap (`setup-project`)

| Who | Command / action |
|-----|------------------|
| **Human (once per stack)** | `cd ~/code/APP && setup-project` from project parent (`GH_ORG` or `--org` required) |
| **OpenCode (spec repo)** | architect → **setup-project** skill: interview, `docs/agents/repos.md`, Task **stack-bootstrap** per impl repo |

Shell bootstrap syncs `bin/*` and templates; registry **INCOMPLETE** until the OpenCode interview fills TBD fields is normal (`exit 3` / `NEXT:`). Re-run `setup-project` after adding sibling impl repos. Details: [README.md](../README.md) Setup, [skills/setup-project/SKILL.md](../skills/setup-project/SKILL.md).

## Push cadence (issue-backed execution)

- **Commit locally** after each passing stage using the stage `commit_message` from `opencode-task-yaml` (append `Refs: #<issue_number>`). Local commits are fine; remote pushes are not part of the per-issue loop.
- **Do not push** the feature branch after each issue or stage. Avoid triggering GitHub Actions, hosted CodeRabbit, and other remote checks mid-feature unless the user explicitly requests remote visibility.
- **Push/open PR only once** after the full feature queue is complete, the one-shot local CodeRabbit CLI review has run, and all CodeRabbit findings have been fixed or explicitly resolved locally.
- **Do not** treat “code already exists in the tree” as “ticket done” — map acceptance to tests and yaml `stages[]`.

## Overview

- **Built-in agents:** `plan` uses DeepSeek V4 Flash; `build` uses MiniMax M3 in `opencode.json` for generic/quick tasks.
- **Primary planning mode** (`architect`) — read-only with **allow-by-default bash** (explicit deny for destructive/mutating shell): exploration, `gh`, `bin/*`, `setup-project --check-only`; artifact writes via **scribe** / **stack-bootstrap** Tasks only. Invokes: `debugger`, `refactor`, `review`, `document`, `designer`, `scribe`. Never invokes `frontend-dev`, `developer`, or `orchestrate`. Prompts user to switch to orchestrate when done; receives user back for review + docs after orchestrate completes. **Skills:** `architect-plan` (new planning, features, specialists, Mode A); `architect-review` (post-implementation Mode B only). The monolithic `architect` skill package is removed.
- **Primary execution mode** (`orchestrate`) runs delegated stage execution and recovery flow. Reads `## Difficulty` from the artifact (`easy` \| `medium` \| `hard`; default `medium` if missing). After **all** stages/issues pass the final verifier (one gate per artifact or `feature:<slug>`): **medium/hard** — **CodeRabbit gate** via `review` + `code-review` skill (single CLI review of accumulated changes against `develop` by default; no CodeRabbit validation reruns); **easy** — skips CodeRabbit. **Never** runs CodeRabbit per GitHub issue, mid-stage, or after CodeRabbit remediation. Then: **easy** — no further gates; **medium** — `review` post-execution check; **hard** — `senior-dev` (scheduled review, no user confirmation) then `helper` (strategy conformance). On completion, prints a table-based sign-off handoff naming the exact feature/artifact, PR, work completed, gates, CodeRabbit, findings/risks, and the copy/paste prompt for architect. **Skills:** `orchestrate-execution` (bootstrap: preflight yes/no, optional env gate, work selection, stage loop, grading, completion gates); `orchestrate-recovery` (helper triggers, loops, env, escalation, manual paste). The monolithic `orchestrate` skill package is removed.
- **Planning specialists** (`debugger`, `refactor`, `review`, `designer`) — read-only subagents of architect; return plan drafts, never write code. `designer` synthesizes design briefs for Prototype Design. The **`review`** agent may Task **`security-reviewer`**, **`performance-reviewer`**, and **`doc-reviewer`** when change scope warrants (see `skills/review/SKILL.md`).
- **Documentation generator** (`document`) — read-only; generates changelog/guides/architecture content; architect invokes, then scribe writes.
- **Execution subagents** (`developer`, `frontend-dev`, `ux-dev`) — coding agents invoked by orchestrate only; architect never invokes them. `ux-dev` generates HTML-only framework-agnostic prototypes from design briefs into `.prototype/<slug>/`.
- **Senior-dev** (`senior-dev`) — orchestrator subagent. **Escalation:** operator-triggered when developer is stuck; orchestrator asks user to confirm before invoking. **Scheduled gate:** for `Difficulty: hard`, after all stages pass verifier, orchestrate invokes senior-dev for post-implementation review **without** that confirmation. Diagnosis + fix on escalation; read-only review on scheduled gate unless scope says otherwise.
- **Artifact writer** (`scribe`) — only write path; writes plan artifacts, docs, `README.md`, and `.env.example` when delegated (invoked by architect and orchestrate).
- **Recovery replanner** (`helper`) diagnoses stuck/failed states and amends existing artifacts through `scribe`. On **hard** Difficulty, orchestrate may also invoke helper for **strategy conformance** (reasoning-only compare plan vs implementation summary).
- **Verifier** (`verifier`) is an independent evidence gate and never writes code.
- **Mentor** (`mentor`) is optional and explanatory only.

## Agent Matrix

| Role                    | Agents                                       | Model Tier | Responsibility                                                                                                                                                       |
| ----------------------- | -------------------------------------------- | ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Primary (planning)      | `architect`                                  | smart      | Read-only: explore, report, draft. Plan mode: scribe writes artifact → switch to orchestrate. Post-implementation: review → sign-off → document → scribe writes docs → scribe archives plan to `.plan/<type>.<slug>.completed.md` |
| Coordinator             | `orchestrate`                                | smart      | Execute stages, grade children, helper recovery, optional `review` (medium) / `senior-dev`+`helper` (hard) after final verifier, dispatch scribe. Plan picker lists **active** `.plan/*.md` only (excludes `*.completed.md`). Startup: optional preflight prompt → **`worktree-env`** + **`developer`** preflight if **yes**, then work menu.                       |
| Planning specialists    | `debugger`, `refactor`, `review`, `designer` | smart      | Return type-specific plan drafts to architect. `designer` uses Gemini 3 Flash. `review` may also be invoked by orchestrate on **medium** Difficulty after execution.    |
| Documentation generator | `document`                                   | fast       | Generate changelog/guides/architecture content; architect invokes, scribe writes                                                                                     |
| Artifact writer         | `scribe`                                     | fast       | Write/update plan artifacts, docs, `README.md`, `.env.example` from architect/orchestrate content                                                                     |
| Recovery                | `helper`                                     | fast       | Replan minimal strategy deltas and trigger artifact amendment                                                                                                        |
| Execution               | `developer`, `frontend-dev`, `ux-dev`        | smart/fast | Execute assigned `stage_id` tasks. `ux-dev` uses `google/gemini-3-flash-preview` (see `opencode.json`) for HTML-only prototype generation into `.prototype/<slug>/`.                                            |
| Operator escalation     | `senior-dev`                                 | smart      | Escalation: operator + user confirm when stuck. **Hard** completion gate: auto-invoked post-verifier for scheduled review.                                                                                    |
| Verification            | `verifier`                                   | fast       | Verify acceptance criteria with traceable evidence                                                                                                                   |

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

- **Skill:** Each agent may load only its core skill(s). No `skill: { "*": "allow" }`. Explicit allow per skill (e.g. `architect-plan` + `architect-review` for architect; `orchestrate-execution` + `orchestrate-recovery` for orchestrate; `developer`, `preflight` for developer; `worktree-env` for **`worktree-env`**).
- **Architect subagents** (`debugger`, `refactor`, `review`, `document`, `designer`): `task: { "*": deny }` — they cannot invoke scribe or any other agent. Return content only to parent; architect handles scribe handoff.

## OpenRouter preset (limit “Others” model spend)

OpenCode does not define an in-repo model allowlist beyond [`opencode.json`](../opencode.json). To avoid accidental traffic to untuned models (often grouped as “Others” in OpenRouter Activity):

1. In the [OpenRouter](https://openrouter.ai/) dashboard, create a **preset** whose allowed model list matches **only** the models you use in `opencode.json` (including `:nitro` variants if you use them).
2. Bind that preset to the **API key** OpenCode uses, per OpenRouter’s current key/preset UX.

## Canonical Flow

1. `architect` asks for plan type (Feature/Debug/Refactor/Review/Document/Prototype Design) when request is greeting/unspecified.
2. **Features:** architect classifies **`## Difficulty`** (`easy` \| `medium` \| `hard`), runs a Claude Context readiness check (`get_indexing_status` → `index_codebase` if needed), then investigates with `claude-context`. **Easy** or **medium** (single-domain, sufficient investigation) → architect synthesizes the plan without strategists; **medium** (multi-domain / high uncertainty / cross-cutting) or **hard** → architect decomposes and spawns scoped **`strategist`** subagents. **Strategist** and other planning specialists also run the same Claude Context readiness gate before discovery; bash/glob fallback is allowed only when MCP is unavailable or indexing still fails after retry (`MCP_FALLBACK` in output). Stage sizing: aim **3–7 stages**; split stages that would exceed **~15 developer tool rounds** or **>3 substantive files** each. Other types: architect invokes matching specialist (`debugger`/`refactor`/`review`/`designer`) as needed. For Prototype Design: design intake → `designer` → scribe writes `.plan/design.<slug>.md`.
3. `architect` invokes `scribe` to write the artifact to `.plan/<type>.<slug>.md` (mandatory step).
4. User switches to `orchestrate`.
5. `orchestrate` ensures artifact exists; if missing, dispatches `scribe` to write it.
6. `orchestrate` asks **“Run preflight now? (yes/no)”** unless preflight already passed or was declined this session; does not show work options until answered. **yes** → **`worktree-env`** then **`developer`** preflight; **no** → skip preflight for the session.
7. `orchestrate` runs Claude Context readiness (`get_indexing_status` → `index_codebase` if needed).
8. `orchestrate` shows the **work-selection menu** verbatim (**(1)** GitHub backlog first; **(4)** legacy `.plan` last; numbers match display order). On **(1)**, run the GitHub `feature:<slug>` backlog. On **(4)** only, **read `.plan/` via a filesystem tool** (glob or list), list **active** plans (omit `*.completed.md`) from that output only—never from memory—and ask the user to select one. **(2)** / **(3)** route to `architect` or clarified scope as in the orchestrate agent.
9. Preflight may be re-run only when the user asks or after `ENV_BLOCKED` remediation.
10. `orchestrate` dispatches one stage at a time to `developer`, `frontend-dev`, or `ux-dev` (by stage Owner). Design artifacts use `Owner: ux-dev`; `ux-dev` outputs HTML-only files to `.prototype/<slug>/`.
11. Execution subagent returns completion report (`stage_id`, files, tests, checks, blockers, risks, next input).
12. `orchestrate` dispatches next stage only after successful handoff.
13. For final completion, run `verifier` per stage; run final verifier when all stages complete.
14. **CodeRabbit gate** (once per orchestration, after final verifier / entire GitHub queue, before difficulty gates and architect): **medium/hard** — orchestrate Tasks **`review`** with `execution_mode: orchestrate_coderabbit_gate` and **`code-review`** skill on **all** changed files against `develop` by default; **never** per stage, per issue, or after remediation. BLOCKED → developer/frontend-dev fixes every non-deferred numbered finding → verifier confirms local fixes. **easy** — skip.
15. **Difficulty completion gates** (after CodeRabbit PASS when applicable): **easy** — none. **medium** — orchestrate invokes **`review`** with artifact + completion summary (+ CodeRabbit findings). **hard** — orchestrate invokes **`senior-dev`** (scheduled review), then **`helper`** (strategy conformance). Remediation from these gates may update review artifact via scribe before handoff.
16. When gates complete: orchestrate prints the mandatory table-based completion handoff: **Sign-off target**, **Work completed**, **Gates and checks**, **CodeRabbit**, **Key findings / risks**, **Next steps**, and **Copy/paste sign-off script**. The handoff must name the exact `feature:<slug>` or `.plan` artifact and PR/skip reason; architect still runs Mode B/Mode F review + docs (authoritative sign-off).
17. Architect (post-implementation): invokes `review` for sign-off. If remediation: scribe writes review artifact → user switches to orchestrate → developer applies fixes → verifier. If sign-off: architect invokes `document` → scribe writes docs → scribe **archives** the primary implementation artifact to `.plan/<type>.<slug>.completed.md` via `operation: archive_plan` so future orchestrate sessions do not offer it as a runnable plan.

At each stage handoff, orchestrate grades child output:

- `PASS` -> continue
- `NEEDS_RETRY` -> corrective feedback and rerun stage
- `BLOCKED` -> helper + scribe amendment path

## Escalation and Recovery (enforced)

Invoke `helper` immediately when any occurs:

- same stage fails verification twice
- unresolved blocker reported by execution subagent
- verifier reports failed criteria requiring strategy change
- execution reports `ENV_BLOCKED` (runtime/toolchain mismatch)

Recovery loop:

1. `helper` diagnoses and proposes minimal amendment.
2. `scribe` updates existing artifact in place.
3. resume with next indicated stage.

Do not advance stages until helper amendment is applied.
Do not allow repeated test-command retries under unresolved environment mismatch.
Preflight is user-opt-in at session start (`yes` / `no`); work selection follows. Do not require artifact writes for preflight output. Claude Context readiness runs after the preflight choice on fresh sessions.

**Senior-dev escalation (operator-triggered, user confirmation required):** When developer reports `STAGE_STUCK` and the operator asks to escalate, orchestrate stops, asks the user to confirm, then invokes `senior-dev`. **Exception:** for **`Difficulty: hard`**, after all stages pass the final verifier, orchestrate invokes `senior-dev` for **scheduled post-implementation review** without that confirmation (not the same as mid-stage escalation).

## Subagent Loop Exit Strategy (enforced)

When a subagent repeats the same completion message or stalls:

1. **OpenCode config**: `steps` caps agentic iterations per session — e.g. scribe `5`, developer/frontend-dev `45`, architect `30`, orchestrate `50`, primaries and subagents are bounded. See `opencode.json` `agent` block.
2. **Orchestrator loop detection**: If the same or near-identical child report is received 2+ times, treat as `BLOCKED`, invoke `helper`, and amend the same artifact via `scribe` before any retry.
3. **Scribe exit rule**: Scribe returns exactly once per task. After reporting path + operation + summary, it stops.
4. **Developer anti-loop rule**: Developer must not repeat the same verbal intent (e.g. "Let me create X"); one statement, then execute. If the same failing command repeats twice without meaningful change, return `blocker_code: STAGE_STUCK` and stop.
5. **Manual escape**: Use `Ctrl+C` or session interrupt. Resume in a new session with artifact path if needed.
6. **Manual handoff (Task did not return):** If a subagent completed and produced a report but the Task did not return control to the orchestrator, switch to the `orchestrate` agent and paste the completion report. The orchestrator will grade it and proceed to the next stage. Do not message the subagent again—it has already completed.

Provider-level `timeout` (e.g. 300000ms) and per-model **`temperature` / `top_p` / `frequency_penalty`** are set under `provider.openrouter.models.<id>.options` in `opencode.json` to reduce variance and wasted tokens (e.g. lower temp for execution, gentle `frequency_penalty` for DeepSeek).

## Model routing (OpenRouter)

| Layer | Agents | Model |
| --- | --- | --- |
| Planning (primary) | `architect`, `plan` | DeepSeek V4 Flash |
| Scoped planning | `strategist` | DeepSeek V4 Pro |
| Orchestration | `orchestrate` | MiniMax M3 |
| Primary implementation | `developer`, `frontend-dev`, `build` | MiniMax M3 |
| Design / prototypes | `designer`, `ux-dev` | Gemini 3 Flash |
| Senior / security depth | `senior-dev`, `security-reviewer` | DeepSeek V4 Pro |
| Fast utility | `debugger`, `helper`, `refactor`, `verifier`, `review`, `performance-reviewer` | DeepSeek V4 Flash |
| Teaching | `mentor` | Qwen3.7 Max |
| Vision | `vision` | Qwen3 VL |
| Writing / docs | `scribe`, `document`, `doc-reviewer`, `stack-bootstrap`, `worktree-env` | GPT-5 Nano |

Runtime authority: `opencode.json`. Agent frontmatter `model:` should match for changed agents.

`default_agent` is set to `orchestrate` so execution sessions start with the coordinator as the active primary context.

## Review and Verifier Interaction

- `review` focuses on bug/correctness/security risks and fix planning.
- `verifier` checks conformance against:
  - original feature acceptance criteria (`.plan/feature.<slug>.md`)
  - review remediation criteria (`.plan/review.<slug>.md`) when review path is active.
- If verifier fails:
  - update the same `review.<slug>.md` artifact in place through `scribe`
  - mark completed tasks
  - append remediation tasks
  - append dated `IterationNotes`
  - invoke `helper` when repeated failures or blocker persists
  - repeat `developer` -> `verifier` cycle

## MCP Usage Policy

Primaries and execution agents should use MCP only when it reduces uncertainty:

- **`claude-context`**: Semantic code search in workspace. Use during planning (architect, **strategist**, debugger, refactor, review, document, designer). Discovery-heavy agents must run a readiness gate first (`get_indexing_status`; if needed `index_codebase`) and may fall back to bash/glob only when MCP is unavailable or indexing still fails after retry, with `MCP_FALLBACK` recorded in output. `orchestrate` also runs a lightweight readiness check on fresh startup even when full preflight is skipped.
- **`context7`**: Up-to-date docs for 9000+ external libraries. Use when framework/library API behavior is uncertain. Limit to 3 calls per question.
- **`docs-mcp-server`**: Internal docs, prototypes, linked repos, architecture notes.
- **`dash-api`**: API/library contract lookup when behavior is unclear.

If a user says "look at the prototype", check `docs-mcp-server` first and record what was used.

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
Artifact: .plan/<type>.<slug>.md
Stage IDs: <stage-id-list>
Scope in: <paths/components>
Scope out: <explicit exclusions>
Acceptance checks: <commands>
Completion report required: stage_id, files_changed, `changes` [{ file, summary, strategy_step }], tests_run, acceptance_check_status, blockers, residual_risks, next_stage_input
```

Use this when dispatching markdown writes to `scribe`:

```text
Target path: .plan/<type>.<slug>.md, docs/<section>/<name>.md, README.md, or .env.example
Operation: create|update
Content: full body from parent (markdown or .env.example template lines)
Constraints: approved paths only; markdown or .env.example only
```

## Troubleshooting: CRLF / `env: bash\r`

On macOS/Linux, **CRLF** line endings in `bin/*` shell scripts break the shebang (`env: bash\r: No such file or directory`). OpenCode templates are LF; spec-repo copies are normalized on every **`sync_spec_tooling.sh`** run (`strip_crlf` after install).

**Agents:** Do not fix CRLF file-by-file with sed/Python. Run one of:

```bash
# From spec repo (when ./bin/* fails)
bash bin/feature-upgrade <slug>
"$HOME/.config/opencode/bin/stack/sync_spec_tooling.sh" "$(pwd)"

# From project parent (wrapper syncs tooling before exec)
feature-upgrade <slug>
```

**Prevention:** Spec repos receive [`.gitattributes`](../templates/spec-repo/.gitattributes) on sync so Git keeps `bin/**` as LF. Re-run **`setup-project`** or **`sync_spec_tooling.sh`** after pulling OpenCode config updates that touch `templates/spec-repo/bin/`.

Config-repo CI runs `scripts/check-crlf.sh` on `bin/`, `scripts/`, `templates/`, and `.gitattributes`.

## Smoke Checklist

- Artifact includes required schema sections (`Difficulty`, `StagePlan`, `StageAcceptanceChecks`, `CompletionReport`, `VerifierInputs`, `DocumentationOutputs`).
- Primary agents cannot edit files directly (`edit: deny`).
- Scribe can write to `.plan`, docs markdown paths, `README.md`, and `.env.example` (when parent supplies path and content).
- Helper never writes directly and only amends existing artifacts via `scribe`.
- Helper is invoked on repeated verifier failure or unresolved blockers.
- Environment/toolchain blockers (`ENV_BLOCKED`) halt stage progression and require helper+scribe amendment before retry.
- Stage dispatch is one-at-a-time with completion handoff.
- UI work routes to `frontend-dev`; non-UI work routes to `developer`; prototype generation from design briefs routes to `ux-dev` (outputs to `.prototype/<slug>/`).
- Senior-dev: user confirmation for mid-stage **escalation**; **no** confirmation for **hard** Difficulty scheduled post-verifier review.
- Orchestrate may invoke **`review`** after execution for **medium** Difficulty.
- Orchestrator completion is table-driven and names the exact feature/artifact to sign off; it must include the copy/paste architect prompt, not a generic "Switch to architect" sentence.
- Verifier receives original feature artifact and review artifact (if present).
- Verifier report includes criterion-level evidence.
- Verifier failure updates the existing review artifact (no fragmented review files).
- No stale references to removed agents (`fix`, `pr-reviewer`, `refactorer`). Execution uses `developer` (not built-in `build`) in the custom pipeline.
- MCP lookups are used only when prompt/context indicates need.
- Final docs are generated by architect (document + scribe) after review sign-off.
