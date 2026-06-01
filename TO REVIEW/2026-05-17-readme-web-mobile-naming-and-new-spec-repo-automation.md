# 2026-05-17 — README Refactor, Web/Mobile Repo Naming, and `new-spec-repo` Sync Automation

**Session scope:** Rename implementation-repo guidance away from legacy “frontend” toward surface-based names (`<app>-web`, `<app>-mobile`); restructure `README.md` so setup and daily use come first; automate multi-repo bootstrap/sync from the parent project folder via `bin/new-spec-repo`; fix sync bugs discovered on a real `mycelia-tree` run; confirm that reruns only affect routing/configuration, not spec product content.

**Status:** Implemented and finalized in this chat (2026-05-17). **Verify on disk before merge** — this repo has since evolved (e.g. `README.md` may have been shortened again; `bin/new-spec-repo` may be a shim to `bin/setup-project` / `bin/stack/create_or_sync_spec.sh`). Search for the behaviors below in the active entrypoint if paths differ.

**Related sessions (later dates, on disk):**

- [`2026-05-18-new-spec-repo-git-flow-main-develop.md`](2026-05-18-new-spec-repo-git-flow-main-develop.md) — `main` / `develop` branch policy for spec sync (follow-up session).
- [`2026-06-01-new-spec-repo-spec-repo-change-expectations.md`](2026-06-01-new-spec-repo-spec-repo-change-expectations.md) — when reruns produce commits vs “already up to date”.
- [`2026-06-01-new-project-initialization-setup-guide.md`](2026-06-01-new-project-initialization-setup-guide.md) — operator setup guide synthesized from README at session time.
- [`2026-05-19-spec-central-stack-workflow-implementation.md`](2026-05-19-spec-central-stack-workflow-implementation.md) — later consolidation into `setup-project` (may supersede direct `new-spec-repo` usage).

---

## Executive summary

| Area | Outcome |
| --- | --- |
| Repo naming | Prefer **`<app>-web`**, **`<app>-mobile`**, **`<app>-api`** over **`frontend`** / **`APP-frontend`** in README, templates, upgrade docs, and planning prose |
| README | Setup + daily use moved to the top; large mermaid blocks and duplicate sections removed; one-command parent-folder bootstrap documented |
| `new-spec-repo` | **Create-or-sync** (no longer abort if spec repo exists); auto-discover sibling git folders; infer app slug from parent folder name; auto-run **`link-spec-repo`** in each impl repo |
| Sync fixes | Push **`HEAD`** (not hardcoded `main`); switch existing spec clone to GitHub **default branch** before rewriting routing; valid JSON for branch-protection API |
| Safety | Reruns replace only **`docs/agents/repos.md`** routing list + impl-repo wiring; PRDs/ADRs/prototypes untouched; refuse sync if spec repo has uncommitted changes |
| Agent names | **`frontend-dev`** execution agent **unchanged** — it means UI work, not a repo name |

---

## 1. Web / mobile repo naming (not “frontend”)

### Problem

“Frontend” reads as “the UI that renders the web” and does not fit native mobile or multi-surface products. Repo names should describe **surface or capability**.

### Convention adopted

| Prefer | Avoid (legacy) |
| --- | --- |
| `<app>-web` | `<app>-frontend`, `frontend` |
| `<app>-mobile` | generic “frontend” for native clients |
| `<app>-api`, `<app>-worker`, etc. | — |

**Note:** The **`frontend-dev`** subagent name was **not** renamed. It still dispatches UI/design stages in plans and GitHub issues.

### Files updated in this session

| File | Change |
| --- | --- |
| `README.md` | Bootstrap examples use `APP-web` / `APP-api`; naming rationale in multi-repo section |
| `bin/new-spec-repo` | Usage comment: `app-web`, `app-mobile`, `app-api` |
| `templates/spec-repo/docs/prd/_template.md` | Example ticket repo: `myorg/my-web` |
| `templates/spec-repo/.github/ISSUE_TEMPLATE/prd-parent.yml` | Placeholders: `org/web`, `org/mobile`, `org/api` |
| `docs/upgrade-spec/onboarding-supplement.md` | Example paths `roborew/web` (was `roborew/frontend`) |
| `docs/upgrade-spec/upgrade-plan.md` | YAML samples and prose use `web` / `mobile` |
| `skills/architect-plan/SKILL.md` | Multi-domain example: “API + web/mobile surfaces + infra” |
| `agents/architect.md` | Same multi-domain wording |

---

## 2. README restructure (concise, setup-first)

### Problem

Original `README.md` was long: multiple large mermaid diagrams, repeated “building from spec” / “local `.plan`” sections, and setup buried below pipeline detail.

### Target structure (as finalized in chat)

1. **Short intro** + links to RUNBOOK / capability matrix  
2. **Setup** — config dir, per-repo `setup-skills`, optional spec multi-repo (one bash block)  
3. **Daily use** — `architect` → `orchestrate`, `SPEC_REPO`, brief `.plan` path  
4. **Quick reference** table  
5. **How it works** — compact agent/permission summary  
6. **Workflow overview** — **one** small mermaid + short decision table  
7. **Design prototypes**, **Desktop/shell** — shortened tails  

### Removed or delegated to RUNBOOK

- Three large flowchart TD diagrams → one LR overview  
- Long “Which option do I choose?” table → 4-row table  
- Duplicate sections: Flow / How to operate / Building from spec / local `.plan` / ADRs / spec access  
- Standalone “Multi-repo product workflow” heading — content folded into **Setup** step 3  

### Bootstrap command (documented form)

Run from the **parent folder** that contains sibling clones (`APP-web`, `APP-api`, `APP-spec`), **not** from inside the spec repo:

```bash
export GH_ORG=OWNER
mkdir -p ~/code/APP && cd ~/code/APP
gh repo clone "$GH_ORG/APP-web"
gh repo clone "$GH_ORG/APP-api"
~/.config/opencode/bin/new-spec-repo
```

Manual per-repo `cd … && link-spec-repo …` loops were removed from README in favor of automation inside `new-spec-repo`.

---

## 3. `new-spec-repo` — create, sync, discover, link

### Problem

Original script:

- **Aborted** if GitHub spec repo already existed  
- Required explicit repo list: `new-spec-repo APP APP-web APP-api`  
- Required manual **`link-spec-repo`** in each implementation repo  
- On sync, could commit on a **feature branch** but **push `main`**, leaving changes invisible on the default branch  

### Behavior implemented in this session

#### Invocation

```bash
# From parent folder (e.g. ~/code/mycelia-tree/)
GH_ORG=roborew new-spec-repo                 # app slug = basename of cwd; targets = discovered siblings
GH_ORG=roborew new-spec-repo mycelia-tree    # explicit app slug; still auto-discover targets if none passed
GH_ORG=roborew new-spec-repo APP APP-web APP-api   # explicit targets when discovery is wrong
```

#### Target discovery

Scans sibling directories under the parent folder:

- Must contain **`.git`**
- Skips **`${APP}-spec`**
- Skips dot-directories

Assumes **local folder name = GitHub repo short name** (e.g. folder `mycelia-tree-web` → `roborew/mycelia-tree-web` when `GH_ORG=roborew`).

#### Spec repo lifecycle

| State | Action |
| --- | --- |
| Local `${APP}-spec/.git` exists | Use existing clone |
| Remote exists, no local clone | `gh repo clone` |
| Neither | `gh repo create … --clone`, copy `templates/spec-repo/` scaffold |

#### Routing file only (existing spec repos)

For **existing** spec repos, the script does **not** re-copy the full template tree. It ensures `docs/agents/` exists and **rewrites** `docs/agents/repos.md`:

```yaml
# Generated by new-spec-repo.
# This file is routing configuration; rerunning the script replaces this list.
repos:
  - name: roborew/mycelia-tree-api
    role: target
  - name: roborew/mycelia-tree-web
    role: target
```

#### Auto-link implementation repos

After updating the spec repo, for each discovered target with a local directory:

```bash
(cd "${PARENT_DIR}/${local_dir}" && "${ROOT}/bin/link-spec-repo" "${ORG}/${APP}-spec")
```

`link-spec-repo` updates `docs/agents/issue-tracker.md`, installs `bin/feature-context` if missing, appends scratch paths to `.gitignore`. It does **not** overwrite an existing `bin/feature-context`.

#### Git commit / push

- If `docs/agents/repos.md` (or other staged files) changed → commit (`chore: bootstrap …` or `chore: sync … target repos`)
- Push **`git push -u origin HEAD`** (not hardcoded `main`)

#### Existing spec repo — default branch checkout (added after `mycelia-tree` run)

Before rewriting `repos.md` on an **existing** spec clone:

1. Resolve GitHub **`defaultBranchRef`**
2. **Abort** if working tree has uncommitted changes (user must commit or stash)
3. `git fetch`, **`git switch`** default branch, **`git pull --ff-only`**
4. Then regenerate `repos.md` and commit on that branch

This prevents sync commits landing only on a local feature branch (e.g. `feature/delploy-maintenance`) while pushing `main`.

#### Branch protection

Replaced invalid `-F` form fields (GitHub API **422**) with JSON body:

```json
{
  "required_status_checks": null,
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": true
}
```

Failures are non-fatal: `(branch protection skipped — adjust permissions)`.

#### Label seeding

Unchanged: if `yq` + `jq` present, seed labels from `.github/labels.yml` into spec repo and each target listed in `repos.md`.

---

## 4. What reruns change vs leave alone

### Intended scope: configuration and routing only

| Touched on rerun | Not touched |
| --- | --- |
| `<app>-spec/docs/agents/repos.md` (full replace of routing list) | PRDs under `docs/prd/` |
| Impl repo `docs/agents/issue-tracker.md` (SPEC_REPO link) | ADRs, prototypes, changelogs, custom docs |
| Impl `.gitignore` scratch entries (if missing) | GitHub Issues / PRD content |
| Labels (idempotent `--force`) | Existing `bin/feature-context` (not overwritten) |

### When a commit happens vs not

- **Commit + push:** regenerated `repos.md` differs from last commit  
- **No commit:** `Spec repo already up to date.` — list already matches discovery  
- **Labels / link-spec-repo** may still run even with no spec commit  

### Directory / repo structure changes

Rerunning from the parent folder after rename/add/remove of sibling git clones **replaces** the spec routing list to match **current** local folders. It does **not** rename GitHub repos. If local folder name ≠ GitHub repo name, pass explicit `owner/repo` arguments.

---

## 5. Real-world validation (`mycelia-tree`)

User ran from `mycelia-tree/` parent:

```text
~/.config/opencode/bin/new-spec-repo
Using existing local spec repo mycelia-tree-spec...
[feature/delploy-maintenance c2752c5] chore: sync mycelia-tree-spec target repos
 1 file changed, 2 insertions(+), 2 deletions(-)
```

Observed:

- **`repos.md` did change** (`+2/-2`) — likely `frontend` → `web` entry update  
- Commit landed on **`feature/delploy-maintenance`**, not `main` — fixed afterward by default-branch checkout + `push HEAD`  
- Branch protection **422** — fixed with JSON API body  
- Labels seeded for `roborew/mycelia-tree-spec`, `-api`, `-web`  
- **`link-spec-repo`** ran for `mycelia-tree-api` and `mycelia-tree-web`  

User concern “nothing was changed in the spec directory” was explained as: working tree clean **on the checked-out branch**, while default/`main` on GitHub might not yet show the commit until push to the correct branch.

---

## 6. Operator FAQ (from chat)

### Where do I run `new-spec-repo`?

**Parent project folder** (e.g. `~/code/mycelia-tree/`), alongside `mycelia-tree-spec`, `mycelia-tree-web`, `mycelia-tree-api`. **Not** inside `mycelia-tree-spec`.

### I renamed a folder from `*-frontend` to `*-web`. Rerun?

**Yes.** From the parent folder:

```bash
cd ~/code/mycelia-tree
~/.config/opencode/bin/new-spec-repo
```

Updates `repos.md` and relinks impl repos. Does **not** duplicate lines — **replaces** the generated routing list.

### Do I pass repo names every time?

**No**, if local folder names match GitHub repo names and all clones are siblings. Explicit args only when discovery is wrong or repos are not cloned locally.

### Does this wipe my spec repo?

**No** — only **`docs/agents/repos.md`** is regenerated on sync (plus git metadata). Product artifacts in the spec repo stay unless you have uncommitted local edits (script refuses to sync until clean).

---

## 7. Files touched (this chat)

| Path | Role |
| --- | --- |
| `README.md` | Setup-first layout; `APP-web`; one-command bootstrap; routing-only rerun note |
| `bin/new-spec-repo` | Create-or-sync, discovery, auto-link, branch/push fixes, generated header |
| `bin/link-spec-repo` | Unchanged logic; invoked automatically by `new-spec-repo` |
| `templates/spec-repo/docs/prd/_template.md` | Example repo `myorg/my-web` |
| `templates/spec-repo/.github/ISSUE_TEMPLATE/prd-parent.yml` | `org/web`, `org/mobile`, `org/api` placeholders |
| `docs/upgrade-spec/onboarding-supplement.md` | `roborew/web` examples |
| `docs/upgrade-spec/upgrade-plan.md` | `web` / `mobile` in samples and checklists |
| `skills/architect-plan/SKILL.md` | Multi-domain wording |
| `agents/architect.md` | Multi-domain wording |

---

## 8. Verification checklist

```bash
# Syntax
bash -n bin/new-spec-repo
bash -n bin/link-spec-repo

# From a test parent folder with sibling git clones
cd ~/code/APP
~/.config/opencode/bin/new-spec-repo

# Expect:
# - docs/agents/repos.md in APP-spec lists discovered repos
# - commit on GitHub default branch (not orphan feature branch)
# - link-spec-repo output for each impl folder
# - PRDs and other spec files unchanged

# After folder rename, rerun — repos.md should reflect new names, no duplicate entries
```

---

## 9. Follow-ups (out of scope or later sessions)

| Item | Notes |
| --- | --- |
| `setup-project` consolidation | May supersede direct `new-spec-repo`; port discovery/sync/link behaviors into `bin/stack/create_or_sync_spec.sh` |
| Git-flow `main` / `develop` | See dedicated TO REVIEW doc; may overlap with default-branch checkout in this session |
| CRLF warning on `repos.md` | Environment/git `core.autocrlf` — see CRLF hardening docs in `TO REVIEW/` |
| Promote README setup section | Current `README.md` on disk may differ from session-final version; reconcile with `docs/guides/` or initialization guide |
| Rename `frontend-dev` agent | Explicitly **not** done — only repo naming guidance changed |

---

## 10. Suggested commit message (if promoting)

```text
docs(ops): web/mobile repo naming, README setup-first, new-spec-repo sync automation

Replace frontend repo examples with surface-based names; document parent-folder
bootstrap; make new-spec-repo create-or-sync with sibling discovery, auto
link-spec-repo, safe routing-only updates, and correct branch push behavior.
```
