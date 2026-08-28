---
name: orchestrate-execution
description: "Routing kernel for issue-backed orchestration: lifecycle invariants, trigger routing, state logging, and completion definition."
modelTier: "fast"
roleReminder: "Load once when orchestrate begins coordination; load lifecycle skills only when their triggers occur."
---

> Hard Rules live in `agents/orchestrate.md`. This skill defines the steady-path routing kernel; detailed procedures belong to the skill named by each trigger.

## Scope

Coordinate an existing GitHub ticket queue. Do not write files, execute shell, invent queue logic, or load lifecycle skills speculatively.

## Immutable Invariants

1. GitHub tickets are the source of truth for normal execution. A missing, malformed, or unready GitHub queue is a blocking readiness failure, never an implicit local-plan fallback.
3. Run the checkout identity gate before selection, implementation, or state mutation. Children receive the verified checkout and branch contract and must not create, switch, checkout, or rename branches.
4. Delegate every mutation or shell operation to the appropriate child. The coordinator never edits application files, issue bodies, labels, comments, or commits directly.
5. Run exactly one seam at a time: dispatch `test-writer` for RED, the Owner-matched implementer for GREEN, then `code-review` in ticket mode. Never advance without an `APPROVED` code-review report.
6. An empty, malformed, or step-limited required child report is `BLOCKED`, not success. Required skill load failure is `BLOCKED: REQUIRED_SKILL_NOT_LOADED`; perform no state transition.
7. Preserve `state:*`, `verified`, `unverified`, `code_review_gate:`, commit-reference, and close-at-merge contracts exactly.
8. CodeRabbit is a single feature/artifact-wide gate after the final verifier pass, never per stage, ticket, or remediation. Final implementation sign-off and documentation remain with the implementation architect.

## Lifecycle States

Use one state at a time and retain only concise gate evidence:

| State | Entry trigger | Required skill |
|---|---|---|
| `bootstrap` | Fresh coordinator context or checkout identity change | `orchestrate-bootstrap` |
| `github_queue` | User selects backlog and readiness passes | `github-issue-run` |
| `sandbox` | User requests build/refresh/expose/destroy | `orchestrate-sandbox` |
| `verify` | Implementer Task returns | `orchestrate-verification` |
| `recover` | Child failure, loop, blocker, or missing report | `orchestrate-recovery` |
| `complete` | Queue exhausted and all acceptance gates pass | `orchestrate-completion` |

Record each loaded skill with its observed trigger and state in the lifecycle log from `agents/orchestrate.md`. Record skipped checklist items with a reason; do not create a log file.

## Trigger Order

1. Fresh context: load `orchestrate-bootstrap`; resolve preflight choice, checkout identity, Claude Context readiness, and work selection before implementation.
2. GitHub backlog: after slug capture and readiness PASS, load `github-issue-run`; discover one runnable ticket, claim it, and dispatch its Owner.
3. Implementer return: load `orchestrate-verification`; grade the report, dispatch `code-review`, and post required review evidence before advancement.
4. Any failure or missing evidence: load `orchestrate-recovery`; do not advance until its recovery gate is satisfied.
5. Queue exhaustion: load `orchestrate-completion`; run the one-shot CodeRabbit and difficulty gates, PR stabilization, and completion handoff.

## Required Task Contract

Every implementation or verification Task includes:

```text
impl_repo_path: <absolute verified git root>
expected_branch: <verified branch>
is_linked_worktree: true|false
main_checkout_root: <root when known>
branch_policy: do not create, switch, checkout, or rename branches
```

Code-review Tasks additionally include `diff_base`, `files_changed`, `acceptance_to_test`, `red_phase`, `green_phase`, `assertion_delta`, `security_review`, and GitHub `issue_number`/`repo` when applicable. When `test_commands` exist, include the Docker-default contract from `orchestrate-verification`.

## Child Report Grade

`PASS` requires the expected identifier, changed files, RED and matching GREEN evidence, explicit `assertion_delta`, acceptance mapping for every numbered criterion, tests/checks, and no blockers. `NEEDS_RETRY` covers missing or weak evidence. `BLOCKED` covers an explicit blocker, unsafe scope, unavailable required skill, or environment failure. Code-review `APPROVED` additionally requires non-missing criterion coverage and resolved security status.

## Completion Definition

Orchestration is complete only after every ticket/stage has an `APPROVED` verifier report, required CodeRabbit/difficulty gates are resolved, PR stabilization is finalized or explicitly skipped, and the completion handoff names the exact target and implementation-architect next action.
