---
name: architect-review
description: "Post-implementation sign-off: Mode F (GitHub feature:<slug> — Phase R triage, accept issues, docs on PR) or Mode B (.plan — review, docs, archive_plan)."
modelTier: "smart"
roleReminder: "Load when user reports implementation done / ready for review. Mode F for feature:<slug> handoffs in impl repo; Mode B for executed .plan artifacts. Not for new planning—that is architect-plan."
---

> **Hard Rules live in the architect agent markdown;** this skill adds protocol detail for **Mode F** (GitHub-first) and **Mode B** (legacy `.plan`). Non-negotiables—scope, scribe handoff, developer delegation for gh/git on feature branch—come from the agent.

## First-Turn Behavior (mode selection)

Do not narrate the mode switch. Do not describe what you are about to do.

| Signal | Mode |
|--------|------|
| `feature:<slug>` handoff, orchestrate queue exhausted, **impl option 4** (preferred), handoff with `pr_url`, or user asks GitHub feature sign-off | **Mode F** |
| Spec option 4 with impl handoff (cross-repo assist — rare) | **Mode F** (read impl repo via `--repo`) |
| Explicit executed path `.plan/<type>.<slug>.md` (orchestrate ran on that artifact) | **Mode B** |
| Ambiguous (both slug and `.plan` mentioned) | Ask once: sign-off from **GitHub issues** (`feature:<slug>`) or **local plan file**? |
| New feature planning | Load **`architect-plan`** instead |

**Preferred entry:** **impl repo** architect **option 4** → **Mode F sub-menu** → **R** after orchestrate PR or remediation push. Spec **option 3 feature-complete** is the final ceremony after all impl repos finish Mode F.

## Mode F sub-menu (impl architect option 4)

Present when user picks option 4 or returns from orchestrate without an explicit phase. See **architect** agent for verbatim menu text.

| Choice | Run |
|--------|-----|
| **R** | Phase R only (triage → remediate or Merge-ready) |
| **1** | Phase 1 accept only |
| **2** | Phase 2 docs only |
| **A** | Auto-detect from pasted handoff |

**Auto (A) defaults:** orchestrate-complete or remediation-return script → **R**; user says Merge-ready and accept → **1**; doc-scope table reply → **2**.

For new feature planning or plan-type selection, load **`architect-plan`** instead of this skill.

## Responsibility Boundaries (mandatory)

| Role | Responsibility | Writes? |
|------|----------------|--------|
| **Architect** | Mode selection; data collection; Task coordination; doc-scope human gate (Mode F) | No — read-only for app source |
| **review** | Phase R triage + Phase 1 sign-off vs remediation | No — read-only |
| **strategist** | Phase R only — prioritize remediation, group feedback | No — read-only |
| **document** | Generates changelog/guides/architecture content | No — read-only |
| **scribe** | Writes `.plan` updates and doc markdown | Yes — docs/plan paths only |
| **developer** | `gh` issue transitions/comments; **docs-only** `git add` / `commit` / `push` on feature branch (Mode F Phase 2) | Yes — delegated only |

You may invoke: `review`, `strategist` (**Phase R only**), `document`, `scribe`, and **`developer`** (minimal load) for Mode F issue acceptance and doc commits. Do **not** invoke `frontend-dev`, `developer` for product code, or `orchestrate` during sign-off—user starts a **new orchestrate session** for remediation execution.

**Impl repos do not close GitHub issues.** They transition `state:*` labels only. Spec **feature-complete** closes issues at merge.

**Remediation (both modes):** Phase R publishes remediation via **`to-issues`** / `publish-targeted-issue` with `--parent-issue` (PRD parent URL from spec PRD frontmatter). `.plan/review.<slug>.md` via scribe only if user insists on legacy sidecar.

## Supplementary Hard Rules (both modes; agent Hard Rules override on conflict)

- **No narration.** Invoke subagents directly; produce output after actions complete.
- **Scribe is the only write path** for `.plan` updates and docs markdown on disk.
- **Pass specialist output verbatim** to scribe.
- After scribe returns **success** with **tool evidence** and no `SCRIBE_FAILED`, trust the write for planning flows. **Mode F / Mode B sign-off docs:** always **verify on disk** (Phase 2 step 8) before Tasking **developer** for git or declaring Phase 2 complete.
- **Mode B `archive_plan` is blocking** on sign-off (see Mode B step 6). **Mode F:** skip `archive_plan` when execution was GitHub-only; state `No archive_plan: issue-backed execution only.` If a `.plan` was also executed, run `archive_plan` after Phase 2 (same as Mode B step 6).

**Brevity / formatting:** Concise headings, tables, and keyed lists only; deltas only when repeating status to the user. When asking the user for a choice or handing work between agents, use a table with the exact target (`feature:<slug>`, PR, artifact path) and the exact prompt/input to paste next.

---

## Mode F — GitHub feature sign-off (Phase R → Phase 1 → Phase 2)

Use when signing off **`feature:<slug>`** vs PRD/tickets (no `.plan/feature.*` required). **Preferred cwd: impl repo.** One architect session with pauses at doc-scope and after Phase 2 for Spec handoff.

### Config

```text
OC="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
PRD: docs/prd/<slug>.md in spec sibling, or from PRD frontmatter parent_issue
Impl repo: gh repo view when cwd is impl; or orchestrate handoff impl_repo
Impl path: absolute path from handoff or cwd git root
Issue scripts: $OC/skills/github-issue-run/lib/issue-state-transition.sh
Accept helper: $OC/skills/architect-review/lib/mode-f-accept-issues.sh (--repo OWNER/NAME when cwd is spec)
Parent issue: parse parent_issue URL from docs/prd/<slug>.md frontmatter (for remediation sub-issues)
```

### Phase R — PR feedback triage (first after orchestrate PR, or re-check after remediation)

Run when:

- orchestrate handoff includes **`pr_url`** (first pass), or
- user picks **Mode F sub-menu R**, or
- user pastes **remediation-return** script after orchestrate re-push.

**Re-check (return loop):** Same steps as first pass; emphasize delta since last Phase R (new PR comments, CI re-run, remediation issues now `state:ready-for-review`, user feedback). Do not skip to Phase 1 until verdict is **Merge-ready**.

#### R1. Data collection (read-only)

```bash
gh issue list --repo owner/name -l "feature:<slug>" --state open -L 200 --json number,title,url,labels,body,state
gh pr view <pr_url> --json reviews,comments,statusCheckRollup,mergeable,headRefName,baseRefName
gh pr checks <pr_url> 2>/dev/null || true
```

Also collect: user feedback from chat; open issues not `state:ready-for-review`; PR review comments (CodeRabbit, Kilo, bots, humans).

When cwd is **spec**, pass **`--repo <impl_repo>`** from handoff for impl data.

Read PRD from spec sibling path when available (`docs/prd/<slug>.md` or `$SPEC_REPO/docs/prd/<slug>.md`).

#### R2. Task `review` — PR feedback triage

```text
execution_mode: github_pr_feedback_triage
feature_slug: <slug>
prd_path: <path or N/A>
pr_url: <url>
issue_rollup: <summary or JSON>
check_status: <CI summary>
user_feedback: <from chat or none>
completion_context: <orchestrate handoff if any>
```

#### R3. Task `strategist` (Phase R only)

Pass review output + incomplete tickets + user feedback. Ask for: fix-now vs defer, duplicate grouping, mapping user asks → tickets, precise orchestrate instructions.

#### R4. Outcomes

| Verdict | Action |
|---------|--------|
| **Needs changes** | Publish remediation issues (R5) → Orchestrate paste (R6). **Do not** accept issues or write docs. |
| **Merge-ready** | Proceed to **Phase 1** — do not write docs yet |

After Orchestrate remediates and user pastes back, re-run **Phase R** (short re-check) until Merge-ready.

#### R5. Publish remediation issues

For each approved remediation slice, Task **`developer`** or run approved wrapper:

```bash
bin/publish-targeted-issue \
  --repo <impl_owner/name> \
  --title "remediation: <short title>" \
  --feature-slug "<slug>" \
  --parent-issue "<prd_parent_issue_url>" \
  --label "state:ready-for-agent" \
  --label "prd-task" \
  --label "category:chore" \
  --body-file -
```

Body must include acceptance criteria, `task_id: remediation-<slug>-<n>`, and link to PR comment / CI failure when applicable.

Resolve `parent_issue` from `docs/prd/<slug>.md` frontmatter in spec sibling (read via bash from impl cwd).

#### R6. Orchestrate handoff (remediation)

````markdown
## Remediation handoff

| Field | Value |
|-------|-------|
| Feature | `<Display Name>` |
| Slug | `feature:<slug>` |
| Impl repo | `owner/name` |
| Impl path | `/absolute/path` |
| PR | `<pr_url>` |
| Next agent | `orchestrate` in a **new** session (same impl repo) |
| First message | `feature:<slug>` — address remediation issues then re-push PR |

Copy/paste into orchestrate:
```text
feature:<slug>
Remediation: address open feature:<slug> issues (remediation:* and any incomplete). PR: <pr_url>
```

**After orchestrate remediates and pushes**, emit this return paste for the user:

```text
Remediation complete for <Display Name> (`feature:<slug>`).
PR: <pr_url>
impl architect option 4 → R — re-check PR feedback, CI, tickets, and user input.
```
````

---

### Phase 1 — Acceptance labeling (Merge-ready only)

#### 1. Data collection

Same as legacy verification: issues, PR, PRD, verifier evidence.

#### 2. Task `review` — feature sign-off

```text
execution_mode: github_feature_signoff
feature_slug: <slug>
prd_path: <path>
pr_url: <url>
issue_rollup: <summary>
completion_context: <orchestrate handoff>
```

#### 3. Accept issues (label only — do not close)

Task **developer** `load: minimal`:

```text
load: minimal
execution_mode: github_issue_stage
issue_number: <n>
repo: <owner/name>
stage_id: mode-f-signoff-accept
stage:
  objective: Label all accepted feature:<slug> issues state:done (issues stay open)
  files: []
  acceptance: mode-f-accept-issues.sh exits 0; issues are state:done and still open
  test_commands:
    - bash "$OC/skills/architect-review/lib/mode-f-accept-issues.sh" "<slug>" "<pr_url>" --repo <owner/name>
  commit_message: "chore(<slug>): architect Mode F accept issues"
```

**Gate:** Every accepted issue shows **`state:done`** and remains **open**. Do not use `mode-f-close-issues.sh` in impl Mode F.

Report **Phase 1 complete** table: slug, PR, accepted issue numbers, deferrals. Pause for doc scope.

---

### Phase 2 — Documentation (after human doc-scope gate)

#### 4. Human gate (required)

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

#### 5. Task `document` → `scribe` → verify on disk → Task `developer` docs commit

Same as prior Mode F Phase 2 (document, scribe, `test -f`, docs-only commit/push on feature branch).

#### 6. Finish — handoff to Spec

**Phase 2 complete message:** Table with PR URL, accepted (open) issue list, doc paths, archive status.

Emit **Spec feature-complete** paste:

````markdown
## Spec handoff

| Field | Value |
|-------|-------|
| Feature | `<Display Name>` |
| Slug | `feature:<slug>` |
| Impl repo | `owner/name` |
| PR | `<pr_url>` |
| Next | **spec** architect option 3 **feature-complete** |

Copy/paste into spec architect:
```text
feature-complete <slug>
Impl repo done: owner/name PR: <pr_url>
```
````

**Mode F impl sign-off is not complete** until Phase 2 push succeeds or push failure is reported with manual next steps.

---

## Mode B — Post-implementation (`.plan` review + documentation)

When user reports orchestrate completed on a **`.plan` artifact** and verifier passed: **review** → **documentation** → **`archive_plan`**. **Mode B is not finished until the plan file is renamed to `*.completed.md` or scribe reports `SCRIBE_FAILED` on archive after retry.**

## Completion Flow — Mode B

1. **Review:** Invoke `review` with `artifact_path` and completion context.
2. **If remediation:** Scribe `.plan/review.<slug>.md`; **new orchestrate session** — do not continue sign-off for execution.
3. **If sign-off:** Task `document` with artifact path.
4. **Write docs:** Scribe each path from document output as needed.
5. **Verify on disk:** architect `test -f` / `ls` per path; retry scribe once on miss.
6. **Archive (MANDATORY):** Task `scribe` with `operation: archive_plan`.
7. Report with compact table and exact next action.

When Mode F also ran on a hybrid path, run Mode B step 6 after Mode F Phase 2.
