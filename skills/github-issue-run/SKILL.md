---
name: github-issue-run
description: "Orchestrate GitHub feature:<slug> backlog — next-runnable discovery, state transitions, flat or stage execution loop. Delegate gh and lib scripts to developer."
modelTier: fast
roleReminder: "Load with orchestrate-execution for GitHub backlog mode. You have no bash — delegate all shell to developer."
---

# GitHub issue run

Companion to **`orchestrate-execution`** when working from a **GitHub `feature:<slug>` backlog** (no local `.plan` artifact).

## Preconditions

- Session bootstrap completed: user chose preflight **yes** (`env_gate_passed`) or **no** (`env_gate_declined`) before work selection.
- Implementation repo with child issues from spec fanout + impl **issue-expand** (`opencode-task-yaml` with non-empty `stages[]` for orchestrate level).
- `gh` authenticated (via delegated **developer** Tasks).
- Issues labelled `feature:<slug>` and `state:ready-for-agent` (or transitioned to `state:in-progress` during execution).

## Config path for helper scripts

```text
OC="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
"$OC/skills/github-issue-run/lib/next-runnable-issue.sh"
"$OC/skills/github-issue-run/lib/issue-state-transition.sh"
"$OC/skills/github-issue-run/lib/feature-finish-pr.sh"
```

## Discovery

Task **developer** `load: minimal`:

```bash
bash "$OC/skills/github-issue-run/lib/next-runnable-issue.sh" "<slug>"
```

Stdout is JSON: `{ number, title, body, opencode_meta, repo }` or empty (exit 1 = queue exhausted).

Parse **`opencode_meta`** from **`opencode-task-yaml`** (primary) or legacy **`opencode-task-json`**.

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
2. **next-runnable-issue.sh** → capture JSON.
3. Transition to **`state:in-progress`**.
4. If **`opencode_meta.stages`** is non-empty → follow **stage loop** in **`orchestrate-execution`** (`execution_mode: github_issue_stage`).
5. Else **flat mode** → single implement pass (`execution_mode: github_issue`) using root acceptance + test_commands from meta.
6. Task **verifier** with same contract + completion report.
7. Grade per **Child Report Grading Gate**; require **`git_commit`** with `Refs: #<n>` when files changed.
8. On PASS → **`state:ready-for-review`** + optional `gh issue comment` with summary + commit hash. **Do not** run CodeRabbit per issue.
9. On FAIL → **`state:blocked`** or **helper** / **orchestrate-recovery** — do not advance queue.
10. Repeat from step 2 until discovery fails.

## Queue exhausted

When **next-runnable-issue.sh** exits 1 (no runnable issues left):

1. **CodeRabbit gate (once):** If difficulty is not `easy`, orchestrate runs the **CodeRabbit gate** from **`orchestrate-execution`** on **all** feature changes before PR finish — defaulting to `develop` as base and allowing max 3 CLI runs including remediation re-gates. Per-issue transitions must not invoke CodeRabbit.
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
4. Prompt: **Switch to `architect` for feature sign-off** (Mode F two-phase: verify + close issues, then docs on PR).

**Orchestrate must not** set `state:done`, close issues as accepted, or write `docs/changelog/*` — that is **architect Mode F** ([architect-review](../architect-review/SKILL.md), helper `architect-review/lib/mode-f-close-issues.sh`).

**Opt-out:** Set `ORCHESTRATE_AUTO_PR=0` in the environment, or tell orchestrate not to open a PR for this run.

**Base branch:** Defaults to `develop`, falling back to the repo default branch if `develop` is absent on `origin`. Override with `PR_BASE` env or pass as second script argument.

## Compatibility

If helper scripts are missing, stop and report — do not fall back to inventing queue logic. Local `.plan` execution remains a separate orchestrate path when user provides an artifact path explicitly.
