---
name: github-issue-run
description: "Orchestrate GitHub feature:<slug> backlog — next-runnable discovery, state transitions, flat or stage execution loop. Delegate gh and lib scripts to developer."
modelTier: fast
roleReminder: "Load with orchestrate-execution for GitHub backlog mode. You have no bash — delegate gh/lib shell to developer (bootstrap env uses worktree-env + preflight)."
---

# GitHub issue run

Companion to **`orchestrate-execution`** when working from a **GitHub `feature:<slug>` backlog** (no local `.plan` artifact).

## Preconditions

- Session bootstrap completed: user chose preflight **yes** (`env_gate_passed`) or **no** (`env_gate_declined`) before work selection.
- **Checkout identity gate** completed: `checkout_contract` captured (`impl_repo_path`, `branch`, `branch_policy`) — mandatory even when preflight was declined.
- Implementation repo with child issues from spec fanout and technical planning targeted at that implementation repo (normally coordinated from the spec session with `--cwd`; current runtime accepts `opencode-task-yaml` content and legacy `opencode-task-json` fences, with non-empty `stages[]` for orchestrate level).
- **Issue-expand readiness gate** passed (`opencode-run impl orchestrate-readiness-check <slug>`) before the loop starts.
- `gh` authenticated (via delegated **developer** Tasks).
- Issues labelled `feature:<slug>` and `state:ready-for-agent` (or transitioned to `state:in-progress` during execution).
- Current branch is the user's selected feature/topic branch (primary checkout or linked worktree). Protected branches (`develop`/`main`/`master`) require explicit user confirmation before `state:in-progress`.

## Config path for helper scripts

```text
OC="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
"$OC/skills/github-issue-run/lib/checkout-contract.sh"
"$OC/skills/github-issue-run/lib/next-runnable-issue.sh"
"$OC/skills/github-issue-run/lib/issue-state-transition.sh"
"$OC/skills/github-issue-run/lib/feature-finish-pr.sh"
```

## Checkout identity

Before discovery or transitions, orchestrate runs **`checkout-contract.sh`** and stores `checkout_contract`. Set env vars for helper scripts:

```bash
export OPENCODE_EXPECT_REPO_ROOT="<impl_repo_path>"
export OPENCODE_EXPECT_BRANCH="<branch>"
```

Subagents must work on this checkout and branch only — never create or switch branches unless the user explicitly requests it in the current turn.

## Discovery

Task **developer** `load: minimal` — **only** this script; do **not** run broad `gh issue list` without `--label "feature:<slug>"`:

```bash
bash "$OC/skills/github-issue-run/lib/next-runnable-issue.sh" "<slug>"
```

GitHub filters server-side (`feature:<slug>` **and** `state:ready-for-agent`). The helper never scans the whole repo. Do not inventory other features or total `ready-for-agent` counts unless the user explicitly asks.

Stdout is JSON: `{ queue_remaining, number, title, body, opencode_meta, repo }` or empty (exit 1 = queue exhausted).

**One issue per call** — `queue_remaining` is how many issues still have `state:ready-for-agent` for this feature (GitHub label filter). The orchestrator loops: discover → implement → verify → transition → discover again until exit 1. "Found 1" on a single call does **not** mean the queue has only one ticket.

Parse **`opencode_meta`** from the current runtime contract: JSON content in an `opencode-task-yaml` fence (preferred) or legacy `opencode-task-json` fence. Do not migrate stored issue bodies in this skill.

## State transitions

Task **developer** `load: minimal`:

```bash
bash "$OC/skills/github-issue-run/lib/issue-state-transition.sh" "<repo>" "<number>" "<state-label>"
```

| When | Label |
|------|-------|
| Start work | `state:in-progress` |
| Verifier PASS (all stages done for issue) | `state:ready-for-review` |
| Blocked / env failure | `state:blocked` |
| Accepted after Mode F Phase 1 | `state:done` (set by **architect** — orchestrate must **not** use this label) |

## Execution loop

1. Obtain kebab-case **feature slug** from user if missing.
2. Ensure **checkout identity gate** completed (`checkout_contract` stored).
3. **next-runnable-issue.sh** → capture JSON.
4. Set `OPENCODE_EXPECT_REPO_ROOT` and `OPENCODE_EXPECT_BRANCH` from `checkout_contract`; transition to **`state:in-progress`**.
5. If **`opencode_meta.stages`** is non-empty → follow **stage loop** in **`orchestrate-execution`** (`execution_mode: github_issue_stage`). Stage owners are restricted to `developer`, `frontend-dev`, or `ux-dev`; dispatch the exact owner and never substitute `frontend-dev` for an `ux-dev` prototype stage.
6. Else **flat mode** — **blocked on spec-driven path**; return to spec architect option 1. Flat mode applies only to targeted issues without `stages[]` outside the spec fanout path.
7. Task **verifier** with same contract + completion report.
8. Grade per **Child Report Grading Gate**; require **`git_commit`** with `Refs: #<n>` when files changed.
9. On PASS → **`state:ready-for-review`** + optional `gh issue comment` with summary + commit hash. **Do not** run CodeRabbit per issue.
10. On FAIL → **`state:blocked`** or **helper** / **orchestrate-recovery** — do not advance queue.
11. Repeat from step 3 until discovery fails.

## Queue exhausted

When **next-runnable-issue.sh** exits 1 (no runnable issues left):

1. **CodeRabbit gate (once):** If difficulty is not `easy`, orchestrate runs the **CodeRabbit gate** from **`orchestrate-execution`** on **all** feature changes before PR finish — defaulting to `develop` as base. Per-issue transitions must not invoke CodeRabbit, and remediation must not re-run CodeRabbit.
2. Task **developer** `load: minimal`:

```bash
bash "$OC/skills/github-issue-run/lib/feature-finish-pr.sh" "<slug>"
```

Stdout is JSON: `{ branch, base, pr_url, pr_number, action, repo, message }`.

| `action` | Meaning |
|----------|---------|
| `pr-created` | Branch pushed; new ready-for-review PR opened |
| `pr-exists` | Branch pushed; reused existing open PR |
| `skipped-opt-out` | `ORCHESTRATE_AUTO_PR=0` or user asked not to open a PR |
| `skipped-protected-branch` | Current branch is `develop`/`main`/`master` — push/PR skipped; report `message` and manual next steps |

3. Report `pr_url` (or skip reason) and feature **`### CodeRabbit`** completion fields to the user.
4. **First orchestration complete** (PR newly opened): prompt **impl architect option 4 → A** with first-complete paste (see `orchestrate-execution` Completion template).
5. **Remediation session complete** (user message included `Remediation:`): prompt **impl architect option 4 → R** with remediation-return paste — re-check PR feedback before accept/docs.

**Orchestrate must not** set `state:done`, close issues as accepted, or write `docs/changelog/*` — that is **impl architect Mode F** ([architect-review](../architect-review/SKILL.md), helper `architect-review/lib/mode-f-accept-issues.sh`). Spec **feature-complete** closes issues at merge.

**Opt-out:** Set `ORCHESTRATE_AUTO_PR=0` in the environment, or tell orchestrate not to open a PR for this run.

**Base branch:** Defaults to `develop`, falling back to the repo default branch if `develop` is absent on `origin`. Override with `PR_BASE` env or pass as second script argument.

## Compatibility

If helper scripts are missing, stop and report — do not fall back to inventing queue logic. Local `.plan` execution remains a separate orchestrate path when user provides an artifact path explicitly.
