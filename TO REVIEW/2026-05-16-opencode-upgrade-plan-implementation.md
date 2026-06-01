# 2026-05-16 — OpenCode Upgrade Plan: Full Implementation Record

**Session completed:** Saturday, 2026-05-16 (per chat transcript timestamps — planning from ~15:24 through implementation, prototypes, and git-flow Q&A through ~18:56 UTC+1).

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

**Later sessions:** Orchestrate may delegate `check-plan.sh` to `developer` (`load: minimal`) for bash permission reasons — see `2026-06-01-subagent-bash-permissions-and-orchestrator-delegation.md`.

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
| `2026-06-01-spec-fanout-repo-aware-registry-and-upgrade.md` | Rich `repos.md`, `capability` on tickets, `bin/upgrade-spec-repo` |
| `2026-06-01-subagent-bash-permissions-and-orchestrator-delegation.md` | `check-plan.sh` via `developer` Task |
| `2026-06-01-feature-pipeline-and-architect-front-door.md` | Architect menus / pipeline docs |

When operating a live stack, read **this doc** for what the upgrade session built, then the **latest** dated doc for the subsystem you are changing.

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
