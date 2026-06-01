# 2026-05-19 — Spec-Central Stack Workflow: Full Implementation Record

**Session scope:** Implement the **Spec-central vertical stack workflow** plan (`spec-central_stack_workflow_21fd8d39`): unify shell bootstrap into `bin/setup-project`, add spec-coordinated OpenCode skills and agents, make **GitHub issues** the execution source of truth after fanout (not local `.plan/issue.*`), extend orchestrate for `stages[]` on issues, and validate on the **blocshed** stack.

**Status:** All plan todos marked **completed** in chat. **Verify on disk** before relying on paths below — the checked-out `~/.config/opencode` tree at doc-write time may not include `bin/`, `templates/`, or several skills if a later refactor or branch removed them; recover from git history or re-sync from a machine where the session edits were saved.

**Chat transcript:** [Spec-central stack workflow](e4851f6f-4658-4c8b-bb24-e76b4db7c7b5)

**Plan file (do not edit):** `~/.cursor/plans/spec-central_stack_workflow_21fd8d39.plan.md` (uploaded copy also under `.cursor/projects/.../uploads/`)

---

## Executive summary

| Area | Outcome |
| --- | --- |
| Shell bootstrap | Single entry **`~/.config/opencode/bin/setup-project`**; internals under **`bin/stack/`**; deprecated shims for `new-spec-repo`, `link-spec-repo`, `upgrade-spec-repo` |
| Layout | Parent folder (`~/code/APP/`) is **container only** — no git root or agent files at parent; siblings `APP-spec`, `APP-api`, `APP-web`, … |
| OpenCode bootstrap | **`setup-project`** skill in **spec repo** only; **`stack-bootstrap`** subagent copies impl templates |
| Execution SOT | After `bin/fanout`, **GitHub child issues** hold coarse tasks; **`issue-expand`** adds TDD **`stages[]`** in `opencode-task-json` before orchestrate |
| Orchestrate | **`orchestrate-execution`** runs **stage loop** when `opencode_meta.stages` present; **`developer`** accepts `execution_mode: github_issue_stage` |
| Close-out | **`feature-complete`** skill in spec repo rolls up cross-repo delivery and closes spec parent issue |
| Docs | `README.md`, `docs/RUNBOOK.md`, `docs/plan-artifact-schema.md`, `templates/spec-repo/README.md` updated |
| blocshed run | Shell `setup-project --keep-branch` **succeeded**; registry **TBD** stubs expected until architect skill pass |
| Permission fix | Architect bash allowlist extended for `git remote get-url origin` (and related read-only git/gh) |

---

## Problem statement (why this work happened)

1. **Three shell scripts** (`new-spec-repo`, `link-spec-repo`, `upgrade-spec-repo`) for one mental model — “make this PROJECT folder ready.”
2. **Two execution paths** — legacy local `.plan/feature.<slug>.md` vs issue-backed fanout — without a clear front door or shared stage schema on issues.
3. **Per-repo `setup-skills`** forced `cd` into every implementation repo; spec repo should coordinate the whole stack in one session.
4. **Orchestrate** could not run TDD **stages** from GitHub issue bodies when fanout only produced flat acceptance lists.

---

## Target architecture (final)

```text
~/code/APP/                    # Container ONLY (no tracked files here)
├── APP-spec/                  # PRDs, registry, fanout, product CONTEXT
├── APP-web/                   # Implementation repo(s)
├── APP-api/
└── APP-<surface>/
```

| Layer | Location | Responsibility |
| --- | --- | --- |
| Product spec | `APP-spec/docs/prd/<slug>.md` | User stories, `tickets:` definitions, approval |
| Coarse tasks | GitHub in each impl repo | One issue per PRD ticket after **`bin/fanout`** |
| Detailed plan | **Same GitHub issues** | `issue-expand`: Implementation plan + `stages[]` in fenced `opencode-task-json` |
| Session cache | `tmp/feature-context.md` | Ephemeral; **not** source of truth |
| Legacy | `.plan/feature.<slug>.md` | Option B only; migration path documented in `setup-project` skill |

---

## Production workflow (operator)

```text
# Step 1 — Shell (project parent, new OR existing stack)
cd ~/code/APP
export GH_ORG=owner
~/.config/opencode/bin/setup-project
# optional: --keep-branch, --check-only, --spec-only, --app, --org

# Step 2 — OpenCode in spec only
cd APP-spec && opencode
# architect: "Run setup-project" (or front-door option for stack setup)
#   → interview, fill docs/agents/repos.md, Task stack-bootstrap per impl repo

# Feature delivery (issue-backed path)
spec:  grill-me → to-prd → approve → bin/fanout <slug>
impl:  architect → issue-expand (feature:<slug>) → orchestrate (GitHub backlog B)
close: spec architect → feature-complete
```

**Canonical references after implementation:** `docs/RUNBOOK.md`, `docs/plan-artifact-schema.md`, `templates/spec-repo/README.md`.

---

## 1. Unified shell: `bin/setup-project`

### Entry point

- **Path:** `~/.config/opencode/bin/setup-project` (not `./bin/setup-project` inside `APP/`)
- **PATH helper:** `scripts/install-opencode-cli.sh` → `~/.local/bin`
- **Deprecation shims:** `bin/new-spec-repo`, `bin/link-spec-repo`, `bin/upgrade-spec-repo` → `exec` or delegate to `setup-project`

### CLI

```text
setup-project [options] [project-parent-dir]

  --check-only     Validate registry + PRD + impl wiring (no writes)
  --spec-only      Create/sync spec only; skip impl linking
  --keep-branch    Do not checkout develop/main in spec (stay on current branch)
  --app <slug>     Override app slug (default: lowercased parent basename)
  --org <org>      Override GH_ORG
  -h, --help
```

Default parent directory = current working directory.

### `bin/stack/` helpers (created in session)

| Script | Role |
| --- | --- |
| `common.sh` | Discovery, case-insensitive spec detection, `stack_gh_repo_from_dir`, `stack_default_app_slug` |
| `create_or_sync_spec.sh` | Create or sync spec from `templates/spec-repo`; **stdout = single absolute path only** |
| `sync_spec_tooling.sh` | Copy fanout bins/libs; run `migrate_repos_registry.py`; PRD validation |
| `sync_impl_tooling.sh` | Sync impl-side bins from templates |
| `link_impl_repo.sh` | `SPEC_REPO` in `issue-tracker.md`, `feature-context`, gitignore |
| `check_impl_wiring.sh` | Mechanical gaps for `--check-only` |
| `print_next_steps.sh` | Human completion banner |

### Mode detection

| State | Actions |
| --- | --- |
| No `APP-spec` / no `.git` | Create spec from template; discover siblings; seed labels; link impls |
| Spec exists | Sync tooling; migrate registry; validate PRDs |
| Impl siblings present | Link each (skip `*-spec` dirs) |
| Registry has `TBD` roles | Exit **3** + message to run OpenCode `setup-project` skill |

### Exit codes (shell)

| Code | Meaning |
| --- | --- |
| 0 | Full success |
| 3 | Shell work done; registry metadata still incomplete (`INCOMPLETE` / `NEXT:`) |
| 6 | PRD validation errors |
| 1+ | Hard failures (missing org, invalid paths, etc.) |

---

## 2. OpenCode agents and skills

### New agent: `stack-bootstrap`

- **File:** `agents/stack-bootstrap.md`
- **Skill:** `skills/stack-bootstrap/SKILL.md`
- **Role:** Write-capable leaf; installs OpenCode scaffolding into **one** implementation repo when architect runs `setup-project`
- **Guardrails:** May edit target repo; deny `~/.config/opencode/**`
- **Registered in:** `opencode.json` (agent entry added in session)

### New skill: `setup-project` (spec repo only)

- **File:** `skills/setup-project/SKILL.md`
- **Phases (summary):**
  - **A** — Discover parent + siblings; read `docs/agents/repos.md`
  - **B** — Interview: `application_role`, `capabilities` per repo
  - **C** — Legacy audit: `.plan/_archive/legacy/`, `docs/_archive/legacy/` rules
  - **D** — `scribe` registry; `Task` → `stack-bootstrap` per impl; `developer` runs `setup-project --check-only` on parent
- **Bash preference:** `gh repo view --json nameWithOwner` over `git remote get-url` where possible

### New skill: `issue-expand` (implementation repo)

- **File:** `skills/issue-expand/SKILL.md`
- **Role:** Enrich fanout issues: `## Implementation plan`, `stages[]` inside fenced `opencode-task-json`
- **Handoff:** Prompt user to switch to **orchestrate** → GitHub backlog `feature:<slug>`
- **Supersedes:** Local `.plan/issue.<n>.md` approach (cancelled todo `issue-plan-skill`)

### New skill: `feature-complete` (spec repo)

- **File:** `skills/feature-complete/SKILL.md`
- **Role:** Cross-repo rollup, PR links on parent issue, close spec PRD issue after all impl repos done

### Extended: `orchestrate-execution`

- **File:** `skills/orchestrate-execution/SKILL.md`
- **Change:** When `opencode_meta.stages` present on selected GitHub issue, run **stage loop** (pick next runnable stage, dispatch `developer` with `github_issue_stage`)
- **Fallback:** Flat acceptance list when no `stages[]`

### Extended: `developer`

- **File:** `agents/developer.md`
- **New contract:** `execution_mode: github_issue_stage` with `stage_id` + one object from `opencode_meta.stages[]`

### Architect wiring (`agents/architect.md`)

**Skills added to `permission.skill`:**

- `setup-project`, `issue-expand`, `feature-complete` (plus existing planning utilities)

**Tasks added to `permission.task`:**

- `stack-bootstrap: allow`
- `developer: allow` (for `gh` / `setup-project --check-only` on parent only)

**Spec-repo front door (option 2 A/B during plan; later sessions may simplify menus — see `2026-06-01-feature-pipeline-and-architect-front-door.md`):**

- **A)** Issue-backed — `issue-expand` → orchestrate GitHub backlog
- **B)** Legacy — `grill-me` → `.plan/feature.<slug>.md` → orchestrate from file

**Bash allowlist additions (permission fix for “Permission required”):**

- `git remote get-url origin`
- `git remote -v`
- `git branch --show-current`
- `gh repo view --repo *`
- `gh issue list *`

User must **approve once**, **restart session**, or **skip** remote discovery with explicit `roborew/blocshed-spec` in prompt.

### Schema doc

- **`docs/plan-artifact-schema.md`** — `opencode-task-json` + `stages[]` fields for issue bodies

### Config registration

- **`opencode.json`** — `stack-bootstrap` agent entry
- **`ocx.jsonc`** — new skills registered (session-era; later commits may have removed central skills registry — verify)

---

## 3. Bugs fixed during this chat

| Symptom | Cause | Fix |
| --- | --- | --- |
| `bin/setup-project: no such file` from `APP/` | Script lives only in OpenCode config | Document full path; `install-opencode-cli.sh`; usage header in script |
| `invalid spec path (internal bug)` + GitHub URL in path | `gh repo create/clone` printed URL on **stdout**; parent captured logs as `SPEC_PATH` | `create_or_sync_spec.sh`: logs → stderr; only final path on stdout; parent parses last valid directory line |
| `link-spec-repo` run inside `blocshed-spec` | Case mismatch `BlocShed` vs `blocshed`; `BlocShed-spec` ≠ `blocshed-spec` | Case-insensitive `*-spec` skip; app slug = **lowercased** parent basename; remotes from `git`/`gh` per repo |
| Architect **Permission required** on `git remote get-url origin` | Read-only architect; command not on bash allowlist | Add git remote / branch + `gh repo view` patterns; skill prefers `gh repo view --json nameWithOwner` |
| `INCOMPLETE` after successful shell run | Registry stubs with `TBD` for `application_role` / `capabilities` | **Expected** until OpenCode `setup-project` skill completes interview |

---

## 4. blocshed validation (user stack)

**Parent:** `/Users/robo/05_Repos/01_PROJECTS/apps/blocshed`

**Siblings:** `blocshed-spec`, `blocshed-api`, `blocshed-web`

**GitHub:** `roborew/blocshed-spec` (remote casing may differ from folder names)

**Successful command:**

```bash
cd /Users/robo/05_Repos/01_PROJECTS/apps/blocshed
export GH_ORG=roborew
~/.config/opencode/bin/setup-project --keep-branch
```

**Observed:**

- Spec stayed on **develop**
- Labels seeded on spec, api, web
- api/web linked to spec
- `docs/agents/repos.md` updated with impl entries but **TBD** stubs → exit **3** / `INCOMPLETE` — **not a shell failure**

**Next step for user (not done in shell pass):**

```bash
cd blocshed-spec && opencode
# architect → Run setup-project
# Fill application_role and capabilities; remove TBD
```

**Validate:**

```bash
~/.config/opencode/bin/setup-project --check-only /Users/robo/05_Repos/01_PROJECTS/apps/blocshed
```

---

## 5. Plan todos — completed vs cancelled

| Todo ID | Status | Deliverable |
| --- | --- | --- |
| `unified-setup-project-bin` | **Completed** | `bin/setup-project` + `bin/stack/*` + deprecation shims |
| `stack-bootstrap-agent` | **Completed** | `agents/stack-bootstrap.md` + `skills/stack-bootstrap/SKILL.md` |
| `setup-project-skill` | **Completed** | `skills/setup-project/SKILL.md` + architect wiring |
| `legacy-plan-audit` | **Completed** | Rules in `setup-project` skill (archive paths) |
| `issue-expand-skill` | **Completed** | `skills/issue-expand/SKILL.md` |
| `orchestrate-issue-stages` | **Completed** | `skills/orchestrate-execution/SKILL.md` + `developer.md` + schema doc |
| `feature-complete-skill` | **Completed** | `skills/feature-complete/SKILL.md` |
| `docs-canonical-flow` | **Completed** | README, RUNBOOK, templates/spec-repo/README |
| `align-stack-skill` | **Cancelled** | Superseded by `setup-project` |
| `init-stack-bin` | **Cancelled** | Merged into unified bin |
| `issue-plan-skill` | **Cancelled** | Superseded by `issue-expand` |
| `orchestrate-issue-plans` | **Cancelled** | Superseded by issue `stages[]` loop |

---

## 6. Files created or modified (inventory)

### New — shell

- `bin/setup-project`
- `bin/stack/common.sh`
- `bin/stack/create_or_sync_spec.sh`
- `bin/stack/sync_spec_tooling.sh`
- `bin/stack/sync_impl_tooling.sh`
- `bin/stack/link_impl_repo.sh`
- `bin/stack/check_impl_wiring.sh`
- `bin/stack/print_next_steps.sh`

### New — agents / skills / docs

- `agents/stack-bootstrap.md`
- `skills/stack-bootstrap/SKILL.md`
- `skills/setup-project/SKILL.md`
- `skills/issue-expand/SKILL.md`
- `skills/feature-complete/SKILL.md`
- `docs/plan-artifact-schema.md`

### Modified (representative)

- `bin/new-spec-repo`, `bin/link-spec-repo`, `bin/upgrade-spec-repo` (deprecation)
- `agents/architect.md` (skills, tasks, bash allowlist, front-door / routing)
- `agents/developer.md` (`github_issue_stage`)
- `skills/orchestrate-execution/SKILL.md`
- `opencode.json`, `ocx.jsonc`
- `README.md`, `docs/RUNBOOK.md`, `templates/spec-repo/README.md`
- `scripts/install-opencode-cli.sh` (PATH install; if added in session)

### Unchanged shared libs (used by stack scripts)

- `bin/lib/migrate_repos_registry.py`
- `bin/lib/read_spec_repo.sh`
- `templates/spec-repo/**` (fanout, validators — pre-existing; synced by `sync_spec_tooling.sh`)

---

## 7. Operator cheat sheet

| Goal | Where | Action |
| --- | --- | --- |
| Bootstrap / refresh stack wiring | `APP/` parent | `GH_ORG=owner ~/.config/opencode/bin/setup-project` |
| Check wiring only | `APP/` parent | `setup-project --check-only /path/to/APP` |
| Fill registry roles | `APP-spec` + architect | Run **`setup-project`** skill |
| New feature (issue-backed) | spec → impl | PRD → fanout → impl **issue-expand** → orchestrate backlog |
| Close feature cross-repo | `APP-spec` + architect | **`feature-complete`** |
| Legacy single-repo feature | impl + architect option B | grill-me → `.plan` → orchestrate file picker |

---

## 8. Follow-up checklist

- [ ] Confirm all paths in §6 exist on disk in your `~/.config/opencode` checkout (restore from git if missing)
- [ ] Complete architect **`setup-project`** in `blocshed-spec`; re-run `--check-only` until registry complete
- [ ] New architect session after permission changes if `git remote` still prompts
- [ ] Commit/push OpenCode config when satisfied
- [ ] If `link-spec-repo` was mistakenly run inside spec earlier, verify spec repo has no impl-only artifacts

---

## 9. Related TO REVIEW docs (same folder, date sort)

Later sessions extended or fixed overlapping areas — read together:

| File | Relationship |
| --- | --- |
| `2026-06-01-setup-project-shell-bootstrap.md` | Re-run UX, gh stdout, `NEXT:` messaging, end-of-run commit |
| `2026-06-01-setup-project-workflow-and-deepseek-bash-fixes.md` | Architect fizzling, `INCOMPLETE` vs `OK`, bash `2>&1` deny fix |
| `2026-06-01-feature-pipeline-and-architect-front-door.md` | PRD parser, registry YAML, architect menus, blocshed gates |
| `2026-06-01-spec-repo-markdown-parser.md` | `SPEC_REPO` parsing in impl `issue-tracker.md` |
| `2026-05-20-setup-project-empty-targets-fix.md` | Empty `TARGETS` / spec-only bootstrap |
| `2026-05-20-setup-project-cross-stack-scope.md` | Parent-folder scoping |
| `2026-06-01-issue-backed-workflow-orchestrate-handoff.md` | Why orchestrate handoff after issue-expand |

---

*Document produced from Cursor chat implementing `spec-central_stack_workflow_21fd8d39` (session completed 2026-05-19). Filename prefix `2026-05-19-` sorts with other reviews from that day; use ISO date prefixes for new entries.*
