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
| `state:in-progress` | `state:ready-for-review` | Implementation complete |
| `state:ready-for-review` | `state:done` | Sign-off / merge |
| any | `state:blocked` | Dependency or env blocker |
| any | `state:wontfix` | Explicit cancel |

## Hard rules

- **Never** transition `state:needs-info` → `state:ready-for-agent` without explicit human reply in the thread.
- Remove prior `state:*` label before adding a new one (use **`lib/triage.sh transition`**).
- Do not close issues as part of triage unless the user explicitly requests close.

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
