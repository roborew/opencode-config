# 2026-06-01 — New Project Initialization Setup Guide

**Session scope:** Produce a short, operator-facing setup guide for initializing new projects under the OpenCode agent orchestration config. No application code or bootstrap scripts were changed in this session.

**Status:** Finalized in chat (**2026-06-01** — date the setup guide deliverable completed, not the calendar day of any later TO REVIEW edits). Deliverable was documentation only (chat response + this `TO REVIEW` record). A dedicated file under `docs/guides/` was **not** added to the repo unless promoted separately.

**Filename convention:** `YYYY-MM-DD-<slug>.md` where the date prefix is **session work-completion date** (same as the H1), so files sort chronologically alongside other `TO REVIEW` notes.

**Related sessions (same date, on disk):** Shell bootstrap and `setup-project` fixes are documented in [`2026-06-01-setup-project-shell-bootstrap.md`](2026-06-01-setup-project-shell-bootstrap.md). Feature pipeline and architect front door: [`2026-06-01-feature-pipeline-and-architect-front-door.md`](2026-06-01-feature-pipeline-and-architect-front-door.md).

---

## Executive summary

| Area | Outcome |
| --- | --- |
| User request | Short setup guide for new project initialization |
| Repo changes | None in the first turn; this `TO REVIEW` markdown added on request |
| Primary deliverable | Five-step operator guide (prerequisites → repo shape → per-repo wiring → optional spec repo → daily workflow) |
| Sources synthesized | `README.md` Setup section (at session time), `skills/setup-skills/SKILL.md`, `docs/RUNBOOK.md`, `docs/upgrade-spec/onboarding-supplement.md`, `bin/new-spec-repo` references |

---

## What was implemented in this chat

### 1. Research pass

Before writing the guide, the following areas of the OpenCode config repo were reviewed:

| Source | Purpose |
| --- | --- |
| `README.md` | Canonical setup steps: config dir, `setup-skills`, optional `new-spec-repo` multi-repo layout |
| `skills/setup-skills/SKILL.md` | Per-repo scaffold: `docs/agents/*`, `CONTEXT.md`, triage labels, `AGENTS.md` / `README.md` block |
| `docs/RUNBOOK.md` | Post-bootstrap workflow: architect → orchestrate, spec vs implementation paths |
| `docs/upgrade-spec/onboarding-supplement.md` | Deeper manual Git/GitHub checklist and initiation ceremony (Part 1 & 2) |
| `templates/spec-repo/` | Spec repo templates referenced by bootstrap tooling |
| `bin/new-spec-repo` | Parent-folder discovery of sibling impl repos and `<app>-spec` creation |

### 2. Setup guide (final chat deliverable)

The guide below is the complete text produced and agreed in chat. It is preserved here so it can be promoted to `docs/guides/` or merged into README/RUNBOOK later.

---

## New project initialization (OpenCode)

### 0. Prerequisites

- **OpenCode** must load this config checkout: symlink to `~/.config/opencode`, or set `OPENCODE_CONFIG_DIR` to this directory so `opencode.json`, agents, skills, and rules load.
- **GitHub CLI** (`gh`) authenticated when using Issues, spec-repo bootstrap, or fanout workflows.

### 1. Pick your shape

| You are starting… | Do this first |
| --- | --- |
| **One implementation repo** | Create or clone the repo, then go to step 2. |
| **Spec repo + several impl repos** (`APP-web`, `APP-api`, …) | Create implementation repos on GitHub and clone them as **siblings** under one parent folder (e.g. `~/code/APP/`). Then go to step 3. |

**Repo naming:** Prefer surface or capability names (`<app>-web`, `<app>-mobile`, `<app>-api`) over vague “frontend” only, so names stay accurate as stacks evolve.

### 2. Wire each application repo (once per repo)

1. Add **`CONTEXT.md`** and **`opencode.md`** — start from [`docs/templates/opencode.md.template`](../docs/templates/opencode.md.template) in this config repo.
2. Run **`setup-skills`** once (via **architect** when that skill is enabled). It scaffolds:
   - `docs/agents/issue-tracker.md`
   - `docs/agents/triage-labels.md`
   - `docs/agents/domain.md`
   - An **`## Agent skills`** block in **`AGENTS.md`** or **`README.md`**
   - **`LANGUAGE.md`** when missing (optional scaffold)
3. **`setup-skills`** is prompt-driven: explore remotes, confirm issue tracker + label scheme + domain layout with the operator, then persist via **`scribe`**.

**Canonical triage labels** (map to repo labels if different):

| Role | Default string |
| --- | --- |
| Maintainer must evaluate | `needs-triage` |
| Waiting on reporter | `needs-info` |
| AFK agent can pick up | `ready-for-agent` |
| Needs human implementation | `ready-for-human` |
| Won't fix | `wontfix` |

**Domain layout choices:**

- **Single-context** — one `CONTEXT.md` at repo root + `docs/adr/`
- **Multi-context** — `CONTEXT-MAP.md` at root pointing to per-context `CONTEXT.md` and optional per-context ADRs

### 3. Optional: create the spec repo from the parent folder

From the **parent directory** that contains sibling clones (e.g. `APP-web`, `APP-api`):

```bash
export GH_ORG=YOUR_ORG   # GitHub user or org — owner in owner/repo, not the app slug
mkdir -p ~/code/APP && cd ~/code/APP
gh repo clone "$GH_ORG/APP-web"
gh repo clone "$GH_ORG/APP-api"
~/.config/opencode/bin/new-spec-repo
```

**Behavior (no arguments):**

- Uses the **current folder name** as the app slug
- Discovers sibling git repos under the parent
- Creates or syncs **`<app>-spec`**
- Updates **`docs/agents/repos.md`** in the spec repo
- Runs **`link-spec-repo`** inside each local implementation repo

**Constraints:**

- Implementation repos **must exist locally** before `new-spec-repo` (the script creates only **`<app>-spec`**).
- Explicit targets when discovery is insufficient: `new-spec-repo APP APP-web APP-api …`
- After adding, renaming, or removing impl repo folders, re-run from the parent to refresh **`repos.md`** and relink. Existing PRDs, ADRs, and prototypes in the spec repo are left unchanged.

**Optional:** `gh secret set LABEL_SYNC_PAT` on the spec repo if using [label sync](../templates/spec-repo/.github/workflows/sync-labels.yml).

### 4. After bootstrap — daily workflow

| Step | Where | Action |
| --- | --- | --- |
| Plan | Spec or impl repo | **`architect`** — PRD, feature plan, debug/refactor, review, or repo setup |
| Execute | Impl repo | **`orchestrate`** — GitHub `feature:<slug>` backlog (default after fanout) or local **`.plan/*.md`** |
| Spec sign-off | Spec repo (Mode F) | Set **`SPEC_REPO`** to local spec path when architect should compare impl work to **`docs/prd/<slug>.md`** |

**Spec-driven feature path:**

```text
grill-me → to-prd → human approves → bin/fanout <slug> → orchestrate (feature:<slug>) → architect Mode F
```

**Local plan path (no fanout):**

```text
bin/feature-context <issue> → architect → .plan/<type>.<slug>.md → orchestrate
```

**Canonical operational detail:** [`docs/RUNBOOK.md`](../docs/RUNBOOK.md)

**Deeper one-time Git/GitHub checklist** (branch protection, `.gitignore` for agent scratch dirs, label seeding): [`docs/upgrade-spec/onboarding-supplement.md`](../docs/upgrade-spec/onboarding-supplement.md) when present in the checkout.

### 5. Agent scratch directories (recommended)

Add to each target repo `.gitignore` when adopting OpenCode (see onboarding supplement):

```gitignore
# OpenCode agent scratch
tmp/
.research/
.qa/
.plan/*.completed.md
```

- `tmp/feature-context.md` — hydrated per-run from GitHub; typically gitignored
- `.plan/<slug>.md` — committed while active; `.completed.md` suffix ignored

---

## Files touched in this session

| File | Change |
| --- | --- |
| `TO REVIEW/2026-06-01-new-project-initialization-setup-guide.md` | **Created** — this document |
| All other paths | **Unchanged** in this session |

---

## Gaps and promotion options

The chat deliverable was intentionally **short**. It does not replace:

- Full manual GitHub/org setup in `docs/upgrade-spec/onboarding-supplement.md` Part 1
- `setup-project` shell bootstrap documented in sibling `TO REVIEW` files from 2026-06-01
- `docs/FEATURE-PIPELINE.md` spec-driven production workflow (if present in checkout)

**If promoting to permanent docs**, suggested targets:

1. `docs/guides/new-project-setup.md` — standalone operator guide (copy sections above)
2. `README.md` — restore a compact **Setup** subsection linking to the guide
3. `skills/setup-project/SKILL.md` — align examples with generic `APP` / `myapp` naming

---

## Verification checklist

- [ ] Confirm `~/.config/opencode` (or `OPENCODE_CONFIG_DIR`) points at this checkout
- [ ] `gh auth status` succeeds for org/user that owns target repos
- [ ] Single-repo path: `setup-skills` run once; `docs/agents/*` and `CONTEXT.md` exist
- [ ] Multi-repo path: sibling impl clones + `new-spec-repo` (or `setup-project` if using stack scripts from sibling sessions) completes; `SPEC_REPO` set in impl repos
- [ ] Architect → orchestrate handoff works on a smoke feature or `.plan` file per `docs/RUNBOOK.md`

---

## Session metadata

- **Work-completion date (filename + title):** 2026-06-01
- **Trigger:** User request — “short setup guide for new project initialization”
- **Follow-up:** User request — record finalized work in `TO REVIEW/` with date-prefixed **filename** for chronological sorting alongside other session notes (date = when the setup guide was finalized in this chat, not “today” when the TO REVIEW file was authored if those differ)
