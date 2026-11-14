---
slug: example-feature
parent_issue: ""
# Repos touched by this PRD — must be subset of docs/agents/repos.md entries
target_repos: []
# Primary: ordered implementation tickets (multiple per repo allowed).
# Each ticket becomes one GitHub child issue with labels feature:<slug>, category:feature, mode:*, state:ready-for-agent.
tickets: []
# Legacy: one slice per repo (owner/repo key). Used only if `tickets` is empty.
slices: {}
---

# PRD: <feature name>

## Problem statement

## Proposed solution

## User stories

- As <role>, I want <capability>, so that <outcome>.

## Implementation decisions

## Testing decisions

## Out of scope

## Open questions

## Linked artifacts

- Research: `.research/<slug>.md`
- Prototype: `docs/prototypes/<slug>/` (optional design artifact)
- ADRs: `docs/adr/`
- CONTEXT: `CONTEXT.md`
- Repo registry: `docs/agents/repos.md`

## Architecture confirmation

Before fanout, confirm target repos and roles match `docs/agents/repos.md`. Do not slice tickets until the human approves the registry summary for this feature.

## Tickets (frontmatter)

Define work as **`tickets`** (recommended). `opencode-run spec fanout <slug>` creates **one GitHub issue per ticket**, in dependency order, and embeds machine-readable metadata for orchestrate.

Each ticket object:

| Field | Required | Description |
|-------|----------|-------------|
| `id` | yes | Stable unique id, e.g. `api-org-model` (used in `depends_on` and rerun dedupe). |
| `repo` | yes | Full GitHub repo `owner/name` (must match `docs/agents/repos.md`). |
| `capability` | yes | One responsibility from that repo's `capabilities` list in `docs/agents/repos.md`. |
| `title` | yes | Issue title. Must be unique within the target repo for this PRD. |
| `owner` | yes | `developer`, `frontend-dev`, or `ux-dev` (should match registry `agent_owner` for the repo unless this is a shared prototype stage). |
| `mode` | no | `afk` or `hitl` → label `mode:afk` / `mode:hitl` (default `afk`). |
| `depends_on` | no | List of ticket `id` values that must be merged/closed before this ticket is runnable; fanout resolves them to **Blocked by: #n** lines. |
| `acceptance` | yes | List of product-outcome acceptance criteria strings. |
| `body` | no | Extra markdown appended under **Description** in the issue body. |

**Optional (deprecated at spec phase):** `commit_message`, `test_commands` — omit; **issue-expand** in the implementation repo discovers these from the codebase.

Example (YAML under frontmatter `tickets:`):

```yaml
tickets:
  - id: api-format-pipeline
    repo: myorg/my-api
    capability: content formatting
    title: "Formatting: archive payload normalisation"
    owner: developer
    mode: afk
    depends_on: []
    acceptance:
      - Archive payloads are normalised before storage

  - id: web-billing-archive-panel
    repo: myorg/my-web
    capability: archived content management UI
    title: "Billing UI: archived content management panel"
    owner: frontend-dev
    mode: hitl
    depends_on: [api-format-pipeline]
    acceptance:
      - Admin can list archived items from the distribution API
```

If `tickets` is empty, fanout falls back to legacy **`slices`** (one issue per `owner/repo` key).
