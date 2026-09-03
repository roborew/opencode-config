---
name: triage
description: "Issue state machine — transition GitHub issue labels per docs/agents/triage-labels.md. Batch helpers via lib/triage.sh."
modelTier: fast
roleReminder: "Read docs/agents/triage-labels.md first. Never move needs-info → ready-for-agent without human reply."
---

# Triage

Manage GitHub issue **state:** labels for the current repo (or `TRIAGE_REPO=owner/name`).

## Preconditions

- Read **`docs/agents/triage-labels.md`** (or spec-synced copy under impl repo).
- `gh` authenticated.

## State machine (summary)

| From | To | Gate |
|------|-----|------|
| `state:needs-triage` | `state:needs-info` | Missing requirements |
| `state:needs-triage` | `state:ready-for-agent` | Fully specified AFK work |
| `state:needs-triage` | `state:ready-for-human` | Requires human-only work |
| `state:needs-info` | `state:ready-for-agent` | **Human replied** with answers |
| `state:ready-for-agent` | `state:in-progress` | Agent/orchestrate picked up |
| `state:in-progress` | `state:ready-for-ticket-review` | Implementation complete (sub-PR opens) |
| `state:ready-for-ticket-review` | `state:ticket-reviewed` | Human approved the sub-PR (per-ticket) — set by develop orchestrator or coder session on "ticket reviewed" reply |
| `state:ticket-reviewed` | (merge into feature branch) | Orchestrator or coder merges sub-PR into `opencode/feat-<slug>`; ticket stays open until spec `feature-complete` |
| `state:ticket-reviewed` | `state:ready-for-feature-review` | Set by **feature coder** when it accepts the stack and opens the feature PR |
| `state:ready-for-feature-review` | `state:done` | Human "all reviewed" on the feature PR; develop orchestrator transitions every ticket |
| `state:done` (open) | issue **closed** | Spec **feature-complete** at merge only |
| any | `state:blocked` | Dependency or env blocker |
| any | `state:wontfix` | Explicit cancel |

## Hard rules

- **Never** transition `state:needs-info` → `state:ready-for-agent` without explicit human reply in the thread.
- Remove prior `state:*` label before adding a new one (use **`lib/triage.sh transition`**).
- Do not close issues as part of triage unless the user explicitly requests close in a **feature-complete** or one-off cancel flow.

## CLI helpers (you or developer run)

```bash
bash skills/triage/lib/triage.sh list-needs-triage
bash skills/triage/lib/triage.sh transition <num> state:ready-for-agent
```

Or from OpenCode config checkout:

```bash
OC="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
bash "$OC/skills/triage/lib/triage.sh" transition <num> state:ready-for-agent
```

## Reporting

After batch triage, summarize: issues touched, new states, any left in `needs-info` awaiting human input.
