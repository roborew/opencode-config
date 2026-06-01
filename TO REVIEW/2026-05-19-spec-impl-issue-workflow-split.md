# 2026-05-19 — Spec vs implementation issue workflow split, YAML tickets, and agent-only bin usage

**Session scope:** Redesign the spec-driven feature pipeline after a failed **`downgrade-archival-recovery`** run in **blocshed-web**: `bin/issue-expand-bundle` jq crash, architect manually re-fetching GitHub issues, gates passing on thin JSON blobs, and the agent wrongly treating existing code as “ticket done”. Split **spec** (requirements only) from **implementation** (codebase-backed technical planning). Replace fat **`opencode-task-json`** with readable markdown + **`opencode-task-yaml`**. Enforce **agents run `bin/*`** — humans only run **`setup-project`** once.

**Status:** Designed, implemented, and refined in chat. **Verify on disk before merge** — this workspace may have diverged since the session (e.g. `skills/issue-expand/`, `templates/spec-repo/bin/lib/issue_contract.py`, or a slimmed `README.md` may not match what was edited here).

**Related context:** [`2026-05-19-registry-migration-scribe-write-fixes.md`](2026-05-19-registry-migration-scribe-write-fixes.md) — same blocshed stack / `downgrade-archival-recovery` setup thread.

---

## Executive summary

| Topic | Outcome |
| --- | --- |
| Root incident | `issue-expand-bundle` aborted on jq error; agent ran manual `gh` loops; equated “code exists” with “acceptance met”. |
| Spec overreach | PRD/fanout required `test_commands`, `commit_message`, file paths — moved to **impl-only** planning. |
| Issue body contract | **Requirements** (product) + **Implementation planning** (Context, Current state, Stage plan, Tests) + slim **yaml** block. |
| Gates | `feature-check` / `orchestrate-readiness-check` require **substantive** plans, not non-empty JSON `stages[]`. |
| Cleanup | Shared **`issue_contract.py`**; bundle readiness via `validate_issue_body.py --hints` (removed duplicate jq rules). |
| UX fix | **Never** tell the user to run impl `bin/*` — only **`setup-project`** once; architect runs all other scripts. |

---

## 1. Problems diagnosed (trigger session)

### 1.1 Symptom: `issue-expand-bundle` failed

```text
jq: error (at <stdin>:1): Cannot index boolean with string "body"
```

Reproduced when jq input is a boolean or array of booleans (e.g. `[true]`) piped into filters using `.body`. Likely triggers: unguarded parent-issue fetch, malformed `ISSUES_JSON`, or `set -e` aborting mid-write.

The agent then manually ran **`gh issue view`** for seven issues instead of fixing the script.

### 1.2 Symptom: false “orchestrate-ready”

- **`feature-check`** and **`orchestrate-readiness-check`** passed on **`downgrade-archival-recovery`** open issues (#77–#83).
- Tickets had large **`opencode-task-json`** `stages[]` but thin human sections.
- Agent grep’d production code, saw archive/unarchive implementations, concluded work was done — **without** checking tests or acceptance mapping.

### 1.3 Symptom: unreadable tickets

User could not review GitHub issues: huge JSON blob, light user stories / implementation plan. Planning quality should match **legacy `.plan/feature.*.md`**, stored on the issue.

### 1.4 Symptom: command laundry lists

Assistant told the user to run:

```text
bin/issue-expand-bundle …
bin/feature-check …
bin/orchestrate-readiness-check …
```

User policy: **one shell script ever** — **`setup-project`** from project parent — everything else via OpenCode agents.

---

## 2. Design decisions (agreed in chat)

### 2.1 Two-phase responsibility

| Phase | Repo | Owns |
| --- | --- | --- |
| **Requirements** | spec | User stories, product acceptance, repo/capability tickets, blockers, grill-me context |
| **Technical planning** | impl | Context, current state, files, TDD stages, tests, yaml `stages[]` — from **indexed codebase** |

Spec must **not** assume impl file paths or test commands. Implementation architect discovers reality via **claude-context** (mandatory).

### 2.2 Canonical issue body (target)

```markdown
Parent PRD: <url>

## User stories covered
…

## Requirements
… (product outcomes only — from PRD acceptance)

## Implementation planning
### Context
### Goal
### Current state
### Stage plan
### Files to change
### Tests
### Refactor / risks

## OpenCode task (machine-readable)
```opencode-task-yaml
task_id: …
owner: …
capability: …
depends_on: […]
stages:
  - stage_id: …
    …
```

**Blocked by:** …

## Description
…
```

- **Markdown** = human review surface (same facts as a `.plan` artifact).
- **YAML fence** = orchestrate projection (replaces JSON blob).
- Legacy **`opencode-task-json`** parsed during migration only.

### 2.3 Human vs agent shell

| Who | Runs |
| --- | --- |
| **Human (once)** | `setup-project` from project parent (`~/code/APP`) |
| **Architect** | `bin/issue-expand-bundle`, `bin/feature-check`, `bin/orchestrate-readiness-check`, `bin/feature-context`, `bin/fanout`, `bin/feature-upgrade`, … |
| **Human (OpenCode)** | Front-door menu, approve PRDs/plans/issue edits, switch to **orchestrate** when prompted |

---

## 3. Implementation (files touched)

### 3.1 New shared libraries (`templates/spec-repo/bin/lib/`)

| File | Purpose |
| --- | --- |
| **`extract_task_meta.py`** | Parse **`opencode-task-yaml`** or legacy **`opencode-task-json`**; CLI emits JSON for shell scripts. |
| **`task_meta_to_yaml.py`** | Emit slim yaml from JSON object (fanout routing fields + optional `stages[]`). |
| **`issue_contract.py`** | Shared placeholders, section extractors, **`has_substantive_impl_planning()`** — dedupes validate + extract. |

### 3.2 Spec fanout (slim requirements phase)

| File | Changes |
| --- | --- |
| **`build_issue_body.sh`** | Sections: User stories, **Requirements**, **Implementation planning** (placeholder), **opencode-task-yaml** fence. |
| **`fanout`** | Product acceptance → Requirements bullets; yaml meta = `task_id`, `owner`, `capability`, `depends_on` only; yaml `task_id` matching in `existing_issue_number`. |
| **`sync-fanout-bodies`** | Same slim meta; preserves substantive **Implementation planning** and `stages[]` on resync. |
| **`validate_prd_frontmatter.py`** | Required: `repo`, `capability`, `title`, `owner`, `acceptance`. **Optional:** `commit_message`, `test_commands`. |
| **`validate_issue_body.py`** | **fanout** level: Requirements, no `stages[]`. **orchestrate** level: substantive Implementation planning + non-empty `stages[]`. Added **`--hints`** for bundle. |
| **`extract_issue_sections.py`** | Refactored to use **`issue_contract`**; preserve flags for sync. |
| **`templates/spec-repo/docs/prd/_template.md`** | Document spec vs impl fields; example tickets without test_commands. |
| **`templates/spec-repo/skills/fanout-issues/SKILL.md`** | Spec-only fanout; agent runs `bin/fanout`; user directed to impl **architect option 1**. |

### 3.3 Implementation repo tooling

| File | Changes |
| --- | --- |
| **`templates/bin/issue-expand-bundle`** | jq guards; **`--state open`** default (`--include-closed` optional); parent-issue fetch safety; readiness via **`validate_issue_body.py --hints`**; **`OC_ROOT`** for validate path; Errors section on partial failure. |
| **`templates/bin/feature-context`** | Safe parent-issue jq (no `.body` on boolean). |
| **`templates/bin/feature-check`** | Task id from **`extract_task_meta.py`**; yaml + json fences. |
| **`templates/bin/orchestrate-readiness-check`** | Parse meta via Python; clearer FAIL messaging. |
| **`skills/github-issue-run/lib/next-runnable-issue.sh`** | **`extract_task_meta.py`** for `opencode_meta`. |

### 3.4 Skills and agents

| File | Changes |
| --- | --- |
| **`skills/issue-expand/SKILL.md`** | Full rewrite: implementation technical planning; architect runs all bins; hard rules (no “code exists = done”, no user command lists). |
| **`agents/architect.md`** | **Human vs agent shell commands** hard rule; impl menu option 1 wording; spec menu without user-facing `bin/fanout` text. |
| **`skills/to-prd/SKILL.md`** | Tickets = product acceptance only; no PRD `test_commands` / `commit_message` requirement. |
| **`skills/orchestrate-execution/SKILL.md`** | GitHub mode references yaml + issue-expand prerequisite. |
| **`skills/architect-review/SKILL.md`** | Sign-off reads Implementation planning + yaml. |
| **`skills/github-issue-run/SKILL.md`** | yaml primary, json legacy. |

### 3.5 Documentation

| File | Changes |
| --- | --- |
| **`docs/FEATURE-PIPELINE.md`** | Two-phase flow; agent-centric (not user bin runbook). |
| **`docs/plan-artifact-schema.md`** | **`opencode-task-yaml`** contract; fanout vs issue-expand fields. |
| **`docs/skills/issue-expand-bundle.md`** | Marked agent-internal. |
| **`docs/smoke/github-issue-execution.md`** | Expect yaml + substantive planning. |
| **`README.md`** | Daily use = OpenCode menus only; **`setup-project`** once. |

### 3.6 Sync and script output

| File | Changes |
| --- | --- |
| **`bin/stack/sync_spec_tooling.sh`** | Sync **`issue_contract.py`**, **`extract_task_meta.py`**, **`task_meta_to_yaml.py`**. |
| **`templates/spec-repo/bin/feature-upgrade`** | Next steps: “OpenCode architect option 1” per impl repo — not `bin/issue-expand-bundle` commands. |
| **`templates/spec-repo/bin/sync-fanout-bodies`** | Done message points to architect option 1. |

---

## 4. Validation behaviour (after changes)

### 4.1 Fanout level — passes with

- Parent PRD URL, User stories, Requirements, yaml `task_id` + `owner`, **no** `stages[]`.

### 4.2 Orchestrate level — fails until

- Non-placeholder **Requirements** and **User stories**.
- **Implementation planning** with **Context**, **Current state**, **Stage plan**, **Tests** (or substantive legacy **Implementation plan** ≥120 chars during migration).
- Non-empty **`stages[]`** in yaml/json with required stage fields.

**Existing `downgrade-archival-recovery` json tickets are expected to FAIL** until re-planned via **architect option 1**.

### 4.3 Legacy migration path

- **`extract_task_meta.py`** reads both fence types.
- **`issue_contract.has_substantive_impl_planning()`** accepts filled legacy **Implementation plan** section temporarily.
- **`sync-fanout-bodies`** preserves planning content and `stages[]` when refreshing spec sections from PRD.

---

## 5. Cleanup pass (same session)

| Before | After |
| --- | --- |
| Duplicate placeholder / plan logic in **`validate_issue_body.py`** and **`extract_issue_sections.py`** | **`issue_contract.py`** |
| Six jq readiness lines in **`issue-expand-bundle`** | Single loop calling **`validate_issue_body.py --hints`** |
| Fat fanout json meta (`acceptance`, `test_commands`, `commit_message` in fence) | Slim yaml routing only |
| Stale docs mandating PRD `test_commands` | Updated **to-prd**, **FEATURE-PIPELINE**, **README** |

**Intentionally kept (not redundant yet):**

- Legacy **json** fence parsing (until all issues migrated).
- Two **`feature-check`** scripts (spec multi-repo vs impl single-repo).
- **`META_JSON` → `task_meta_to_yaml.py`** pipeline in fanout (thin intermediate).

**Optional phase 2 (not done):** drop json fence support after all open issues use yaml + new markdown sections.

---

## 6. Intended user workflow (post-change)

### Once per stack

```bash
cd ~/code/APP && setup-project
```

(Shell bootstrap from OpenCode config `bin/` — syncs tooling into spec + impl repos.)

### Product feature

1. Open **spec** repo → **architect** → option 1 → grill-me → to-prd → approve PRD.
2. Architect runs fanout (skill) — user does **not** run `bin/fanout`.

### Implementation feature (e.g. `downgrade-archival-recovery`)

1. Open **blocshed-web** → **architect** → **option 1** → slug `downgrade-archival-recovery`.
2. Architect runs bundle, investigates codebase, drafts **Implementation planning** per issue.
3. User approves each issue body edit in chat.
4. Architect runs gates; when PASS → **Switch to orchestrate**.
5. **orchestrate** executes yaml `stages[]` per issue.

**No other terminal commands** for the user in this path.

---

## 7. What was explicitly rejected / fixed in chat

| Bad behaviour | Fix |
| --- | --- |
| Gates pass → skip to orchestrate | Gates require substantive planning sections |
| Production code grep → “ticket done” | issue-expand hard rule: map acceptance → tests or explicit gap |
| Paste `bin/*` command lists to user | architect + issue-expand: agents run bins |
| Spec PRD defines file paths and test commands | PRD acceptance = product outcomes only |
| Unreadable json blob on issues | Markdown planning + compact yaml |

---

## 8. Verify on disk (checklist)

Run from OpenCode config repo:

```bash
test -f templates/spec-repo/bin/lib/issue_contract.py && echo OK issue_contract
test -f templates/spec-repo/bin/lib/extract_task_meta.py && echo OK extract_task_meta
grep -q "Human vs agent shell" agents/architect.md && echo OK architect rule
grep -q "The user does not run" skills/issue-expand/SKILL.md && echo OK issue-expand
grep -q "OpenCode only" README.md || grep -q "OpenCode menus" README.md && echo OK readme
```

Re-sync impl repo after confirming files:

```bash
OPENCODE_CONFIG=~/.config/opencode \
  ~/.config/opencode/bin/stack/sync_impl_tooling.sh /path/to/blocshed-web
```

Re-sync spec repo:

```bash
OPENCODE_CONFIG=~/.config/opencode \
  ~/.config/opencode/bin/stack/sync_spec_tooling.sh /path/to/blocshed-spec
```

---

## 9. Open follow-ups (not finalized in chat)

- Re-run **architect option 1** on **blocshed-web** for `downgrade-archival-recovery` to replace json blobs with readable plans (human approves each edit).
- Close duplicate **closed** issues (#66–#76) with same label to reduce noise (optional hygiene).
- Phase 2: remove **`opencode-task-json`** parsing once migration complete.
- Confirm **`downgrade-archival-recovery`** PRD exists on spec default branch (404 on raw GitHub during incident).

---

## 10. File index (quick lookup)

```
agents/architect.md
bin/stack/sync_spec_tooling.sh
docs/FEATURE-PIPELINE.md
docs/plan-artifact-schema.md
docs/skills/issue-expand-bundle.md
docs/smoke/github-issue-execution.md
README.md
skills/architect-review/SKILL.md
skills/github-issue-run/SKILL.md
skills/github-issue-run/lib/next-runnable-issue.sh
skills/issue-expand/SKILL.md
skills/orchestrate-execution/SKILL.md
skills/to-prd/SKILL.md
templates/bin/feature-check
templates/bin/feature-context
templates/bin/issue-expand-bundle
templates/bin/orchestrate-readiness-check
templates/spec-repo/bin/fanout
templates/spec-repo/bin/feature-upgrade
templates/spec-repo/bin/sync-fanout-bodies
templates/spec-repo/bin/lib/build_issue_body.sh
templates/spec-repo/bin/lib/extract_issue_sections.py
templates/spec-repo/bin/lib/extract_task_meta.py
templates/spec-repo/bin/lib/issue_contract.py
templates/spec-repo/bin/lib/task_meta_to_yaml.py
templates/spec-repo/bin/lib/validate_issue_body.py
templates/spec-repo/bin/lib/validate_prd_frontmatter.py
templates/spec-repo/docs/prd/_template.md
templates/spec-repo/skills/fanout-issues/SKILL.md
```
