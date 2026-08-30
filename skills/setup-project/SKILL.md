---
name: setup-project
description: Spec-repo-only stack bootstrap — discover siblings, interview, legacy docs audit, configure all implementation repos via stack-bootstrap and scribe. Replaces per-repo setup-skills for vertical stacks.
modelTier: smart
roleReminder: "Run only in PROJECT-spec (docs/prd/ or spec layout). Never ask the user to cd into each implementation repo."
---

# Setup project (spec repo)

Orchestrate **one OpenCode session in `PROJECT-spec`** to configure the entire sibling stack under the parent folder. The parent `PROJECT/` directory must contain **no** project files — only `PROJECT-spec` and `PROJECT-*` implementation repos.

## Preconditions

- Session cwd is the **spec repo** (`docs/prd/` or `docs/agents/repos.md`).
- Sibling implementation repos exist at `../<repo-basename>` (discovered from git remotes in `docs/agents/repos.md` or directory scan).
- Shell bootstrap already ran from the **project parent** folder (e.g. `~/code/APP`), using the OpenCode config script — **not** `./bin/setup-project` inside `APP/`:

  ```bash
  export PATH="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}/bin:$PATH"
  cd ~/code/APP && setup-project
  ```

  Re-runs are **idempotent** — safe to run again; spec repo stays on current branch unless `--keep-branch` is passed explicitly.

  Optional re-check via delegated bash (same path as `skills/stack-bootstrap` uses):

  ```bash
  OC="${OPENCODE_CONFIG_DIR:-${OPENCODE_CONFIG:-$HOME/.config/opencode}}"
  "$OC/bin/setup-project" --check-only "$(dirname "$PWD")"
  ```

## Phase A — Discover scope

1. Read `docs/agents/repos.md`.
2. **Spec repo identity:** use `gh repo view --json nameWithOwner -q .nameWithOwner` (preferred — architect bash allowlist). Fallback: `git remote get-url origin` only if allowed; otherwise read `SPEC_REPO` from any impl sibling's `docs/agents/issue-tracker.md`.
3. List sibling git directories: `ls -d ../*/ 2>/dev/null` and filter those with `.git` (skip `*-spec` folders). Match registry `repo:` entries to folder names via basename (`roborew/blocshed-api` → `../blocshed-api`).
4. Do **not** run mutating git commands. For remote URLs on siblings, use registry + `gh repo view --repo owner/name --json nameWithOwner` or Task **`developer`** `load: minimal` with `git -C ../blocshed-api remote get-url origin`.

Emit a **Setup status** table per repo:

| Repo | In registry | issue-tracker | triage-labels | feature-context | child-feature.yml | opencode.md | CONTEXT.md | compose-test |
|------|-------------|---------------|---------------|-----------------|-------------------|-------------|--------------|---------------|

`compose-test` = presence of `docker-compose.test.yml` (or `compose.test.yaml`) at the repo root. Coder sessions need this as the only sanctioned test backend; missing → flag for scaffold (scribe from `templates/project-stub/docker-compose.test.yml`).

Flag orphans (local git dir not in registry) and registry entries without local clones.

## Phase B — Interview (stack-wide)

One topic at a time (same substance as **`setup-skills`**):

- Shared triage labels (`docs/agents/triage-labels.md` pattern for all repos).
- Per repo: `application_role`, `capabilities`, `non_goals`, `agent_owner`, `default_test_commands`, **`compose_test_file`** (path relative to repo root; required for orchestration).
- Product vocabulary → spec `CONTEXT.md` / `LANGUAGE.md`.

## Phase C — Legacy audit (implementation repos)

For **each** sibling implementation repo, read-only scan then propose batch actions; **human confirms** before moves.

### Audit targets

| Location | Action |
|----------|--------|
| `docs/agents/` | Merge toward template set; duplicates → `docs/_archive/legacy/` |
| `CONTEXT.md` vs spec | Impl = repo gotchas only; product glossary stays in **spec** `CONTEXT.md` |

## Phase D — Apply

1. **scribe** — update spec `docs/agents/repos.md` with full registry schema (`repo`, `application_role`, `capabilities`, `non_goals`, `agent_owner`, optional `default_test_commands`, required `compose_test_file` — relative path to `docker-compose.test.yml` / `compose.test.yaml` at the repo root). Every impl repo must have a compose test file before orchestrate can run tickets against it; scaffold from `templates/project-stub/docker-compose.test.yml` when missing.
2. **stack-bootstrap** — one Task per implementation repo (`load: full`, `local_path`, `spec_repo`, `operations: [copy_templates]`).
3. Legacy `docs/agents/*` archives — **stack-bootstrap** per confirmed move.
4. **developer** (bash) — run from spec repo:

   ```bash
   OC="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
   bash -lc "$OC/bin/setup-project --check-only $(dirname "$PWD")"
   ```

5. Report pass/fail. If exit 3: registry incomplete (`NEXT:` message — normal until interview completes). If exit 4: impl wiring gaps. If exit 6: PRD ticket validation errors.

## Done message

When check passes:

- Stack is ready for `grill-me` / `to-prd` / fanout / **issue-expand** in this spec repo (option 1 chain).
- Implementation work uses **orchestrate** per impl repo after spec handoff (not per-repo setup-skills).
- Close features with **feature-complete** in this spec repo.

## Bash (architect)

Architect runs discovery and validation shell; **stack-bootstrap** / **scribe** / **developer** Tasks handle writes.

| Allowed (examples) | Denied (architect `permission.bash`) |
|--------------------|--------------------------------------|
| `gh repo view … -q .nameWithOwner` | `rm`, `mv`, `cp`, `mkdir`, `chmod` |
| `gh issue view`, `gh issue list`, `gh pr list` | `gh issue create`, `gh issue edit`, `gh issue close`, `gh issue comment` |
| `ls -d ../*/` (no `2>/dev/null` with space before `2>`) | `git add`, `git commit`, `git push` |
| `bash -lc "$OC/bin/setup-project --check-only …"` | `echo … > file` (`* > *` deny) |
| `opencode-run spec fanout`, `yq`, `file`, `python3 "$OC/bin/project/spec/lib/*"` | Package installs (`npm install`, etc.) |

Prefer bare commands over `2>&1` / `2>/dev/null` when a deny might match spaced `* 2> *`.

## Hard rules

- Do not invoke `orchestrate` from this skill.
- Do not infer backend/frontend from repo names; use registry fields.
- **setup-skills** remains for a **single orphan repo** not in a stack — not for normal stack onboarding.
- **Never** tell the user to run `opencode-run` scripts — **you** run them when a loaded skill requires it (except **`setup-project`** once from project parent, which the human already ran).
