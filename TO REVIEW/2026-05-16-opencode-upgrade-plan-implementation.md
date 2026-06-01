# 2026-05-16 — OpenCode Upgrade Plan: Full Implementation Record

**Document filename:** `2026-05-16-opencode-upgrade-plan-implementation.md` — prefix **`2026-05-16`** is the **Cursor chat created date** (not “today” when this file was last edited).

| Field | Date | Source |
| --- | --- | --- |
| **Cursor chat created** | **2026-05-16** | Transcript file birth `2026-05-16 15:24`; first user message Saturday, May 16, 2026, 3:24 PM (UTC+1) |
| Implementation finalized (t0–t12) | **2026-05-16** | Same chat session through ~18:56 UTC+1 |
| Prototypes + `feature-context` README pull | **2026-05-16** | Same session (~18:37–18:39 UTC+1) |
| This TO REVIEW doc expanded | 2026-06-01 | Follow-up turn only — **do not** rename file to 2026-06-01 |

**Transcript ID:** `e795de6b-374e-4973-977e-db304fea24e3` — snippets below were recovered from that transcript’s `Write` / `StrReplace` operations.

**Path rule:** Upgrade docs say `.opencode/skills/`; this repo uses **`skills/`** at the config repo root.

**Recreation order for another AI:** (1) copy `docs/upgrade-spec/*` from Downloads → (2) skills t1–t5 → (3) `check-plan.sh` + plan schema + orchestrate/architect-plan patches → (4) `templates/spec-repo/` tree → (5) `bin/new-spec-repo`, `bin/link-spec-repo`, `templates/bin/feature-context` → (6) registries + architect allowlist → (7) prototype scaffold + `feature-context` PRD pull → (8) `bash scripts/validate-opencode-config.sh`.

**Session scope:** Implement all **12 tickets (t0–t12)** from the **OpenCode Workflow Upgrade Plan** (Peacock-parity skills, per-application spec repos, plan enforcement, CONTEXT/LANGUAGE elevation, multi-repo tooling). Source specs were copied into the config repo; execution derived file content from those specs and from plan refinements agreed in chat (per-app spec model, TDD + per-stage commits, N implementation repos).

**Status:** All plan todos **t0–t12** marked **completed** in chat. **`bash scripts/validate-opencode-config.sh`** reported success after the implementation pass.

**Chat transcript:** [OpenCode upgrade plan](e795de6b-374e-4973-977e-db304fea24e3)

**Plan file (do not edit):** `~/.cursor/plans/opencode_upgrade_plan_e7efc1b9.plan.md` (uploaded copy: `.cursor/projects/.../uploads/opencode_upgrade_plan_e7efc1b9.plan-L1-L399-0.md`)

**Authoritative specs (versioned in repo after t0):**

- `docs/upgrade-spec/upgrade-plan.md` (from `~/Downloads/opencode_upgrade_plan.md`)
- `docs/upgrade-spec/onboarding-supplement.md` (from `~/Downloads/opencode_onboarding_supplement.md`)

**Verify on disk:** Later sessions may have refactored shell entry points (e.g. unified `bin/setup-project`), extended issue-backed execution, or changed registry files. Before relying on paths below, confirm they exist in your checked-out `~/.config/opencode` tree and compare with related TO REVIEW docs (especially `2026-05-19-spec-central-stack-workflow-implementation.md`).

---

## Executive summary

| Area | Outcome |
| --- | --- |
| Source archive | `docs/upgrade-spec/` holds upgrade plan + onboarding supplement |
| New skills | `to-prd`, `triage`, `research`, `improve-codebase-architecture` |
| Plan gates | `check-plan.sh`, orchestrate precondition, architect-plan post-condition, schema updates |
| Context | `docs/templates/CONTEXT.md`; grill-me / architect-plan / setup-skills / `opencode.md.template` wired |
| QA artifact | `skills/orchestrate-execution/templates/qa.md`; orchestrate terminal QA step; schema `QAPlan` |
| Multi-repo | `templates/spec-repo/`; `bin/new-spec-repo`; `bin/link-spec-repo`; spec bins (`new-prd`, `fanout`, `status`) |
| Impl bridge | `templates/bin/feature-context` (reads spec repo from `issue-tracker.md`); `child-feature.yml` |
| Setup | `setup-skills` templates expanded (issue-tracker, triage-labels, domain, agents-block, CONTEXT, LANGUAGE) |
| Registries | `ocx.jsonc` + `dcp.jsonc` populated per plan (verify current contents if empty) |
| Prototypes (chat) | Canonical `APP-spec/docs/prototypes/<slug>/`; PRD links; `new-prd` scaffolds; `feature-context` pulls README |
| Architecture | **One spec repo per application** — not a global `roborew/spec` |

---

## Problem statement (why this work happened)

1. **Missing Peacock-parity skills** — no `to-prd`, `triage`, `research`, or `improve-codebase-architecture` in the shared config.
2. **Weak plan contract** — orchestrate could run without a validated `.plan` artifact; no machine check for required sections.
3. **No product spec layer** — PRDs, fanout, and parent issues lived only in the upgrade docs, not as a reusable scaffold in the config repo.
4. **Monolithic spec assumption** — original upgrade doc assumed one `roborew/spec`; product context (`CONTEXT.md`, `repos.md`) is app-scoped.
5. **Empty registries** — `ocx.jsonc` and `dcp.jsonc` were stubs.

---

## Architecture decisions locked in this chat

### Per-application spec repos (replaces global `roborew/spec`)

| Concept | Convention |
| --- | --- |
| Spec repo | `roborew/<app-slug>-spec` (e.g. `roborew/blockShed-spec`) |
| Implementation repos | Any mix: `<app-slug>-web`, `<app-slug>-api`, ingest, infer, etc. — **not** always frontend+api |
| Registry | `docs/agents/repos.md` in the spec repo lists only that app's targets |
| Config repo | `~/.config/opencode` stays **shared** and project-agnostic; holds `templates/spec-repo/` |
| Local layout | `~/code/<app-slug>/` container with sibling clones: `<app-slug>-spec`, `<app-slug>-web`, … |

### Human vs automated split

| Automated (scripts / agents) | Human |
| --- | --- |
| `bin/new-spec-repo` creates **spec** repo + scaffold + labels (+ project board attempt) | Create **implementation** GitHub repos first |
| `bin/link-spec-repo` wires target → spec | `gh` auth, PAT for `LABEL_SYNC_PAT`, project column rules in browser |
| PRD / fanout / planning in **spec** repo | Per-target `setup-skills`, `opencode.md`, smoke tests |
| Execution in **target** repo via `bin/feature-context` → architect-plan → orchestrate | Branch protection policies, org access |

### Cross-cutting execution constraint (TDD + commits + issues)

Each plan **stage** must:

1. Define tests in `StageAcceptanceChecks` before implementation.
2. Complete with verifier PASS and **`tests_run` evidence**.
3. End with a **single `git commit`** whose message uses the stage's draft **`CommitMessage`** and references **`IssueRef`** (`Refs: #n` / `Closes: #n`).
4. Not advance until commit exists (orchestrate treats missing commit as **NEEDS_RETRY**).

Architect pre-populates `IssueRef` and `CommitMessage` per stage (numbers from `bin/feature-context` / GitHub issue context).

### Design prototypes (post-ticket addition in chat)

| Rule | Detail |
| --- | --- |
| Location | **`APP-spec/docs/prototypes/<slug>/`** only (canonical) |
| Scaffold | `docs/prototypes/_template/` (`README.md`, `assets/`, `screenshots/`) |
| PRD | `to-prd` / PRD template link prototype path |
| `bin/new-prd` | Creates matching `docs/prototypes/<slug>/` when scaffolding a PRD |
| `feature-context` | Includes prototype **README** from spec (reference only — **no copy** into impl repos) |

### LANGUAGE.md auto-scaffold

- Spec template includes `LANGUAGE.md`.
- `setup-skills` drops `LANGUAGE.md` template when missing in a target repo.
- `improve-codebase-architecture` may scaffold via scribe if absent.

### Git flow (advice only — not committed as standalone doc)

| Repo | Branch pattern |
| --- | --- |
| Spec | PRD branches → merge to `main` → then `bin/fanout` |
| Implementation | `feature/<slug>-<slice>` (or stage-scoped branches per team practice) |

---

## Target workflow (after this implementation)

```text
~/.config/opencode/          # Shared skills, templates, bin scripts
docs/upgrade-spec/           # Archived upgrade specs

# Greenfield app
bin/new-spec-repo <app> [target-repo...]   # Creates roborew/<app>-spec
# Human: create impl repos, clone under ~/code/<app>/
# Per impl repo:
bin/link-spec-repo roborew/<app>-spec
setup-skills (OpenCode architect)

# Feature (spec repo)
grill-me → to-prd → approve PRD → bin/new-prd / bin/fanout <slug>
# Optional: docs/prototypes/<slug>/

# Feature (implementation repo)
bin/feature-context <issue#>  → tmp/feature-context.md
architect-plan → .plan/feature.<slug>.md  (check-plan.sh valid)
orchestrate-execution → stages + commits + .qa/<slug>.md
```

**Path correction:** Upgrade docs say `.opencode/skills/`; this repo uses **`skills/`** at the repo root.

---

## Ticket-by-ticket implementation record

### t0 — Archive source documents

| Deliverable | Path |
| --- | --- |
| Upgrade plan copy | `docs/upgrade-spec/upgrade-plan.md` |
| Onboarding supplement copy | `docs/upgrade-spec/onboarding-supplement.md` |

```bash
mkdir -p docs/upgrade-spec
cp ~/Downloads/opencode_upgrade_plan.md docs/upgrade-spec/upgrade-plan.md
cp ~/Downloads/opencode_onboarding_supplement.md docs/upgrade-spec/onboarding-supplement.md
```

---

### t1 — `to-prd` skill

| Deliverable | Path |
| --- | --- |
| Skill | `skills/to-prd/SKILL.md` |
| PRD template | `skills/to-prd/templates/prd.md` |
| Issue body template | `skills/to-prd/templates/prd-issue.md` |
| Doc pointer | `docs/skills/to-prd.md` |
| Registry | Entry in `ocx.jsonc` |

**Behaviour (summary):** Synthesise PRD from grill-me context + optional `.research/<slug>.md`; write `docs/prd/<slug>.md`; open GitHub issue with labels `prd`, `state:ready-for-agent`, `feature:<slug>`; **halt** — do not auto-invoke `to-issues`.

---

### t2 — `triage` skill

| Deliverable | Path |
| --- | --- |
| Skill | `skills/triage/SKILL.md` |
| CLI helper | `skills/triage/lib/triage.sh` |
| Canonical labels doc | `docs/agents/triage-labels.md` |

**Behaviour (summary):** Five-state machine per upgrade spec; refuses `needs-info → ready-for-agent` without human reply; batch transitions via `gh`.

---

### t3 — `improve-codebase-architecture` + LANGUAGE.md

| Deliverable | Path |
| --- | --- |
| Root glossary | `LANGUAGE.md` (7-row table: Module, Interface, Seam, Depth, Leverage, Locality, Deletion test) |
| Skill | `skills/improve-codebase-architecture/SKILL.md` |
| Findings template | `skills/improve-codebase-architecture/templates/findings.md` |
| Consumers | `skills/architect-plan/SKILL.md`, `skills/refactor/SKILL.md` load `LANGUAGE.md` |

---

### t4 — `setup-skills` templates

| Deliverable | Path |
| --- | --- |
| Templates | `skills/setup-skills/templates/issue-tracker.md`, `triage-labels.md`, `domain.md`, `agents-block.md`, `CONTEXT.md`, `LANGUAGE.md` |
| Copy table | `skills/setup-skills/SKILL.md` §4b — includes `feature-context`, child-feature template |
| Labels | `state:*`, `category:*`, `mode:*` per upgrade §P0.2 / §P1.1 |

**Note:** Templates reference **parent spec repo** via `issue-tracker.md` (per-app), not hardcoded `roborew/spec`.

---

### t5 — `research` skill

| Deliverable | Path |
| --- | --- |
| Skill | `skills/research/SKILL.md` |
| Template | `skills/research/templates/research.md` (5 sections) |
| Cache dir | `.research/.gitkeep` |
| Consumer | `architect-plan` optionally loads `.research/<slug>.md` |

---

### t6 — Enforce `.plan` before orchestrate

| Deliverable | Path |
| --- | --- |
| Validator script | `skills/orchestrate-execution/lib/check-plan.sh` |
| Orchestrate skill | `skills/orchestrate-execution/SKILL.md` — step 0 precondition; per-stage commit after verifier PASS |
| Architect skill | `skills/architect-plan/SKILL.md` — scribe terminal write; post-condition; `IssueRef` + `CommitMessage` per stage |
| Schema | `docs/plan-artifact-schema.md` — required sections; stage `IssueRef`, `CommitMessage`; completion report `git_commit` |

**`check-plan.sh` (summary):** Exits **2** if plan file missing; **3** if required sections missing (`Difficulty`, `StagePlan`, `VerifierInputs`, `DocumentationOutputs`, `ReviewDecisionGate`, etc. per spec).

**Later sessions:** Orchestrate may delegate `check-plan.sh` to `developer` (`load: minimal`) for bash permission reasons — see `2026-05-17-subagent-bash-permissions-and-orchestrator-delegation.md`.

---

### t7 — CONTEXT.md mandatory pattern

| Deliverable | Path |
| --- | --- |
| Template | `docs/templates/CONTEXT.md` (6 sections per §P0.4) |
| Grill-me | `skills/grill-me/SKILL.md` — scaffold / validate glossary |
| Architect-plan | Load `CONTEXT.md`; refuse unfilled stub |
| Setup-skills | Drops `CONTEXT.md` template on setup |
| Opencode template | `docs/templates/opencode.md.template` — domain terms → CONTEXT reference |

---

### t8 — QA plan artifact

| Deliverable | Path |
| --- | --- |
| QA template | `skills/orchestrate-execution/templates/qa.md` |
| Orchestrate skill | Terminal step: scribe writes `.qa/<slug>.md` |
| Schema | `docs/plan-artifact-schema.md` — `QAPlan`; verifier = technical/CI, QA = human-observable |

---

### t9 — Per-app spec repo scaffold + bin scripts

#### 9a — `templates/spec-repo/`

| Component | Path (under `templates/spec-repo/`) |
| --- | --- |
| Product context | `README.md`, `CONTEXT.md`, `LANGUAGE.md` |
| PRD | `docs/prd/_template.md` (YAML frontmatter + 8 body sections) |
| ADR placeholder | `docs/adr/.gitkeep` |
| Agents | `docs/agents/issue-tracker.md`, `triage-labels.md`, `repos.md` |
| Prototypes | `docs/prototypes/_template/` (+ `.gitkeep` at `docs/prototypes/`) |
| GitHub | `.github/labels.yml`, `ISSUE_TEMPLATE/prd-parent.yml`, `research.yml`, `workflows/sync-labels.yml` |
| Skill | `skills/fanout-issues/SKILL.md` |
| Bins | `bin/new-prd`, `bin/fanout`, `bin/status` (+ `bin/lib/*` helpers as implemented) |

#### 9b — `bin/new-spec-repo`

| Behaviour | Detail |
| --- | --- |
| Invocation | `bin/new-spec-repo <app-slug> [target-repo...]` |
| Creates | `gh repo create roborew/<app-slug>-spec`, copies scaffold, substitutes slug |
| Pre-registers | Target repos in `docs/agents/repos.md` when passed as args |
| Protects | `main` branch (force-push off, deletion off, linear history) |
| Labels | Seeds label set into spec + named targets |
| Project | `gh project create` + link repos; **column automation** documented as manual |
| Prints | PAT secret instructions, URL, remaining checklist |

#### 9c — `bin/link-spec-repo`

| Behaviour | Detail |
| --- | --- |
| Run from | Target implementation repo cwd |
| Writes | `docs/agents/issue-tracker.md` → spec repo |
| Copies | `bin/feature-context` from config template if missing |
| Gitignore | Adds `tmp/` if absent |

---

### t10 — `feature-context` (spec-repo-agnostic)

| Deliverable | Path |
| --- | --- |
| Template script | `templates/bin/feature-context` |
| Doc | `docs/skills/feature-context.md` |
| Wiring | `setup-skills` copies to target `bin/feature-context` |

**Behaviour (summary):** Read `SPEC_REPO` from `docs/agents/issue-tracker.md`; resolve slug from `feature:` label; fetch PRD via `gh api`; include local `CONTEXT.md`; optional **`docs/prototypes/<slug>/README.md`**; write `tmp/feature-context.md`.

---

### t11 — Child-feature issue template

| Deliverable | Path |
| --- | --- |
| Template | `templates/.github/ISSUE_TEMPLATE/child-feature.yml` |
| Wiring | `setup-skills` copies to target repos |

**Fields (summary):** Parent issue (required), feature label, repo scope, acceptance criteria, mode (`mode:afk` / `mode:hitl`).

---

### t12 — `dcp.jsonc` and `ocx.jsonc`

| File | Intended content |
| --- | --- |
| `dcp.jsonc` | Prune rules: drop stale tool transcripts / redundant reads; keep scribe writes; header comment |
| `ocx.jsonc` | Register `to-prd`, `triage`, `improve-codebase-architecture`, `research`; model-routing entries; header comment |
| `agents/architect.md` | Skill allowlist + routing for new planning utilities (per plan) |

**Verify:** If `ocx.jsonc` / `dcp.jsonc` appear empty in your tree, re-apply from `docs/upgrade-spec/upgrade-plan.md` §Ticket 12 or git history.

---

## Complete file inventory (this session)

### New directories / major trees

```text
docs/upgrade-spec/
skills/to-prd/
skills/triage/lib/
skills/research/
skills/improve-codebase-architecture/
skills/orchestrate-execution/lib/
skills/orchestrate-execution/templates/qa.md
templates/spec-repo/
templates/bin/feature-context
templates/.github/ISSUE_TEMPLATE/child-feature.yml
.research/
```

### New or materially updated files (representative)

```text
LANGUAGE.md
docs/templates/CONTEXT.md
docs/agents/triage-labels.md
docs/skills/to-prd.md
docs/skills/feature-context.md
docs/plan-artifact-schema.md
bin/new-spec-repo
bin/link-spec-repo
skills/setup-skills/templates/{issue-tracker,triage-labels,domain,agents-block,CONTEXT,LANGUAGE}.md
skills/setup-skills/SKILL.md
skills/grill-me/SKILL.md
skills/architect-plan/SKILL.md
skills/orchestrate-execution/SKILL.md
skills/refactor/SKILL.md
docs/templates/opencode.md.template
ocx.jsonc
dcp.jsonc
agents/architect.md
README.md                    # multi-repo workflow sections added in session
```

---

## Manual setup checklist (operator)

Run after implementation; order matters.

1. **`gh auth status`** — scopes: `repo`, `workflow`, `read:org`.
2. **Greenfield:** `~/.config/opencode/bin/new-spec-repo <app> [targets...]` then clone under `~/code/<app>/`.
3. **Per impl repo:** `bin/link-spec-repo roborew/<app>-spec` → **`setup-skills`** → copy/fill **`opencode.md`** from `docs/templates/opencode.md.template`.
4. **`LABEL_SYNC_PAT`** on spec repo for `sync-labels` workflow (`gh secret set LABEL_SYNC_PAT --repo roborew/<app>-spec`).
5. **GitHub Project** — verify columns; configure label→status rules manually if CLI cannot.
6. **Smoke:** `bin/feature-context <issue#>` in an impl repo; `bash scripts/validate-opencode-config.sh` in config repo.

### Adding a new implementation repo later (no re-run `new-spec-repo`)

1. Human creates GitHub repo.
2. Edit **`docs/agents/repos.md`** in spec repo.
3. Run **`link-spec-repo`** + **`setup-skills`** in the new repo.
4. Ensure labels exist; fanout new PRD slices as needed.

---

## Validation performed in session

| Check | Result |
| --- | --- |
| `bash scripts/validate-opencode-config.sh` | Passed after implementation |

---

## Discussed in chat but not fully automated

| Item | Notes |
| --- | --- |
| GitHub Project label→column rules | `gh project` cannot set automation; manual in project settings |
| `LABEL_SYNC_PAT` | Human must create PAT and set secret |
| Implementation repo creation | Always human (`gh repo create` / org UI) |
| Global `roborew/spec` | **Rejected** in favour of per-app `<slug>-spec` |
| Dogfood on real product (e.g. mycelia-tree) | Documented as commands in chat; not executed in config repo |
| Commit/push of config repo changes | Left to user unless explicitly requested |

---

## Relationship to later TO REVIEW work

This session laid the **upgrade-plan foundation** (skills, spec template, `new-spec-repo` / `link-spec-repo`, plan/QA gates). Subsequent chats documented in the same folder may **extend or supersede** pieces of it:

| Later doc (examples) | Typical overlap |
| --- | --- |
| `2026-05-19-spec-central-stack-workflow-implementation.md` | Unified `bin/setup-project`, `stack-bootstrap`, issue-backed `stages[]` |
| `2026-05-18-spec-fanout-repo-aware-registry-and-upgrade.md` | Rich `repos.md`, `capability` on tickets, `bin/upgrade-spec-repo` |
| `2026-05-17-subagent-bash-permissions-and-orchestrator-delegation.md` | `check-plan.sh` via `developer` Task |
| `2026-05-19-feature-pipeline-and-architect-front-door.md` | Architect menus / pipeline docs |

When operating a live stack, read **this doc** for what the upgrade session built, then the **latest** dated doc for the subsystem you are changing.

---

## Appendix A — Code snippets for recreation (verbatim from session)

Use these blocks to recreate the implementation. **Later chats** may have moved logic into `bin/setup-project` or changed `agents/architect.md` — merge with current tree if files diverge.

### t0 — Archive specs

```bash
mkdir -p docs/upgrade-spec
cp ~/Downloads/opencode_upgrade_plan.md docs/upgrade-spec/upgrade-plan.md
cp ~/Downloads/opencode_onboarding_supplement.md docs/upgrade-spec/onboarding-supplement.md
```

### t6 — `skills/orchestrate-execution/lib/check-plan.sh`

```bash
#!/usr/bin/env bash
# Validate plan artifact has required sections (orchestrate / CI gate).
# Usage: check-plan.sh <path-to-plan.md>
# Exit 2 = missing file, 3 = incomplete sections, 0 = OK
set -euo pipefail
PLAN="${1:?plan path required}"
[[ -f "$PLAN" ]] || { echo "MISSING_PLAN: $PLAN — run architect-plan first" >&2; exit 2; }
for section in "## Difficulty" "## StagePlan" "## VerifierInputs" "## DocumentationOutputs" "## ReviewDecisionGate"; do
  grep -qF "$section" "$PLAN" || { echo "PLAN_INCOMPLETE: $PLAN missing $section" >&2; exit 3; }
done
echo "PLAN_OK: $PLAN"
```

`chmod +x skills/orchestrate-execution/lib/check-plan.sh`

### t6 — `skills/orchestrate-execution/SKILL.md` inserts

**After `## Required Inputs`, add:**

```markdown
## Plan precondition (mandatory before the stage loop)

When an artifact path is known (user supplied, handoff, or selected from `.plan/`):

1. From the **repository root**, run:

   `bash skills/orchestrate-execution/lib/check-plan.sh "<artifact_path>"`

2. On **non-zero** exit, print the script’s stderr **verbatim**, **do not** start stage execution, and instruct the user to return to **`architect` / `architect-plan`** to repair the plan artifact.

3. On success, continue to **Stage Loop**.
```

**In the stage loop (after verifier PASS), add per-stage commit gate:**

```markdown
6. If verifier passes:
   - **Per-stage git commit (mandatory):** Before advancing, require the execution subagent’s completion report to include **`git_commit`** with **full hash** and **subject** matching the stage’s **`CommitMessage`** and **`IssueRef`** from `StagePlan` (append `Refs: #n` or `Closes: #n` per plan / issue semantics). If `files_changed` is non-empty and there is no commit evidence → grade **NEEDS_RETRY** (same severity as missing tests). Docs-only stages may use `git_commit: none` **only** if the plan explicitly marks that stage as docs-only.
   - Proceed to next stage.
```

**Note:** [`2026-05-17-subagent-bash-permissions-and-orchestrator-delegation.md`](2026-05-17-subagent-bash-permissions-and-orchestrator-delegation.md) later changed this to **Task `developer` `load: minimal`** because orchestrate has `bash: false`.

### t6/t7/t8 — `docs/plan-artifact-schema.md` additions

Add to **Required Sections** table row for `StagePlan`:

```markdown
| **StagePlan** | Ordered stages with `stage_id`, **Owner**, **`IssueRef`** (e.g. `#34`), **`CommitMessage`** (Conventional Commit subject for the single stage commit), objective, dependencies |
```

Add row:

```markdown
| **QAPlan** | Optional in file; mandatory orchestrate output after stages. Human-observable scenarios — distinct from verifier (CI). See `skills/orchestrate-execution/templates/qa.md`. |
```

Add section:

```markdown
### Orchestrate validation (required headings)

Before execution, `skills/orchestrate-execution/lib/check-plan.sh` must find:

- `## Difficulty`
- `## StagePlan`
- `## VerifierInputs`
- `## DocumentationOutputs`
- `## ReviewDecisionGate`

### Per-stage traceability (mandatory)

Every **StagePlan** entry must include **`IssueRef`** and **`CommitMessage`**. Orchestrate treats verifier PASS without a stage commit (when code changed) as **NEEDS_RETRY** unless the plan exempts the stage as docs-only.
```

Example stage block in skeleton:

```markdown
1. `stage_id: stage-ui`
   - Owner: `frontend-dev`
   - IssueRef: `#34`
   - CommitMessage: `feat(ui): add theme toggle`
   - Objective: ...
```

### t7 — `docs/templates/CONTEXT.md`

```markdown
# CONTEXT — <project name>

## One-line purpose

## Primary actors

## Core domain terms

- **<Term>** — <definition>. Synonyms: <…>. Anti-synonyms: <…>.

## Bounded contexts / modules

## External systems and their vocabulary

## Glossary delta vs industry usage
```

**`skills/architect-plan/SKILL.md`:** Add block requiring read of `CONTEXT.md` / `LANGUAGE.md` / `.research/<slug>.md`; refuse unfilled CONTEXT stub; every stage needs **`IssueRef`** + **`CommitMessage`** in Step 5 / StagePlan Structure (see transcript line 49 patches).

### t8 — `skills/orchestrate-execution/templates/qa.md`

```markdown
# QA Plan: <slug>

## Pre-conditions

- Branch: <branch>
- Setup: <commands>

## Scenarios

1. **<User story>** — Steps: <…>. Expected: <observable outcome>. Pass/Fail: ☐

## Regression spot-checks

- …

## Sign-off

- [ ] All scenarios pass
- [ ] No console errors
- [ ] No new lint or type warnings
```

### t1 — `skills/to-prd/SKILL.md` (front matter + core behaviour)

```markdown
---
name: to-prd
description: "Synthesise a PRD from grill-me / research context, write docs/prd/<slug>.md, publish a GitHub issue with prd + state:ready-for-agent + feature:<slug>. Halt after publish — do not invoke to-issues."
modelTier: "smart"
roleReminder: "Run after grill-me when the feature is understood. Scribe writes files; primary uses gh for the issue only if bash is allowed, else delegate."
---

# To PRD

Publish a **human-reviewable PRD** before vertical slicing.

## Behaviour

1. Compose using `skills/to-prd/templates/prd.md` (eight sections).
2. **Invoke `scribe`** → `docs/prd/<slug>.md`.
3. **Create GitHub issue** with labels `prd`, `state:ready-for-agent`, `feature:<slug>`.
4. **Stop** — human review before `to-issues` / `bin/fanout`.
```

Templates `skills/to-prd/templates/prd.md` and `prd-issue.md` — see session transcript line 43 or `~/Downloads/opencode_upgrade_plan.md` §P0.1.

### t2 — `skills/triage/lib/triage.sh`

```bash
#!/usr/bin/env bash
# Batch triage helpers — requires gh, jq. Repo default: current gh repo.
set -euo pipefail

REPO="${TRIAGE_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)}"
if [[ -z "$REPO" ]]; then
  echo "usage: TRIAGE_REPO=owner/name $0 <command> [args]" >&2
  exit 1
fi

state_labels=(state:needs-triage state:needs-info state:ready-for-agent state:ready-for-human state:wontfix)

remove_state_labels() {
  local num="$1"
  local l
  for l in "${state_labels[@]}"; do
    gh issue edit "$num" --repo "$REPO" --remove-label "$l" 2>/dev/null || true
  done
}

cmd_list_needs_triage() {
  gh issue list --repo "$REPO" --label "state:needs-triage" --json number,title,labels --jq '.[] | "#\(.number) \(.title)"'
}

cmd_transition() {
  local num="${1:?issue number}"
  local to="${2:?target state label e.g. state:ready-for-agent}"
  remove_state_labels "$num"
  gh issue edit "$num" --repo "$REPO" --add-label "$to"
  echo "OK: #$num -> $to"
}

case "${1:-}" in
  list-needs-triage) cmd_list_needs_triage ;;
  transition) shift; cmd_transition "$@" ;;
  *)
    echo "commands: list-needs-triage | transition <num> <state:label>" >&2
    exit 2
    ;;
esac
```

`skills/triage/SKILL.md` — state machine + hard rule: no `needs-info` → `ready-for-agent` without human reply (full text in transcript line 44).

### t3 — root `LANGUAGE.md`

```markdown
# LANGUAGE — architecture vocabulary

Shared terms for planning, refactor, and review. Loaded by `architect-plan`, `refactor`, and related skills.

| Term | Definition |
|------|------------|
| **Module** | A unit with a public interface and a hidden implementation. |
| **Interface** | The surface a caller depends on. |
| **Seam** | A point where behaviour can be substituted without editing callers. |
| **Depth** | Ratio of hidden complexity to interface size; deeper is better. |
| **Leverage** | How much downstream simplification a module provides per unit of its own complexity. |
| **Locality** | All code touched by one change lives near each other. |
| **Deletion test** | Could this module be deleted and rewritten in isolation? If no, it lacks depth. |
```

`skills/improve-codebase-architecture/SKILL.md` + `templates/findings.md` — see transcript line 45.

### t5 — `skills/research/SKILL.md`

```markdown
---
name: research
description: "Optional pre-planning cache: write .research/<slug>.md (question, sources, findings, implications, stale-by). architect-plan loads if present."
modelTier: "fast"
---

# Research

Invoke **`scribe`** → `.research/<slug>.md` using `skills/research/templates/research.md`.
```

Add `.research/.gitkeep` at repo root.

### t9b — `bin/new-spec-repo` (full script from session)

```bash
#!/usr/bin/env bash
# Create application spec repo from templates/spec-repo, seed labels, branch protection, optional GitHub Project.
# Usage: GH_ORG=roborew new-spec-repo <app-slug> [target-repo ...]
set -euo pipefail
ORG="${GH_ORG:-roborew}"
APP="${1:?app slug required}"
shift || true
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC_NAME="${APP}-spec"
SPEC_REPO="${ORG}/${SPEC_NAME}"

if gh repo view "$SPEC_REPO" &>/dev/null; then
  echo "Repo $SPEC_REPO already exists — abort" >&2
  exit 1
fi

echo "Creating ${SPEC_REPO}..."
gh repo create "$SPEC_REPO" --private --description "Spec repo: PRDs + parent issues for ${APP}" --clone

CLONE_DIR="$PWD/${SPEC_NAME}"
if [[ -d "$CLONE_DIR" ]]; then
  cd "$CLONE_DIR"
else
  cd "$(find . -maxdepth 2 -name ".git" -type d 2>/dev/null | head -1 | xargs dirname)" 2>/dev/null || cd "$SPEC_NAME"
fi

cp -R "${ROOT}/templates/spec-repo/." .

{
  echo "repos:"
  for t in "$@"; do
    full="$t"
    [[ "$t" != */* ]] && full="${ORG}/${t}"
    echo "  - name: ${full}"
    echo "    role: target"
  done
} > docs/agents/repos.md

git add -A
git commit -m "chore: bootstrap ${SPEC_NAME} scaffold" || true
git push -u origin main || git push -u origin master || true

DEFAULT_BRANCH=$(gh repo view "$SPEC_REPO" --json defaultBranchRef --jq .defaultBranchRef.name)
gh api -X PUT "repos/${SPEC_REPO}/branches/${DEFAULT_BRANCH}/protection" \
  -F required_status_checks= \
  -F allow_force_pushes=false \
  -F allow_deletions=false \
  -F required_linear_history=true 2>/dev/null || true

# Label seeding via yq + jq over .github/labels.yml — see full script in transcript line 63
```

`chmod +x bin/new-spec-repo`

### t9c — `bin/link-spec-repo`

```bash
#!/usr/bin/env bash
# Run inside a target implementation repo.
# Usage: link-spec-repo <owner/name-of-spec-repo>
set -euo pipefail
SPEC_REPO="${1:?owner/name spec repo required}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p docs/agents bin
cat > docs/agents/issue-tracker.md <<'EOF'
# Issue tracker

Issues for this repository are tracked on **GitHub**.

- **CLI:** `gh issue create`, `gh issue view`, `gh issue list`
- **Remote:** (see `git remote get-url origin`)

## Spec repository (parent PRDs)

- **SPEC_REPO:** __SPEC_REPO__

`bin/feature-context` reads **SPEC_REPO** from this file.
EOF
sed -i.bak "s|__SPEC_REPO__|${SPEC_REPO}|g" docs/agents/issue-tracker.md && rm -f docs/agents/issue-tracker.md.bak

if [[ ! -f bin/feature-context ]]; then
  install -m0755 "${ROOT}/templates/bin/feature-context" bin/feature-context
fi

grep -q '^tmp/' .gitignore 2>/dev/null || printf '\n# OpenCode scratch\ntmp/\n.research/\n.qa/\n.plan/*.completed.md\n' >> .gitignore
```

### t10 — `templates/bin/feature-context` (spec-repo-aware; + prototype block)

```bash
#!/usr/bin/env bash
# Hydrate tmp/feature-context.md from GitHub issue + parent PRD (spec repo from docs/agents/issue-tracker.md).
set -euo pipefail
ISSUE="${1:?issue number required}"
OUT="tmp/feature-context.md"
mkdir -p tmp

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
ISSUE_JSON=$(gh issue view "$ISSUE" --repo "$REPO" --json title,body,labels,url,number)

SPEC_REPO=""
if [[ -f docs/agents/issue-tracker.md ]]; then
  SPEC_REPO=$(grep -E '^[[:space:]]*(SPEC_REPO|spec_repo):' docs/agents/issue-tracker.md | head -1 | sed -E 's/^[^:]*:[[:space:]]*//' | tr -d '\r' || true)
fi

SLUG=$(echo "$ISSUE_JSON" | jq -r '.labels[].name' | grep '^feature:' | head -1 | cut -d: -f2- || true)
[[ -z "$SLUG" ]] && SLUG="unknown"

PARENT_URL=$(echo "$ISSUE_JSON" | jq -r '.body' | grep -oE 'https://github.com/[^/]+/[^/]+/issues/[0-9]+' | head -1 || true)

{
  echo "# Feature context: ${SLUG} (${REPO}#${ISSUE})"
  echo "## This issue"
  echo "$ISSUE_JSON" | jq -r '"Title: \(.title)\nURL: \(.url)\n\n\(.body)"'
  if [[ -n "$PARENT_URL" && -n "$SPEC_REPO" ]]; then
    echo "## Parent PRD issue"
    gh issue view "$PARENT_URL" --json title,body,url -r '.title,.url,.body' 2>/dev/null || true
    PRD_PATH="docs/prd/${SLUG}.md"
    echo "## PRD file (${SPEC_REPO} ${PRD_PATH})"
    gh api "repos/${SPEC_REPO}/contents/${PRD_PATH}" --jq .content 2>/dev/null | base64 -d || echo "_Could not fetch PRD._"
    echo
    PROTOTYPE_README="docs/prototypes/${SLUG}/README.md"
    echo "## Prototype reference (${SPEC_REPO} docs/prototypes/${SLUG}/)"
    if proto=$(gh api "repos/${SPEC_REPO}/contents/${PROTOTYPE_README}" --jq .content 2>/dev/null); then
      echo "$proto" | base64 -d
      echo "_Prototype files live in the spec repo. Reference only — do not copy assets into impl repos._"
    else
      echo "_No prototype README for ${SLUG}._"
    fi
    echo
  fi
  echo "## Local CONTEXT.md"
  [[ -f CONTEXT.md ]] && cat CONTEXT.md || echo "_No CONTEXT.md at repo root._"
} > "$OUT"

echo "Wrote $OUT"
```

### t11 — `templates/.github/ISSUE_TEMPLATE/child-feature.yml`

```yaml
name: Child Feature
description: A slice of a parent PRD, scoped to this repo
title: "[<feature-slug>] <slice summary>"
labels: ["category:feature", "state:needs-triage"]
body:
  - type: input
    id: parent
    attributes:
      label: Parent issue
      description: Link to owner/spec-repo#NNN
    validations:
      required: true
  - type: input
    id: feature_label
    attributes:
      label: Feature label
      placeholder: feature:billing-portal-v2
    validations:
      required: true
  - type: textarea
    id: scope
    attributes:
      label: Scope in this repo
    validations:
      required: true
  - type: textarea
    id: acceptance
    attributes:
      label: Acceptance criteria (slice)
    validations:
      required: true
  - type: dropdown
    id: mode
    attributes:
      label: Mode
      options:
        - mode:afk
        - mode:hitl
    validations:
      required: true
```

### t9a — `templates/spec-repo/.github/labels.yml` (excerpt)

```yaml
- name: state:ready-for-agent
  color: 0e8a16
  description: Triaged; agent may pick up (AFK-capable)
- name: mode:afk
  color: c2e0c6
  description: Safe for autonomous execution end-to-end
- name: mode:hitl
  color: e99695
  description: Human-in-the-loop
- name: prd
  color: 8a2be2
  description: Parent PRD issue
```

Full file + `sync-labels.yml`, `prd-parent.yml`, `research.yml` — in transcript line 59 or `~/Downloads/opencode_onboarding_supplement.md` §1.3–1.5.

### t9a — Prototypes scaffold (same session)

```text
templates/spec-repo/docs/prototypes/_template/README.md
templates/spec-repo/docs/prototypes/_template/assets/.gitkeep
templates/spec-repo/docs/prototypes/_template/screenshots/.gitkeep
templates/spec-repo/docs/prototypes/.gitkeep
```

**`templates/spec-repo/bin/new-prd`** — after creating `docs/prd/<slug>.md`, also:

```bash
mkdir -p "$ROOT/docs/prototypes/${SLUG}"
cp "$ROOT/docs/prototypes/_template/README.md" "$ROOT/docs/prototypes/${SLUG}/README.md"  # if template exists
```

### t4 — `skills/setup-skills/SKILL.md` §4b copy table

| Source (config repo) | Destination (target repo) |
| --- | --- |
| `skills/setup-skills/templates/issue-tracker.md` | `docs/agents/issue-tracker.md` (set `SPEC_REPO:`) |
| `skills/setup-skills/templates/triage-labels.md` | `docs/agents/triage-labels.md` |
| `skills/setup-skills/templates/domain.md` | `docs/agents/domain.md` |
| `skills/setup-skills/templates/CONTEXT.md` | `CONTEXT.md` if missing |
| `skills/setup-skills/templates/LANGUAGE.md` | `LANGUAGE.md` if missing |
| `templates/bin/feature-context` | `bin/feature-context` (`chmod +x`) |
| `templates/.github/ISSUE_TEMPLATE/child-feature.yml` | `.github/ISSUE_TEMPLATE/child-feature.yml` |

### t12 — `ocx.jsonc` (session population)

```jsonc
{
  "$schema": "https://ocx.kdco.dev/schemas/ocx.json",
  "registries": {
    "skills": {
      "to-prd": {
        "description": "PRD authoring + GitHub issue publish",
        "defaultModel": "openrouter/deepseek/deepseek-v4-flash"
      },
      "triage": {
        "description": "Issue state machine + gh batch helpers",
        "defaultModel": "openrouter/deepseek/deepseek-v4-flash"
      },
      "research": {
        "description": "Cached .research/<slug>.md pre-planning",
        "defaultModel": "openrouter/deepseek/deepseek-v4-flash"
      },
      "improve-codebase-architecture": {
        "description": "Deepening findings doc via LANGUAGE.md",
        "defaultModel": "openrouter/deepseek/deepseek-v4-pro"
      },
      "fanout-issues": {
        "description": "Spec-repo cross-repo child issue fanout",
        "defaultModel": "openrouter/deepseek/deepseek-v4-flash"
      }
    }
  }
}
```

### t12 — `dcp.jsonc` (session population)

```jsonc
{
  "$schema": "https://raw.githubusercontent.com/Opencode-DCP/opencode-dynamic-context-pruning/master/dcp.schema.json",
  "retention": {
    "maxToolCallTurns": 50,
    "dropRedundantFileReads": true,
    "preserveSubstrings": ["scribe", ".plan/", "SCRIBE_", "verifier", "VERIFIER_"]
  }
}
```

### t12 — `agents/architect.md` skill allowlist (session)

```yaml
permission:
  skill: {
    "architect-plan": "allow",
    "architect-review": "allow",
    "grill-me": "allow",
    "handoff": "allow",
    "to-issues": "allow",
    "to-prd": "allow",
    "triage": "allow",
    "research": "allow",
    "improve-codebase-architecture": "allow",
    "zoom-out": "allow",
    "caveman": "allow",
    "setup-skills": "allow"
  }
```

Add skill routing bullets for **To PRD**, **Triage**, **Research**, **Improve architecture** (transcript lines 80–81).

### Root `.gitignore` (session)

```gitignore
# OpenCode scratch
tmp/
.qa/
.plan/*.completed.md
```

(`.research/` was briefly added then removed in session — keep per your policy.)

### Reference — upgrade spec `check-plan.sh` (original spec used slug arg)

The archived upgrade plan used `PLAN=".plan/${SLUG}.md"`; **this session** standardized on **artifact path** as the sole argument (works for `feature.<slug>.md`, `debug.<slug>.md`, etc.).

---

## Quick reference: commands

```bash
# Config repo validation
cd ~/.config/opencode && bash scripts/validate-opencode-config.sh

# New app spec (from anywhere, gh authed)
~/.config/opencode/bin/new-spec-repo mycelia-tree mycelia-tree-api mycelia-tree-web

# Wire existing impl repo
cd ~/code/mycelia-tree/mycelia-tree-api
~/.config/opencode/bin/link-spec-repo roborew/mycelia-tree-spec

# Session context in impl repo
bin/feature-context 42
```

---

*End of implementation record — 2026-05-16.*
