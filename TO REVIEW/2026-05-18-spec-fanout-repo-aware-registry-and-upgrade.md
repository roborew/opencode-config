# 2026-05-18 — Spec fanout repo-aware registry, duplicate fixes, and upgrade script

**Session scope:** Diagnose architect mis-routing in spec mode (API repo treated as generic backend, web repo as frontend), implement repo-role registry and validation across PRD/fanout/agent skills, harden `bin/fanout` against duplicate issues, add operator upgrade path, and document operator guidance for resetting a fresh feature backlog.

**Status:** Implemented and finalized in chat. Apply to an existing spec repo with `bin/upgrade-spec-repo`; complete `docs/agents/repos.md` via architect `setup-skills` when the script reports TBD placeholders.

**Example stack referenced:** `blocshed-spec` → `roborew/blocshed-web`, `roborew/blocshed-api` (feature `downgrade-archival-recovery`).

---

## Executive summary

| Area | Outcome |
| --- | --- |
| Root cause | No durable repo topology; only `repos: []` or legacy `name`/`role: target`; architect inferred roles from repo names |
| Registry | Rich `docs/agents/repos.md` schema: `application_role`, `agent_owner`, `capabilities`, `non_goals`, etc. |
| PRD tickets | Required `capability` per ticket, aligned to registry; architecture confirmation section |
| Fanout | Idempotent skips; duplicate ticket guard; `validate_tickets.py` before create |
| Agent skills | `architect`, `to-prd`, `fanout-issues`, `setup-skills`, `to-issues` consult registry; no api/web heuristics |
| Operator tooling | `bin/upgrade-spec-repo` + `bin/lib/migrate_repos_registry.py` |
| Operator guidance | Domain (`grill-me` / `CONTEXT.md`) ≠ topology (`repos.md`); safe to close new wrong issues and re-fanout |

---

## Problem reported

### Symptom

Architect in spec mode created duplicate and mis-scoped GitHub child issues (e.g. `roborew/blocshed-web`):

- Duplicate titles (e.g. two “Billing UI: archived content management panel” — #66 / #67)
- Work assigned as if **API = backend** and **web = frontend**, whereas product intent is:
  - **API repo** — content formatting and distribution
  - **Web repo** — user-facing application (billing UI, admin, etc.)

### Why it happened

| Gap | Effect |
| --- | --- |
| `docs/agents/repos.md` was `repos: []` or legacy `name` / `role: target` only | No machine-readable “who owns what” |
| PRD tickets had `repo`, `title`, `owner` only | No `capability` / role binding |
| `grill-me` / `CONTEXT.md` are glossary-first | Good for terms, not repo topology |
| Architect defaults (e.g. “API + web” in decomposition) | Name-based backend/frontend assumption |
| `bin/fanout` had no dedupe or registry validation | Duplicates and wrong slices could publish |

**Conclusion:** Not operator fault alone — the workflow lacked a mandatory architecture registry and confirmation gate before ticket fanout.

---

## Solution design

```text
CONTEXT.md          → product vocabulary (domain terms)
docs/agents/repos.md → repo topology (which repo owns which capabilities)
docs/prd/<slug>.md  → feature intent + tickets (repo + capability)
bin/fanout          → validated, idempotent GitHub child issues
implementation repos → bin/feature-context → architect-plan → orchestrate
```

**Two layers required:**

1. **Domain** — run `grill-me` / maintain `CONTEXT.md` for words like “distribution”, “archive”, “backend”.
2. **Architecture** — fill `docs/agents/repos.md` for which repo implements which responsibilities.

---

## Changes implemented (OpenCode config repo)

### 1. Repo registry schema

| File | Change |
| --- | --- |
| `templates/spec-repo/docs/agents/repos.md` | Documented schema, example entries, consumer rules; `repos: []` placeholder |
| `skills/setup-skills/templates/repos.md` | Copy template for spec setup |

**Registry fields (per repo):**

- `repo` — `owner/name`
- `application_role` — product role (not “backend” by default)
- `agent_owner` — `developer` or `frontend-dev`
- `capabilities` — list tickets must map to
- `non_goals` — optional; fanout validation fails if ticket capability matches
- `integration_contracts`, `default_test_commands` — optional

### 2. PRD template and to-prd

| File | Change |
| --- | --- |
| `templates/spec-repo/docs/prd/_template.md` | Required `capability`; **Architecture confirmation** section; example tickets for formatting API vs web UI |
| `skills/to-prd/SKILL.md` | Architecture gate before PRD publish; read registry; no backend/frontend inference |
| `skills/to-prd/templates/prd.md` | Link to `docs/agents/repos.md` |
| `skills/to-prd/templates/prd-issue.md` | Registry summary + approval before fanout |

### 3. Fanout script hardening

| File | Change |
| --- | --- |
| `templates/spec-repo/bin/fanout` | `existing_issue_number()` — skip by exact title or `task_id` + `feature:<slug>` label |
| | Duplicate guard — fail on duplicate ticket `id` or `(repo, title)` |
| | `validate_tickets_against_registry()` before create |
| | Embed `capability` in `opencode-task-json` |
| | Legacy slices: require registry entry per repo |
| `templates/spec-repo/bin/lib/validate_tickets.py` | **New** — registry empty/unknown repo/missing capability/non_goal/owner mismatch |
| `templates/spec-repo/bin/lib/toposort_tickets.py` | Unchanged dependency; ticket order by `depends_on` |

**Exit codes (fanout):**

| Code | Meaning |
| --- | --- |
| 5 | Empty `docs/agents/repos.md` |
| 7 | Duplicate ticket ids/titles in PRD |
| 6 / 8 / 9 | Missing toposort, validate script, or legacy repo not in registry |

### 4. Agent and skill instructions

| File | Change |
| --- | --- |
| `agents/architect.md` | Spec **architecture gate**; registry before glossary; confirm with human; `setup-skills` if incomplete |
| `templates/spec-repo/skills/fanout-issues/SKILL.md` | Preconditions, validation, failure modes |
| `skills/to-issues/SKILL.md` | Duplicate guard before `gh issue create` |
| `skills/setup-skills/SKILL.md` | Step **D — Repo registry** for spec repos; scribe `repos.md`; template copy table |
| `skills/setup-skills/templates/domain.md` | Pointer: topology in `repos.md` |
| `skills/setup-skills/templates/agents-block.md` | Repo registry section |
| `templates/spec-repo/README.md` | Bootstrap + registry + fanout validation in workflow |

### 5. Line endings

| File | Change |
| --- | --- |
| `.gitattributes` | `templates/spec-repo/bin/* text eol=lf` (Bash-safe on macOS) |

### 6. Operator upgrade tooling (this session)

| File | Change |
| --- | --- |
| `bin/upgrade-spec-repo` | **New** — sync tooling into existing spec repo; migrate registry; validate PRDs |
| `bin/lib/migrate_repos_registry.py` | **New** — legacy `name`/`role: target` → new schema with TBD placeholders + inferred `agent_owner` from repo basename |
| `README.md` | Document `upgrade-spec-repo` usage |

**Note:** A follow-up session (see `TO REVIEW/2026-05-19-registry-migration-scribe-write-fixes.md`) fixed migration overwriting partially filled registries on repeated sync — treat that doc as additive if both are present in the tree.

---

## What `bin/fanout` does (operator reference)

**Purpose:** After human PRD approval, create **one GitHub child issue per PRD ticket** in each target implementation repo.

**Does not:**

- Replace architect ad-hoc `gh issue create` during planning
- Update existing issue bodies or labels
- Remove duplicate issues already on GitHub

**When issues already exist:**

- Skips create if same `feature:<slug>` label + (exact title **or** same `task_id` in body)
- Prints `Skipping existing #N on owner/repo (ticket-id)`
- Still uses skipped issue numbers for `depends_on` resolution on **new** tickets only

**When to re-run:**

- New tickets in PRD not yet on GitHub
- After closing wrong/duplicate issues with no work in flight
- **Not** a substitute for editing PRD + `feature-upgrade` on mature backlogs (see later pipeline docs)

---

## Operator procedures (from this chat)

### Upgrade an existing spec repo

```bash
~/.config/opencode/bin/upgrade-spec-repo ~/path/to/your-spec-repo
```

If incomplete (TBD in registry or PRD validation errors):

```bash
cd ~/path/to/your-spec-repo && opencode
# Architect: "Run setup-skills — complete docs/agents/repos.md for each implementation repo."
~/.config/opencode/bin/upgrade-spec-repo --check-only ~/path/to/your-spec-repo
```

### Fresh backlog after bad fanout (no real work started)

1. Complete `docs/agents/repos.md` and PRD tickets (`repo` + `capability`).
2. **Close** (do not need to delete) incorrect/duplicate child issues for `feature:<slug>`.
3. `bin/fanout <slug>` — creates only missing, validated tickets.
4. Implement via `bin/feature-context <issue>` in each target repo.

### Domain vs architecture (FAQ from chat)

| Question | Answer |
| --- | --- |
| Run domain / `grill-me`? | **Yes** — for vocabulary in `CONTEXT.md` |
| Enough on its own? | **No** — also need `docs/agents/repos.md` |
| Missed a step? | Registry confirmation was not enforced before; now it is in skills + fanout |
| Delete all issues? | **Yes if brand new** with no branches/PRs; **no** once work is attached |

---

## Files touched (this session)

```text
.gitattributes
agents/architect.md
README.md
bin/upgrade-spec-repo
bin/lib/migrate_repos_registry.py
skills/setup-skills/SKILL.md
skills/setup-skills/templates/repos.md
skills/setup-skills/templates/domain.md
skills/setup-skills/templates/agents-block.md
skills/to-issues/SKILL.md
skills/to-prd/SKILL.md
skills/to-prd/templates/prd.md
skills/to-prd/templates/prd-issue.md
templates/spec-repo/README.md
templates/spec-repo/bin/fanout
templates/spec-repo/bin/lib/validate_tickets.py
templates/spec-repo/docs/agents/repos.md
templates/spec-repo/docs/prd/_template.md
templates/spec-repo/skills/fanout-issues/SKILL.md
```

---

## Verification performed in chat

- `bash -n templates/spec-repo/bin/fanout`
- `python3 -m py_compile` on `validate_tickets.py`, `toposort_tickets.py`, `migrate_repos_registry.py`
- `validate_tickets.py` — rejects `non_goal` capability and unknown repo
- `migrate_repos_registry.py` — migrates `name`/`role: target` → new schema with TBD placeholders
- `upgrade-spec-repo` — bash syntax validated after LF normalization

---

## Related TO REVIEW documents

| Date | Document | Relationship |
| --- | --- | --- |
| 2026-05-19 | `2026-05-19-registry-migration-scribe-write-fixes.md` | Fixes migration overwrite on repeated sync; scribe Write-only for full files |
| 2026-06-01 | `2026-06-01-feature-pipeline-and-architect-front-door.md` | Canonical pipeline (`feature-upgrade`, issue-expand, architect menu) |
| 2026-06-01 | `2026-06-01-spec-repo-markdown-parser.md` | `prd_io.py` / PRD frontmatter parsing (complements fanout validation) |

---

## Open items / not in this session

- `bin/new-spec-repo` still writes legacy `name` / `role: target` in `repos.md` on sync — prefer `upgrade-spec-repo` + `setup-skills` for existing specs until new-spec-repo is aligned.
- No automatic cleanup of duplicate GitHub issues — manual close required.
- Registry and PRD fixes do not retroactively rewrite existing issue bodies.

---

## Quick reference commands

```bash
# Upgrade spec repo tooling + registry migration
~/.config/opencode/bin/upgrade-spec-repo <spec-repo-path>

# Validate only
~/.config/opencode/bin/upgrade-spec-repo --check-only <spec-repo-path>

# Publish PRD tickets to GitHub (after approval + validation)
cd <spec-repo> && bin/fanout <slug>

# Inspect feature issues across org
cd <spec-repo> && bin/status <slug>
```
