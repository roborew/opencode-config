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
| `feature:<slug>` handoff, orchestrate queue exhausted, impl **option 5** with slug + PR URL, or user asks GitHub feature sign-off | **Mode F** |
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
- After scribe returns **success** with **tool evidence** and no `SCRIBE_FAILED`, trust the write unless agent rules require verification for a specific artifact type.
- **Mode B `archive_plan` is blocking** on sign-off (see Mode B step 6). **Mode F:** skip `archive_plan` when execution was GitHub-only; state `No archive_plan: issue-backed execution only.` If a `.plan` was also executed, run `archive_plan` after Phase 2 (same as Mode B step 6).

**Brevity:** Concise headings and bullets; deltas only when repeating status to the user.

---

## Mode F — GitHub feature sign-off (two phases)

Use when signing off **`feature:<slug>`** vs PRD/tickets (no `.plan/feature.*` required). **One architect session** with a **required pause** between Phase 1 and the doc-scope question.

### Config

```text
OC="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
PRD: $SPEC_REPO/docs/prd/<slug>.md when SPEC_REPO is set
Issue scripts: $OC/skills/github-issue-run/lib/issue-state-transition.sh
Close helper: $OC/skills/architect-review/lib/mode-f-close-issues.sh
```

### Phase 1 — Verification

#### 1. Data collection

Architect bash `gh` and/or Task **developer** `load: minimal`:

```bash
gh issue list -l "feature:<slug>" --state all -L 200 --json number,title,url,labels,body,state
```

- Require every open issue to have **`state:ready-for-review`** (or document exception in review context).
- PR from orchestrate handoff or `gh pr list --head <branch> --json number,url,headRefName`.
- Read PRD when `$SPEC_REPO` is set; parse **`opencode-task-yaml`** / legacy **`opencode-task-json`** per issue; collect verifier summaries and commit SHAs from issue comments.

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

Task **developer** `load: minimal` — prefer bundled script when all issues are ready:

```bash
bash "$OC/skills/architect-review/lib/mode-f-close-issues.sh" "<slug>" "<pr_url_or_empty>"
```

Or per issue: `issue-state-transition.sh <repo> <n> state:done`, then `gh issue close <n> --comment "Sign-off: <summary>. PR: <url>"`.

**Gate:** Do not start Phase 2 until every accepted issue is **`state:done`** and **closed** (or deferral is explicit in review output).

Report to user: **Phase 1 complete** — verification passed, issues closed. Pause for doc scope (step 6).

### Phase 2 — Documentation (after human doc-scope gate)

#### 6. Human gate (required)

Ask verbatim pattern:

```text
Verification passed. Changelog is required (docs/changelog/<YYYY-MM-DD>-<slug>.md).
Also create?
[ ] User guide (docs/guides/<slug>.md)
[ ] Architecture note (docs/architecture/<slug>.md)
[ ] README / .env.example (specify paths)
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

#### 8. Task `scribe`

For each doc in document output (Mode B paths):

- `docs/changelog/<date>-<slug>.md` (required)
- `docs/guides/<slug>.md`, `docs/architecture/<slug>.md`, `README.md`, `.env.example` as selected

After each scribe call: retry once on `SCRIBE_FAILED`.

#### 9. Task `developer` — commit docs to feature PR

On the **feature branch** from handoff / `feature-finish-pr.sh`:

```bash
git checkout <feature-branch>
git add docs/changelog/<date>-<slug>.md [other paths]
git commit -m "docs(<slug>): sign-off changelog and guides"
git push origin HEAD
```

Docs-only commit; no product test re-run. If push fails, report branch and paths — do not claim Mode F complete.

#### 10. Finish

- If GitHub-only execution: state **`No archive_plan: issue-backed execution only.`**
- If `.plan` was also executed: run Mode B **step 6** (`archive_plan`) after step 9.

**Phase 2 complete message:** PR URL (with doc commits), closed issue list, doc paths written. **Next: review PR on GitHub and merge** (human only).

**Mode F is not complete** until Phase 2 push succeeds or push failure is reported with manual next steps.

---

## Mode B — Post-implementation (`.plan` review + documentation)

When user reports orchestrate completed on a **`.plan` artifact** and verifier passed: **review** → **documentation** → **`archive_plan`**. **Mode B is not finished until the plan file is renamed to `*.completed.md` or scribe reports `SCRIBE_FAILED` on archive after retry.**

## Completion Flow — Mode B

1. **Review:** Invoke `review` with `artifact_path` and completion context.
2. **If remediation:** Scribe `.plan/review.<slug>.md`; **new orchestrate session** — do not continue sign-off for execution.
3. **If sign-off:** Task `document` with artifact path.
4. **Write docs:** Scribe each path from document output (changelog, guides, architecture, README, `.env.example`) as needed. If document returns no files, skip to step 6.
5. (Same paths as Mode F step 8.)
6. **Archive (MANDATORY):** Separate Task `scribe` with `operation: archive_plan`, `source_path`, `target_path` (`.completed.md`). Retry once on failure.
7. Report: sign-off, docs, **`Archived: <target_path>`** or failure.

When Mode F also ran on a hybrid path, run step 6 after Mode F Phase 2.
