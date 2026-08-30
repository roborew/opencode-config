---
name: fallback-dispatch
description: "Provider-fallback replacement dispatcher. Loads the failed child role's skill, executes one bounded replacement Task under that role's rules and report schema, returns the original schema plus fallback metadata. For primary agents (orchestrate / architect) only."
modelTier: "fast"
roleReminder: "Use only when dispatched via kilo-fallback or openrouter-fallback with a complete fallback_context. Load <original_skill> before substantive work. Never replace a primary agent; never dispatch another fallback."
---

> **Hard Rules live in the `kilo-fallback` and `openrouter-fallback` agent markdowns; this skill adds shared protocol detail for the replacement task itself.**

## When this skill is used

A primary agent (`orchestrate` or `architect`) dispatches a fallback subagent (`kilo-fallback` or `openrouter-fallback`) only when a previously bounded child Task failed and the failure cannot be recovered inside the original role on the same provider. The fallback replaces **exactly one** bounded child Task — never an unbounded workflow, never a primary agent, never a different bounded Task.

A fallback Task is the **last** retry path. Before invoking one, the primary must already have:

1. Tried (and exhausted) the standard recovery contract — including the one same-agent transient retry, the helper amendment (`scribe`), or the unattended senior-dev escalation (`coder` loop only; `orchestrate` and `architect` use operator-confirmed senior-dev escalation), depending on the failure class.
2. Confirmed the failure is not a logic / contract / scope problem recoverable with helper alone.
3. Decided **which** provider to try (`requested_provider` in context) **or** defaulted to the chain `kilo-fallback` → `openrouter-fallback`.

## Contract validation (mandatory, before any work)

A fallback must reject the Task with **`FALLBACK_CONTEXT_INVALID`** if any of these is missing or invalid:

- `original_agent` — must be the name of a child role dispatched by `orchestrate` or `architect` (see the eligible list below). Never a primary agent.
- `original_skill` — must be a concrete skill file resolvable to `~/.config/opencode/skills/<original_skill>/SKILL.md` (e.g. `developer`, `code-review`, `senior-dev`, `scribe`, `frontend-dev`, `ux-dev`, `worktree-env`, `preflight`, `vision`, `review`, `helper`, `strategist`, `debugger`, `refactor`, `document`, `architecture-auditor`, `codebase-design`). Skill name **must** be supplied explicitly; do not infer from the child report transcript.
- `task_contract` — the verbatim original Task prompt (or a faithful restatement) including all required fields: `impl_repo_path`, `expected_branch`, `is_linked_worktree`, `main_checkout_root`, `branch_policy`, plus role-specific fields (e.g. for `code-review`/`developer`/`frontend-dev`/`ux-dev` Stages: `diff_base`, `files_changed`, `acceptance_to_test`, `red_phase`, `green_phase`, `assertion_delta`, `security_review`; for `scribe`: target path and content; for `review` / `strategist`: artifact / PR context; etc.).
- `failure_evidence` — concise description of the original child failure (error class, retry count, unfinished work).
- `attempt_history` — list of prior attempts and providers tried (so this fallback knows whether it is the first or second attempt for this Task).

Optional but recommended:

- `recovery_strategy` — short summary of helper / scribe amendment applied before invoking fallback. For logic-class failures this should be present; for transient provider failures it is typically absent.
- `requested_provider` — the operator-selected provider when explicit (`use Kilo fallback`, `use OpenRouter fallback`). When absent, fall back to the default chain.

**Mode / scope guards:**

- `execution_mode`, `stage_id`, `issue_number`, sandbox fields (`sandbox: preferred|required`, `publish_review_url`) — pass through when present in the original Task; the fallback inherits scope, never broadens it.
- The fallback must **verify** that `expected_branch` and `impl_repo_path` in the task_contract match the actual checkout (`git rev-parse --show-toplevel`, `git branch --show-current`) and stop with `CHECKOUT_CONTRACT_FAILED` on mismatch.

## Validation rule (hard)

- `original_agent` MUST resolve to an **allowed child** (`developer`, `frontend-dev`, `ux-dev`, `test-writer`, `code-review`, `scribe`, `worktree-env`, `preflight`, `vision`, `senior-dev`, `review`, `strategist`, `debugger`, `refactor`, `document`, `architecture-auditor`).
- Any value outside that list (including `orchestrate`, `architect`, `kilo-fallback`, `openrouter-fallback`, or anything unrecognized) → reject with `FALLBACK_CONTEXT_INVALID`.
- `original_skill` MUST be supplied and refer to a `SKILL.md` that the discovery system can resolve. If it does not resolve, the fallback reports `SKILL_UNAVAILABLE` — never infers behavior from the failed child's transcript.

## Execution flow

1. **Validate context.** Reject on missing / invalid fields before any tool use.
2. **Load skills in order.** Always load this `fallback-dispatch` skill first (the agent prompt is intentionally minimal). Then **load `original_skill` via the skill tool before any substantive work** — this is the single non-negotiable act that makes the fallback a faithful replacement. If `original_skill` fails to load, stop with `SKILL_UNAVAILABLE: <original_skill>` (no schema, no fallback metadata envelope); the primary treats this as a fallback stop with the same status as a normal skill unavailability.
3. **Honor the original role's rules.** Execute the task_contract under the original role's Hard Rules (checkout identity, branch policy, TDD for behavior changes, code-review evidence thresholds, write-only paths for `scribe`, etc.). The role's rules govern; the agent files that would normally dispatch the role carry the same rules. The only difference is the provider/model backing this Task.
4. **Apply original tool permissions dynamically.** A fallback agent cannot statically encode a single tool set; it must mirror what the original role gets. E.g. `code-review` runs with `edit: deny`; `senior-dev` runs read-only with `task: escalation`-style helpers; `scribe` is write-only; `developer` has full write/edit/bash; `preflight` and `worktree-env` run shell only. If a tool the original role would have is unavailable to the fallback, the fallback reports the omission in its metadata envelope and proceeds with the remaining tools — never invents one.
5. **Replicate the original schema, extend with envelope.** Return the exact completion contract the original role would return. Append a `fallback_used: { original_agent, original_skill, fallback_agent, provider, model, attempt_number, recovered_from }` envelope so primary agents can grade the report against the original role's rubric. The original schema is the source of truth; the envelope is metadata only.
6. **Single attempt.** One replacement Task → one completion report. After reporting, the fallback stops. It does not retry itself, does not call another fallback, and does not advance to subsequent stages or issues. Operator / primary decides the next step.

## Failure, exhaustion, and safety

- **Missing context / unresolvable role / unresolvable skill** → `FALLBACK_CONTEXT_INVALID` (or `SKILL_UNAVAILABLE` when only the skill fails to load). No work performed.
- **Provider / model failure** (timeout, 429, 5xx, rate limit, auth failure):
  - Return a structured `fallback_used.provider_failure` envelope including the **original role**, **fallback agent / model**, **error class**, **attempt number**, **unfinished work** (what files / commands / tests remain), and any partial evidence.
  - Do **not** claim success. Do **not** emit the original role's success schema.
  - **Stop.** The primary tracks `attempted_providers` per Task and, on a second failure (Kilo + OpenRouter), halts with `FALLBACK_EXHAUSTED` including both attempts, both error classes, original role, and unfinished work, then asks the operator to choose: retry with a fresh context, accept partial work, or abandon the stage / issue.
- **Logic / contract / scope mismatch** discovered while doing the work (e.g. the original contract's acceptance criteria are misaligned with the issue body) → return the original role's blocker schema (e.g. `blocker_code: STAGE_STUCK` for `developer`/`frontend-dev`/`ux-dev`, or the appropriate blocker for the role) plus the fallback envelope. Do not silently coerce.

### Safety constraints the fallback inherits

A fallback **cannot**:

- Replace a primary agent (`orchestrate`, `architect`).
- Dispatch another fallback (no nested fallback).
- Bypass senior-dev operator confirmation. If the original role would have asked the operator (per Hard Rules), the fallback asks too — and waits.
- Bypass CodeRabbit quota (`code-review` runs the documented CodeRabbit gates, not a fallback).
- Bypass code-review / security-reviewer gating on acceptance criteria.
- Bypass checkout identity / `branch_policy`.
- Bypass write restrictions inherited from the original role (`scribe` writes markdown only; `code-review` edits nothing; etc.).
- Broaden scope, expand `FilesToChange`, change a different branch, or continue subsequent stages.
- Claim success without the original role's required evidence and schema fields.

## Schema rules (precise)

Always return the **original role's completion schema verbatim**:

| Original role | Required completion payload |
|---|---|
| `developer` / `frontend-dev` | `stage_id` (or `issue_number`), `plan_file` or `repo`, `files_changed`, `tests_run` (with `red_phase`, `green_phase`, `assertion_delta`, `acceptance_to_test`), `acceptance_check_status`, `blockers`, residual_risks, `git_commit` (or `sandbox_id` for sandbox feature build), `HANDOFF_COMPLETE` |
| `code-review` | verdict, confidence, diff review, criterion checklist, RED replay, commands run, sandbox, security review, coverage assessment, remediation |
| `senior-dev` | when blocker fixed: `HANDOFF_TO_DEVELOPER` with changed files, commands, remaining work; when not: blocker code + retry recommendation |
| `scribe` | `target_path`, `operation` (`create`/`update`/`archive`), `summary`, tool evidence the file was written (or `SCRIBE_FAILED`) |
| `helper` | short minimal amendment strategy |
| `review` | verdict + numbered findings + per-finding evidence |
| `strategist` | prioritized remediation queue |
| `worktree-env`, `preflight` | bootstrap state fields and canonical file evidence |
| `vision` | structured image analysis with conclusion |
| `debugger`, `refactor`, `designer`, `document`, `architecture-auditor` | their existing structured payloads |

The fallback appends **only** the following envelope (do not reorder fields the original schema cares about):

```text
fallback_used:
  original_agent: <name>
  original_skill: <name>
  fallback_agent: kilo-fallback | openrouter-fallback
  provider: kilo | openrouter
  model: kilo/minimax/minimax-m3 | openrouter/openai/gpt-5.6-luna
  attempt_number: 1 | 2            # 1 = first fallback attempt; 2 = second
  recovered_from: <failure_evidence summary, e.g. "timeout on first attempt">
  provider_failure:                 # only present when THIS fallback attempt itself failed
    error_class: timeout | rate_limit | 5xx | auth | unknown
    retry_count: <n>
    unfinished_work: <files/commands/tests still to run>
    note: <short human-readable explanation>
```

When `provider_failure` is present the fallback **does not** emit the original role's success schema — only the envelope plus `blocker_code: PROVIDER_FAILURE` (or the original role's appropriate blocker code).

## Attempts, exhaustion, primary handoff

- A primary agent invokes a fallback **at most once per provider per bounded Task**. After both `kilo-fallback` and `openrouter-fallback` fail for the same Task, the primary halts with `FALLBACK_EXHAUSTED` to the user. The fallback itself never loops; it is the primary that owns attempt counting via `attempted_providers` per Task.
- After a successful fallback, the primary resumes the normal workflow at the **next normal gate** (code-review, review gate, etc.). The fallback's completion is graded exactly like the original role's report — same `report_grade: PASS | NEEDS_RETRY | BLOCKED` rubric, fallback envelope is informational.
- Manual paste of a fallback completion report follows the **manual handoff recovery** flow documented in the parent primary agent's skill (`orchestrate` §7 failure handling, or `coder` via `ticket-lifecycle` §2.5).

## Completion

- On **success**: emit the original role's completion payload verbatim, append the `fallback_used` envelope (without `provider_failure`), and stop.
- On **provider failure**: emit only the `fallback_used` envelope **with** `provider_failure`, set `blocker_code: PROVIDER_FAILURE`, and stop. Do not emit a partial original schema.
- On **logic / contract blocker**: emit the original role's blocker schema + `fallback_used` envelope (without `provider_failure`), and stop.
