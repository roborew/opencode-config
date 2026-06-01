# 2026-06-01 — Spec repo `bin/fanout` tooling, templates, and prerequisites

**Session scope:** Clarify when `bin/fanout` is installed into an application spec repo, where the templates live, what filled files must look like for fanout to work, and the full command to re-run `upgrade-spec-repo` after an initial sync.

**Status:** Investigation and operator guidance finalized in chat. **No code changes were implemented or committed in this session.**

---

## Questions addressed

1. When generating a spec / PRD, should a **`bin/fanout`** script be added?
2. Why does fanout fail when spec files appear empty?
3. Where are the file templates, and what should they contain?
4. What is the full command to run **`upgrade-spec-repo`** again (operator had already run it once)?

---

## Summary

| Action | Installs `bin/fanout`? |
|--------|------------------------|
| **`new-spec-repo`** on a **brand-new** spec repo | Yes — copies entire `templates/spec-repo/` |
| **`new-spec-repo`** on an **existing** spec repo (sync only) | **No** — only updates `docs/agents/repos.md` routing list |
| **`to-prd`** / architect publishing a PRD | **No** — writes `docs/prd/<slug>.md` only |
| **`upgrade-spec-repo`** | **Yes** — installs fanout + validation helpers |

Fanout requires **three** preconditions beyond having the script on disk:

1. **`docs/agents/repos.md`** — non-empty `repos:` with `application_role`, `capabilities`, and `agent_owner` per implementation repo.
2. **`docs/prd/<slug>.md`** — `parent_issue` set to the parent PRD issue URL; **`tickets:`** populated (preferred) or legacy **`slices:`** if tickets is empty.
3. **`gh`** authenticated with access to all target repos.

`to-prd` intentionally **stops after PRD publish** and tells the operator to review before fanout. Fanout is a separate manual step (or via the `fanout-issues` skill in the spec repo).

---

## Template location (OpenCode config)

All canonical spec-repo scaffolding lives under:

```text
/Users/robo/.config/opencode/templates/spec-repo/
```

Key paths:

| Path | Purpose |
|------|---------|
| `bin/fanout` | Creates child GitHub issues from PRD frontmatter |
| `bin/lib/validate_tickets.py` | Validates tickets against registry before issue create |
| `bin/lib/toposort_tickets.py` | Orders ticket creation by `depends_on` |
| `bin/new-prd` | Scaffolds `docs/prd/<slug>.md` from `_template.md` |
| `bin/status` | Shows fan-out state for a `feature:<slug>` |
| `docs/prd/_template.md` | PRD frontmatter + body structure |
| `docs/agents/repos.md` | Full registry schema + example |
| `skills/fanout-issues/SKILL.md` | Agent skill for running fanout after human approval |

---

## What `upgrade-spec-repo` installs

Script: `/Users/robo/.config/opencode/bin/upgrade-spec-repo`

On each run (without `--check-only`), it:

- Creates dirs: `bin/lib`, `skills/fanout-issues`, `docs/agents`, `docs/prd`
- Installs executable: `bin/fanout`, `bin/lib/validate_tickets.py`, `bin/lib/toposort_tickets.py`
- Installs when present: `bin/status`, `bin/new-prd`
- Copies: `docs/prd/_template.md`, `skills/fanout-issues/SKILL.md`
- Creates `docs/agents/repos.md` from template **only if missing**
- Runs `migrate_repos_registry.py` on the registry (does not wipe PRDs or prototypes)
- Validates existing PRD `tickets:` against the registry when `yq` is available

Re-running sync is **safe**; it refreshes tooling from the OpenCode template without deleting PRD content.

---

## Full commands (operator reference)

**Sync fanout tooling again (from anywhere):**

```bash
/Users/robo/.config/opencode/bin/upgrade-spec-repo /path/to/your-app-spec
```

**Or from inside the spec repo (defaults to current directory):**

```bash
cd /path/to/your-app-spec
/Users/robo/.config/opencode/bin/upgrade-spec-repo
```

**Validate only — no file changes:**

```bash
/Users/robo/.config/opencode/bin/upgrade-spec-repo --check-only /path/to/your-app-spec
```

**Help:**

```bash
/Users/robo/.config/opencode/bin/upgrade-spec-repo --help
```

After sync, use `--check-only` to see remaining registry or ticket validation gaps before running fanout.

---

## PRD template — required frontmatter

Source: `templates/spec-repo/docs/prd/_template.md`

Empty scaffold (fanout will not create issues):

```yaml
---
slug: example-feature
parent_issue: ""
target_repos: []
tickets: []
slices: {}
---
```

Minimum for fanout to succeed:

```yaml
---
slug: my-feature
parent_issue: "https://github.com/org/spec-repo/issues/123"
target_repos:
  - myorg/my-api
  - myorg/my-web
tickets:
  - id: api-format-pipeline
    repo: myorg/my-api
    capability: content formatting          # must match repos.md capabilities
    title: "Formatting: archive payload normalisation"
    owner: developer                        # should match registry agent_owner
    mode: afk                                 # afk | hitl → mode:* label
    depends_on: []
    commit_message: "feat(api): normalise archive payloads"
    acceptance:
      - Archive payloads are normalised before storage
    test_commands:
      - go test ./internal/format/...
  - id: web-billing-archive-panel
    repo: myorg/my-web
    capability: archived content management UI
    title: "Billing UI: archived content management panel"
    owner: frontend-dev
    mode: hitl
    depends_on: [api-format-pipeline]
    commit_message: "feat(ui): archived content panel"
    acceptance:
      - Admin can list archived items from the distribution API
    test_commands:
      - pnpm test src/features/archive-panel.test.tsx
---
```

### Ticket field reference

| Field | Required | Notes |
|-------|----------|-------|
| `id` | yes | Stable id; used in `depends_on` and dedupe |
| `repo` | yes | Full `owner/name`; must exist in `docs/agents/repos.md` |
| `capability` | yes | Must match a `capabilities` entry for that repo |
| `title` | yes | Unique within target repo for this PRD |
| `owner` | yes | `developer` or `frontend-dev` |
| `mode` | no | Default `afk` |
| `depends_on` | no | List of ticket `id` values |
| `commit_message` | yes | Conventional Commit subject |
| `acceptance` | yes | List of criteria strings |
| `test_commands` | yes | Shell commands for verification |
| `body` | no | Extra markdown in issue body |

If `tickets` is empty, `bin/fanout` falls back to legacy **`slices:`** (one issue per `owner/repo` key) — but the registry must still be populated.

---

## Registry template — `docs/agents/repos.md`

Source: `templates/spec-repo/docs/agents/repos.md`

Empty registry blocks fanout:

```yaml
repos: []
```

Each repo entry must include at least:

```yaml
repos:
  - repo: myorg/my-web
    application_role: User-facing web application
    agent_owner: frontend-dev
    capabilities:
      - billing UI
      - admin surfaces
      - archived content management UI
    non_goals:
      - content formatting pipeline
    default_test_commands:
      - pnpm test

  - repo: myorg/my-api
    application_role: Content formatting and distribution service
    agent_owner: developer
    capabilities:
      - content formatting
      - distribution APIs
      - archive lifecycle backend
    non_goals:
      - web UI
    default_test_commands:
      - go test ./...
```

**Important:** `new-spec-repo` on an **existing** spec repo writes only a **minimal routing stub** (`name` + `role: target`). That is insufficient for fanout until **`setup-skills`** / scribe fills `application_role` and `capabilities`, or `upgrade-spec-repo` migrates toward the full schema.

---

## `bin/fanout` behaviour and failure modes

Run from spec repo root:

```bash
bin/fanout <slug>
```

| Condition | Result |
|-----------|--------|
| Missing `docs/prd/<slug>.md` | Exit 2 |
| Empty `parent_issue` in frontmatter | Exit 3 |
| Empty `repos:` in registry (legacy path) | Exit 5 — *"no repo entries; fill application_role and capabilities"* |
| Missing `bin/lib/toposort_tickets.py` | Exit 6 |
| Duplicate ticket ids or duplicate `(repo, title)` | Exit 7 |
| Missing `bin/lib/validate_tickets.py` | Exit 8 |
| Ticket repo/capability not in registry | Validation error from `validate_tickets.py` |

On success, each ticket becomes one GitHub issue with labels:

- `feature:<slug>`
- `state:ready-for-agent`
- `mode:afk` or `mode:hitl`
- `category:feature`

Issue bodies include fenced **`opencode-task-json`** metadata plus human-readable sections. Fanout is **idempotent**: existing issues matching title or embedded `task_id` are skipped.

---

## Canonical workflow (spec-driven features)

```text
Spec repo
─────────
1. setup-skills → fill docs/agents/repos.md
2. grill-me → clarify feature
3. to-prd → write docs/prd/<slug>.md + parent GitHub issue
4. Human review PRD, registry mapping, parent issue body
5. Set parent_issue in PRD frontmatter (if not already)
6. bin/fanout <slug>  (or fanout-issues skill after architecture gate)

Implementation repo(s)
──────────────────────
7. orchestrate → GitHub feature backlog (feature:<slug>)
8. developer / frontend-dev + verifier per child issue
9. architect Mode F sign-off vs PRD
```

Skills and docs referencing this flow:

- `skills/to-prd/SKILL.md` — halts before fanout
- `skills/fanout-issues/SKILL.md` — architecture gate + `bin/fanout`
- `skills/github-issue-run/SKILL.md` — execution after fanout
- `docs/RUNBOOK.md` — product features / PRD path
- `README.md` — `upgrade-spec-repo` and `new-spec-repo` setup

---

## Operator checklist (unblock fanout)

1. Confirm tooling: `ls -la bin/fanout bin/lib/validate_tickets.py` in spec repo.
2. If missing or stale: `/Users/robo/.config/opencode/bin/upgrade-spec-repo /path/to/spec`.
3. Fill **`docs/agents/repos.md`** (architect + `setup-skills` / scribe).
4. Ensure PRD has **`parent_issue`**, non-empty **`tickets:`**, matching **`repo`** / **`capability`**.
5. Validate: `upgrade-spec-repo --check-only /path/to/spec`.
6. Run: `bin/fanout <slug>` from spec repo root.

---

## Related documents in `TO REVIEW/`

| File | Relationship |
|------|----------------|
| `2026-05-19-registry-migration-scribe-write-fixes.md` | Registry migration behaviour during spec sync |
| `2026-06-01-issue-backed-workflow-orchestrate-handoff.md` | Post-fanout execution in implementation repos |
| `2026-05-20-setup-project-empty-targets-fix.md` | Spec repo target discovery (sibling repos) |

---

## Files referenced (OpenCode config repo)

- `bin/upgrade-spec-repo`
- `bin/new-spec-repo`
- `bin/lib/migrate_repos_registry.py`
- `templates/spec-repo/bin/fanout`
- `templates/spec-repo/docs/prd/_template.md`
- `templates/spec-repo/docs/agents/repos.md`
- `templates/spec-repo/skills/fanout-issues/SKILL.md`
- `skills/to-prd/SKILL.md`
- `README.md` (upgrade-spec-repo section)
