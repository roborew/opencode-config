---
name: architect-review
description: "Post-implementation sign-off: Mode F (GitHub feature:<slug> — verify, close issues, docs on PR) or Mode B (.plan — review, docs, archive_plan)."
modelTier: "smart"
roleReminder: "Load when user reports implementation done / ready for review. Mode F for feature:<slug> handoffs; Mode B for executed .plan artifacts. Not for new planning—that is architect-plan."
---

> **Hard Rules live in the architect agent markdown;** this skill adds protocol detail for **Mode F** (GitHub-first) and **Mode B** (legacy `.plan`). Non-negotiables—scope, scribe handoff, developer delegation for gh/git on feature branch—come from the agent.

## First-Turn Behavior (mode selection)

Do not narrate the mode switch. Do not describe what you are about to do.

| Signal | Mode |
|--------|------|
| `feature:<slug>` handoff, orchestrate queue exhausted, **spec option 4**, impl **option 4**, handoff with `impl_repo` + `pr_url`, or user asks GitHub feature sign-off | **Mode F** |
| Explicit executed path `.plan/<type>.<slug>.md` (orchestrate ran on that artifact) | **Mode B** |
| Ambiguous (both slug and `.plan` mentioned) | Ask once: sign-off from **GitHub issues** (`feature:<slug>`) or **local plan file**? |
| New feature planning | Load **`architect-plan`** instead |

For new feature planning or plan-type selection, load **`architect-plan`** instead of this skill.

## Responsibility Boundaries (mandatory)

| Role | Responsibility | Writes? |
|------|----------------|--------|
| **Architect** | Mode selection; data collection; Task coordination; doc-scope human gate (Mode F) | No — read-only for app source |
| **review** | Sign-off vs remediation | No — read-only |
| **document** | Generates changelog/guides/architecture content | No — read-only |
| **scribe** | Writes `.plan` updates and doc markdown | Yes — docs/plan paths only |
| **developer** | `gh` issue transitions/close/comments; **docs-only** `git add` / `commit` / `push` on feature branch (Mode F Phase 2) | Yes — delegated only |

You may invoke: `review`, `document`, `scribe`, and **`developer`** (minimal load) for Mode F issue closure and doc commits. Do **not** invoke `frontend-dev`, `developer` for product code, or `orchestrate` during sign-off—user starts a **new orchestrate session** for remediation execution.

**Remediation (both modes):** Prefer **`to-issues`** on GitHub paths; `.plan/review.<slug>.md` via scribe only if user insists on legacy sidecar.

## Supplementary Hard Rules (both modes; agent Hard Rules override on conflict)

- **No narration.** Invoke subagents directly; produce output after actions complete.
- **Scribe is the only write path** for `.plan` updates and docs markdown on disk.
- **Pass specialist output verbatim** to scribe.
- After scribe returns **success** with **tool evidence** and no `SCRIBE_FAILED`, trust the write for planning flows. **Mode F / Mode B sign-off docs:** always **verify on disk** (step 8) before Tasking **developer** for git or declaring Phase 2 complete.
- **Mode B `archive_plan` is blocking** on sign-off (see Mode B step 6). **Mode F:** skip `archive_plan` when execution was GitHub-only; state `No archive_plan: issue-backed execution only.` If a `.plan` was also executed, run `archive_plan` after Phase 2 (same as Mode B step 6).

**Brevity / formatting:** Concise headings, tables, and keyed lists only; deltas only when repeating status to the user. When asking the user for a choice or handing work between agents, use a table with the exact target (`feature:<slug>`, PR, artifact path) and the exact prompt/input to paste next.

---

## Mode F — GitHub feature sign-off (two phases)

Use when signing off **`feature:<slug>`** vs PRD/tickets (no `.plan/feature.*` required). **One architect session** with a **required pause** between Phase 1 and the doc-scope question.

### Config

```text
OC="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
PRD: docs/prd/<slug>.md in spec repo cwd, else $SPEC_REPO/docs/prd/<slug>.md from impl issue-tracker
Impl repo: owner/name from orchestrate handoff (required when cwd is spec)
Impl path: absolute sibling path from handoff or resolve_impl_path.sh (for developer docs commit)
Issue scripts: $OC/skills/github-issue-run/lib/issue-state-transition.sh
Close helper: $OC/skills/architect-review/lib/mode-f-close-issues.sh (--repo OWNER/NAME when cwd is spec)
```

### Spec-repo sign-off (cwd is spec)

When orchestrate handoff includes **`impl_repo`** and **`pr_url`**:

- Use **`gh issue list` / `gh issue view` / `gh pr view`** with explicit `--repo owner/name` for the **impl** repo (not spec).
- Read PRD from **`docs/prd/<slug>.md`** (local spec path).
- Task **developer** for issue closure: pass `--repo <impl_repo>` to `mode-f-close-issues.sh`.
- Task **developer** for docs commit (Phase 2): pass **`impl_repo_path`** and feature branch from PR; scribe writes paths relative to impl repo layout — verify with `test -f` using paths under `impl_repo_path` or delegate verify to developer on that checkout.

### Phase 1 — Verification

#### 1. Data collection

Architect: **read-only** `gh issue list` / `gh issue view` / `gh pr list` via bash when collecting data. Any **`gh issue edit`**, **`gh issue close`**, **`gh issue comment`**, or **git** mutation → Task **developer** `load: minimal`:

```bash
gh issue list --repo owner/name -l "feature:<slug>" --state all -L 200 --json number,title,url,labels,body,state
```

When cwd is **spec**, always pass **`--repo <impl_repo>`** from the orchestrate handoff.

- Require every open issue to have **`state:ready-for-review`** (or document exception in review context).
- PR from orchestrate handoff or `gh pr view <url>` / `gh pr list --repo owner/name --head <branch>`.
- Read PRD from spec (`docs/prd/<slug>.md`) or impl tracker path; parse **`opencode-task-json`** per issue; collect verifier summaries and commit SHAs from issue comments.

#### 2. Architect checklist (before Tasking `review`)

- Every PRD **`tickets[]`** entry for **this repo** maps to an issue (or recorded deferral).
- All issues show verifier PASS evidence (comments or handoff).
- Acceptance and `test_commands` from issue meta are addressable in review.

#### 3. Task `review`

Include a **Mode F context block**:

```text
execution_mode: github_feature_signoff
feature_slug: <slug>
prd_path: <path or N/A>
pr_url: <url>
issue_rollup: <summary or JSON>
completion_context: <orchestrate handoff>
```

#### 4. Outcomes

| Verdict | Action |
|---------|--------|
| **Needs changes** | **`to-issues`** (preferred) or scribe `.plan/review.<slug>.md` if user insists; **do not close issues**; prompt **new orchestrate session** |
| **Merge-ready** | Proceed to **ticket closure** — **do not** write docs yet |

#### 5. Ticket closure (Merge-ready only)

Task **developer** `load: minimal` with a **start contract** (Hard Rule #1 — bare “run this script” will be rejected). Prefer bundled close when all issues are ready.

**Task prompt — issue closure** (use any open `feature:<slug>` issue number from step 1):

```text
load: minimal
execution_mode: github_issue_stage
issue_number: <n>
repo: <owner/name>
stage_id: mode-f-signoff-close
stage:
  objective: Close all feature:<slug> issues that are state:ready-for-review
  files: []
  acceptance: mode-f-close-issues.sh exits 0; targeted issues are state:done and closed
  test_commands:
    - bash "$OC/skills/architect-review/lib/mode-f-close-issues.sh" "<slug>" "<pr_url_or_empty>" --repo <owner/name>
  commit_message: "chore(<slug>): architect Mode F issue closure"
```

Fallback per issue: `issue-state-transition.sh <repo> <n> state:done`, then `gh issue close <n> --comment "Sign-off: <summary>. PR: <url>"` — still wrap in the same `github_issue_stage` contract with updated `test_commands`.

**Gate:** Do not start Phase 2 until every accepted issue is **`state:done`** and **closed** (or deferral is explicit in review output).

Report to user with a compact **Phase 1 complete** table: feature slug, PR, closed issues, review verdict, deferrals, and the required doc-scope choice from step 6. Pause for doc scope.

### Phase 2 — Documentation (after human doc-scope gate)

#### 6. Human gate (required)

Ask with this table-driven pattern:

```markdown
## Documentation scope

| Field | Value |
|-------|-------|
| Feature | `<Display Name>` (`feature:<slug>`) |
| Required | `docs/changelog/<YYYY-MM-DD>-<slug>.md` |
| PR | `<pr_url>` |

| Option | Include? | Path |
|--------|----------|------|
| User guide | yes / no | `docs/guides/<slug>.md` |
| Architecture note | yes / no | `docs/architecture/<slug>.md` |
| README / .env.example | yes / no | `<specific paths>` |

Reply with the rows to include, for example: `guide: yes, architecture: no, README: no`.
```

- **Changelog: always** — never skip.
- Guides / architecture / README: only if user selects or review flagged doc debt.

#### 7. Task `document`

```text
execution_mode: github_feature_signoff
feature_slug: <slug>
prd_path: <path>
doc_scope: changelog [, guide, architecture, ...]
issue_rollup + completion_context
artifact_path: <only if .plan was also executed>
```

#### 8. Task `scribe` + verify on disk

For each doc in document output (Mode B paths):

- `docs/changelog/<date>-<slug>.md` (required)
- `docs/guides/<slug>.md`, `docs/architecture/<slug>.md`, `README.md`, `.env.example` as selected

After each scribe call: retry once on `SCRIBE_FAILED` or missing file (below).

**Verify (architect bash, before step 9):** For every path scribe reported written:

```bash
test -f "docs/changelog/<date>-<slug>.md" && ls -la docs/changelog/<date>-<slug>.md
# repeat for each optional doc path
```

- If any path is missing: re-Task **scribe** once with the same content and path; verify again.
- If still missing after retry: stop Phase 2; report paths to user — do not Task **developer** for commit.

Collect the verified path list for step 9 `files_to_change`.

#### 9. Task `developer` — commit docs to feature PR

**Start contract required** — use `github_issue_stage` (same `issue_number` / `repo` as step 5). On the **feature branch** in the **impl repo** (`impl_repo_path` from handoff when cwd is spec):

**Task prompt — docs commit:**

```text
load: minimal
execution_mode: github_issue_stage
issue_number: <n>
repo: <owner/name>
impl_repo_path: <absolute path to impl git root>
stage_id: mode-f-signoff-docs
stage:
  objective: Commit sign-off documentation to the feature branch and push (impl repo checkout)
  files: [<verified paths from step 8>]
  acceptance: All listed doc files exist on disk under impl_repo_path, are committed, and pushed to origin on the feature branch
  test_commands:
    - cd <impl_repo_path> && test -f <each verified path from step 8>
    - cd <impl_repo_path> && git checkout <feature-branch>
    - cd <impl_repo_path> && git add <verified paths from step 8>
    - cd <impl_repo_path> && git commit -m "docs(<slug>): sign-off changelog and guides"
    - cd <impl_repo_path> && git push origin HEAD
  commit_message: "docs(<slug>): sign-off changelog and guides"
```

Docs-only commit; no product test re-run. If push fails, report branch and paths — do not claim Mode F complete.

#### 10. Finish

- If GitHub-only execution: state **`No archive_plan: issue-backed execution only.`**
- If `.plan` was also executed: run Mode B **step 6** (`archive_plan`) after step 9.

**Phase 2 complete message:** Use a table with PR URL (including doc commit), closed issue list, doc paths written, archive status, and **Next: review PR on GitHub and merge** (human only). Do not use a paragraph recap.

**Mode F is not complete** until Phase 2 push succeeds or push failure is reported with manual next steps.

---

## Mode B — Post-implementation (`.plan` review + documentation)

When user reports orchestrate completed on a **`.plan` artifact** and verifier passed: **review** → **documentation** → **`archive_plan`**. **Mode B is not finished until the plan file is renamed to `*.completed.md` or scribe reports `SCRIBE_FAILED` on archive after retry.**

## Completion Flow — Mode B

1. **Review:** Invoke `review` with `artifact_path` and completion context.
2. **If remediation:** Scribe `.plan/review.<slug>.md`; **new orchestrate session** — do not continue sign-off for execution.
3. **If sign-off:** Task `document` with artifact path.
4. **Write docs:** Scribe each path from document output (changelog, guides, architecture, README, `.env.example`) as needed. If document returns no files, skip to step 6.
5. **Verify on disk** (same as Mode F step 8): architect `test -f` / `ls` per path; retry scribe once on miss; stop sign-off if files still missing.
6. **Archive (MANDATORY):** Separate Task `scribe` with `operation: archive_plan`, `source_path`, `target_path` (`.completed.md`). Retry once on failure.
7. Report with a compact table: sign-off verdict, docs written, archive status (**`Archived: <target_path>`** or failure), risks/deferrals, and exact next action.

When Mode F also ran on a hybrid path, run Mode B step 6 after Mode F Phase 2.
