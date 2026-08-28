# Plan artifact schema

Execution plans live in GitHub issue bodies. **Spec-driven features** use issue bodies as the source of truth after fanout.

See [FEATURE-PIPELINE.md](FEATURE-PIPELINE.md) for the operator flow and [RUNBOOK.md](RUNBOOK.md) for agent behaviour.

---

## GitHub issue task block (`opencode-task-yaml`)

Spec **fanout** embeds a minimal fenced `opencode-task-yaml` block (routing only). **`issue-expand`** in the implementation repo adds `stages[]` and fills **Implementation planning** markdown (Context, Current state, Stage plan, Tests). This is the **execution source of truth** for spec-driven features (no parallel `.plan/issue.*` files).

### Root fields (fanout — spec phase)

| Field | Required | Purpose |
|-------|----------|---------|
| `task_id` | yes | Stable id from PRD ticket |
| `owner` | yes | `developer`, `frontend-dev`, or `ux-dev` |
| `depends_on` | no | Ticket ids (fanout → **Blocked by**) |
| `capability` | no | Registry capability |
| `stages` | no | Must be empty at fanout; added by **issue-expand** |

Product `acceptance` lives in **Requirements** markdown, not in the yaml block.

### Root fields (orchestrate — after issue-expand)

| Field | Required | Purpose |
|-------|----------|---------|
| `stages` | yes | Non-empty; see below |
| `commit_message` | per stage | In each stage entry (flat mode may use root — legacy json) |

### `stages[]` (issue-expand)

When non-empty, **orchestrate** runs one stage per loop (`execution_mode: github_issue_stage`) before marking the issue ready-for-review.

| Field | Required | Purpose |
|-------|----------|---------|
| `stage_id` | yes | e.g. `1-red`, `2-green` |
| `owner` | yes | `developer`, `frontend-dev`, or `ux-dev` |
| `objective` | yes | One stage goal |
| `files` | no | Paths to touch (from codebase discovery) |
| `acceptance` | yes | Stage acceptance strings |
| `test_commands` | yes | Commands for verifier |
| `commit_message` | yes | Subject for this stage's commit (`Refs: #n`) |

Human-readable detail lives under **## Implementation planning** (same content as a `.plan` artifact, adapted for GitHub).

### Canonical issue body sections

Parent PRD · User stories · Requirements · **Implementation planning** · **opencode-task-yaml** · Description · Blocked by

---
