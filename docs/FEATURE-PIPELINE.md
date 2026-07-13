# Feature pipeline

Spec-driven path from PRD to orchestrate-ready GitHub issues. **Agents run `bin/*`; humans run `setup-project` once, then use OpenCode menus.**

## Flow (what happens, not what you type)

| # | Where | Who does it |
|---|--------|-------------|
| 1 | spec | User + **architect**: grill-me → to-prd → approve PRD (parent issue → org project board when `GH_PROJECT` set) |
| 2 | spec | **architect** (fanout-issues): creates child issues per repo (sub-issues + `prd-task` label + board) |
| 3 | spec | **architect** (issue-expand, same session): codebase-backed plans per impl sibling, gates |
| 4 | spec | User approves issue edits → **architect** emits per-repo execution handoff(s) |
| 5 | impl | **orchestrate** (new session per repo) exhausts `feature:<slug>` queue → CodeRabbit → feature PR → impl architect handoff |
| 6 | impl | **architect** option 4 Mode F: Phase R (PR feedback) → remediation loop → Phase 1 accept (`state:done`, open) → Phase 2 docs |
| 7 | spec | **feature-complete**: rollup, merge gate, close child issues, merge PRs, close PRD parent |

### Session boundaries (recommended)

- **Planning:** one **spec** architect session — grill-me → to-prd → fanout → issue-expand → gates → handoff(s).
- **Execution:** **new** OpenCode session per impl repo → orchestrate with `feature:<slug>` (parallel OK when handoff says so).
- **Review loop:** **new** session per impl repo → **impl** architect option 4 with slug + PR URL from orchestrate (Phase R until Merge-ready).
- **Complete:** **spec** architect option 3 **feature-complete** after every impl repo reports Mode F done.

Same-session handoff is optional (`/compact` after a short table HANDOFF block); use a new session if the provider errors on tool history.

### Sign-off and ticket closure

| Label / state | Set by | Meaning |
|---------------|--------|---------|
| `state:in-progress` | orchestrate | Actively executing issue/stages |
| `state:ready-for-review` | orchestrate (verifier PASS) | Implementation done; awaiting architect |
| `state:done` | impl architect Mode F Phase 1 | Accepted; issue **stays open** until Spec merge |
| Issue **closed** on GitHub | spec **feature-complete** at merge | Ticket complete |

Orchestrate does **not** close issues or write sign-off docs. Per-issue commits happen locally during execution; do not push per issue. One **feature PR** is opened only after the queue is empty, the one-shot CodeRabbit CLI review has run, and CodeRabbit findings have been fixed locally (`feature-finish-pr.sh`). The final orchestrate response must point to **impl architect option 4 Phase R** with `impl_repo`, `impl_repo_path`, feature slug, PR URL, work completed, gates, CodeRabbit, and key findings/risks.

#### Mode F — three-phase sign-off (impl repo, default)

| Phase | What happens |
|-------|----------------|
| **R — PR feedback** | PR comments (CodeRabbit/Kilo/CI), incomplete tickets, user feedback → remediation sub-issues → orchestrate loop until Merge-ready |
| **1 — Acceptance** | `review` vs PRD/tickets; on Merge-ready → `state:done` via `mode-f-accept-issues.sh` (**issues stay open**) |
| **2 — Documentation** | Changelog required; optional guides; scribe + docs commit on feature PR → handoff to Spec |

Skill detail: [skills/architect-review/SKILL.md](../skills/architect-review/SKILL.md).

#### Feature complete — merge gate (spec repo)

| Step | What happens |
|------|----------------|
| Rollup | All impl repos: issues `state:done` (open), PRs listed |
| Merge gate | User chooses human merge or agent merge on their behalf |
| Close + merge | Close child issues; merge PRs; delete head branches (never develop/main/master) |
| PRD | Close parent + delivery record |

Skill detail: [skills/feature-complete/SKILL.md](../skills/feature-complete/SKILL.md).

#### Mode B — legacy `.plan`

After local plan execution: review → docs → **`archive_plan`** to `*.completed.md`.

#### Remediation

Phase R publishes remediation as PRD sub-issues in impl repo → **orchestrate** again (prefer new session). Issues stay open until Spec merge.

## Two execution modes

| Mode | Where | Source of truth | Architect entry |
|------|--------|-----------------|-----------------|
| **Spec / GitHub** (default) | spec + impl repos | GitHub issues with `feature:<slug>` after fanout + issue-expand | Spec option 1 (planning); impl orchestrate + impl option 4 |
| **Legacy local plan** | single impl repo | `.plan/feature.<slug>.md` | Impl repo option 1 (targeted change) |

Fanout alone is not enough for the stage loop — **issue-expand** is mandatory before orchestrate on the spec path. Orchestrate runs **orchestrate-readiness-check** at bootstrap and blocks if expansion is incomplete.

## One human shell command (stack bootstrap)

From the **project parent** (folder containing `*-spec` and impl repos):

```bash
export GH_ORG=your-github-login-or-org
cd ~/code/APP && setup-project
```

`GH_ORG` is the GitHub **owner** (`owner/repo`), not the app slug or local folder name. That syncs tooling into spec + impl repos. Everything else is OpenCode agents and skills. See [RUNBOOK.md](RUNBOOK.md) and [skills/setup-project/SKILL.md](../skills/setup-project/SKILL.md).

**Project board (optional):** Set `GH_PROJECT` in `~/.opencode-agent-env` before publish/fanout. See [GITHUB-PROJECT-BOARD.md](GITHUB-PROJECT-BOARD.md).

## Responsibility split

| Phase | Repo | Owns |
|-------|------|------|
| Requirements | spec | User stories, product acceptance, repo tickets, blockers |
| Technical planning | spec (issue-expand) | Context, stages, tests, `opencode-task-json` on GitHub issues |
| Execution | impl | orchestrate stage loop, PR |
| Review / accept / docs | impl (Mode F) | Phase R, `state:done` labels, docs on feature branch |
| Merge / close | spec (feature-complete) | Merge gate, close issues, close PRD |

## Canonical issue body

Parent PRD · User stories · Requirements · **Implementation plan** · **opencode-task-json** · Description · Blocked by

Details: [plan-artifact-schema.md](plan-artifact-schema.md).

## Internal scripts (agents only)

Central in `OPENCODE_CONFIG_DIR` — invoke via **`opencode-run`** (never copied into app repos):

| Command | Used by |
|---------|---------|
| `opencode-run --cwd <impl> impl issue-expand-bundle` | issue-expand from spec (sibling path) |
| `opencode-run impl issue-expand-bundle` | issue-expand from impl (deprecated) |
| `opencode-run impl feature-check` | issue-expand (single impl repo) |
| `opencode-run spec feature-check` | feature-upgrade, fanout-issues, issue-expand (all repos) |
| `opencode-run impl orchestrate-readiness-check` | issue-expand, orchestrate bootstrap |
| `opencode-run impl feature-context` | issue-expand, orchestrate |
| `opencode-run spec fanout` | fanout-issues (spec) |
| `resolve_impl_path.sh` | issue-expand (spec → sibling abs path) |

## See also

- [RUNBOOK.md](RUNBOOK.md)
- [skills/issue-expand/SKILL.md](../skills/issue-expand/SKILL.md)
- [skills/setup-project/SKILL.md](../skills/setup-project/SKILL.md)
- [adr/0006-close-at-merge-and-phase-r.md](adr/0006-close-at-merge-and-phase-r.md)
