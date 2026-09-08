---
name: session-notify-fallback
description: "Copy-paste markdown block the coder (ticket or feature mode) emits when `session_notify` to the develop orchestrator returns a stale-session shape. Ticket mode may still auto-wake via the ticket-only poller; feature mode requires manual wake/resume so the develop orchestrator fetches the durable `feature_report:`."
---

# Session-notify fallback (manual wake)

When `session_notify` cannot reach the develop orchestrator — most commonly because the `develop_session_id` from the kickoff message went stale after an `opencode-server` restart — the coder must **not** silently swallow the failure. The durable terminal report (`ticket_report:` or `feature_report:`) is already posted and remains authoritative. `session_notify` is still the primary wake.

## When to emit

Emit the fallback block **only** when the `session_notify` envelope matches one of:

- `error: "session_not_found"`
- `status == 404`
- `blocker_code: "SESSION_NOT_FOUND"`

A generic `SESSION_API_FAILED` is not this fallback shape — record `notify_status` and stop.

## Required inputs

Capture these before posting the terminal report:

- `MODE` — `ticket` or `feature`
- `REPO` — `<owner>/<repo>` (ticket mode)
- `ISSUE` — issue number (ticket mode)
- `FEATURE` — `feature:<slug>`
- `PR_URL` — ready PR URL when present
- `PRD_PARENT_ISSUE_URL` — durable `feature_report:` target (feature mode)

## Markdown block to emit

Emit this **inside** the coder's terminal reply (not as an issue comment):

```text
## session-notify fallback (manual wake)

`session_notify` could not reach the develop orchestrator (`<error>`). The durable terminal report is already posted.

- Ticket mode:
  - `ticket_report:` is posted on `<owner/repo>#<n>`.
  - `session_notify` remains the primary wake.
  - Durable fallback: the ticket-only poller may still wake the develop orchestrator automatically.
  - To unblock immediately, wake or resume the develop orchestrator manually and say:
    `check ticket_report for <owner/repo>#<n>`

- Feature mode:
  - `feature_report:` is posted on `<prd_parent_issue_url>`.
  - `session_notify` remains the primary wake.
  - There is no poller guarantee for `feature_report:`.
  - To unblock, wake or resume the develop orchestrator manually and say:
    `check feature_report for feature:<slug> on <prd_parent_issue_url>`

If the original develop session is gone, open or resume the develop orchestrator on `develop` and give it the same instruction. It should fetch the latest durable report before acting.
```

## After emitting

The coder still posts the durable `ticket_report:` or `feature_report:` (mandatory), records `notify_status: develop_session_id_stale` when that is the failure shape, and stops. Ticket mode may still auto-wake via the ticket-only poller. Feature mode has **no poller guarantee** — operator/manual wake or resume is the fallback.
