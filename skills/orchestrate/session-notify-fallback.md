---
name: session-notify-fallback
description: "Copy-paste markdown block the coder (or feature coder) emits in its terminal reply when `session_notify` to the develop orchestrator returns a blocker (`SESSION_NOT_FOUND`, `error: session_not_found`, or 404). Provides the operator a one-paste manual wake path and a `gh issue comment` alternative that the poller will pick up."
---

# Session-notify fallback (review wake)

When `session_notify` cannot reach the develop orchestrator — most commonly because the `develop_session_id` from the kickoff message went stale after an `opencode-server` restart — the coder must **not** silently swallow the failure. The durable wake channel is the `ticket_report:` (or `feature_report:`) issue comment; `scripts/dev-loop-poller.sh` + `scripts/dev-loop-watch.sh` will pick it up within one poll interval. To unblock immediately, the coder emits the **copy-paste markdown block below** in its terminal reply so the operator can forward the wake manually.

## When to emit

Emit the fallback block **only** when the `session_notify` envelope matches one of:

- `error: "session_not_found"`
- `status == 404`
- `blocker_code: "SESSION_NOT_FOUND"`

A generic `SESSION_API_FAILED` (network blip, server 5xx) is **not** a fallback trigger — `ticket_report:` posting already succeeded, the poller will wake the orchestrator, and the coder should just record `notify_status` and stop. Emitting the block on every error clutters the terminal and creates duplicate wakes when both the notify and the poller succeed.

## Required inputs

Capture these before posting the terminal report:

- `DEVELOP_SESSION_ID` — the develop orchestrator session id from the kickoff message inline (`develop_session_id: <id>`).
- `SERVER_URL` — `OPENCODE_SERVER_URL` from the coder session's environment, or the opencode-server base URL (no trailing slash). If unknown, fall back to the second `gh` one-liner alternative which needs no server auth.
- `ORCHESTRATOR_DIRECTORY` — the develop orchestrator's main checkout directory (for the `?directory=` query on the fallback curl — matches the poller's working `?directory=` pattern). If unknown, fall back to the `gh` one-liner alternative.
- `REPO` — `<owner>/<repo>` (the impl repo).
- `FEATURE` — feature slug (no `feature:` prefix).
- `ISSUE` — issue number.
- `PR_URL` — sub-PR URL (the `READY_FOR_HUMAN_REVIEW` `pr_url` field).

If `DEVELOP_SESSION_ID` is missing (kickoff was truncated and §0.2 GitHub reconstruction returned `null`), emit only the **`gh issue comment` alternative** — there is no session id to forward to.

## Markdown block to emit

Emit this **inside** the coder's terminal reply (not as an issue comment) so the operator reads it in the GUI session:

````text
## session-notify fallback (review wake)

The develop orchestrator could not be auto-woken (`session_notify` returned `<error>`). The `ticket_report:` comment is already posted on `<repo>#<n>` and `scripts/dev-loop-poller.sh` will wake the develop orchestrator within one poll interval — no action needed if you're happy to wait ~2 poll cycles (~4 min).

To forward the wake immediately, paste one of the following in any shell with the opencode-server env loaded:

```bash
DEVELOP_SESSION_ID="<captured from kickoff message develop_session_id>"
SERVER_URL="<opencode-server base url>"
ORCHESTRATOR_DIRECTORY="<develop orchestrator main checkout directory>"
curl -fsS -u "${OPENCODE_SERVER_USERNAME:-opencode}:${OPENCODE_SERVER_PASSWORD:-opencode}" \
  -X POST "${SERVER_URL}/session/${DEVELOP_SESSION_ID}/prompt_async?directory=${ORCHESTRATOR_DIRECTORY}" \
  -H "Content-Type: application/json" \
  -d '{"message":"DEV_LOOP_WAKE: {\"repo\":\"<owner/repo>\",\"feature\":\"<slug>\",\"reason\":\"TICKET_REVIEW_READY\",\"issue\":<n>,\"pr_url\":\"<url>\"}"}'
```

Alternative one-liner that posts the durable `DEV_LOOP_WAKE` comment the poller will pick up (no opencode-server auth required):

```bash
gh issue comment <n> --repo <owner/repo> --body 'DEV_LOOP_WAKE: {"repo":"<owner/repo>","feature":"<slug>","reason":"TICKET_REVIEW_READY","pr_url":"<url>"}'
```
````

The block is a one-shot fallback. Do not loop it, do not append a second copy on subsequent notifies, do not include it in the `ticket_report:` issue comment itself.

## After emitting

The coder still posts `ticket_report:` (mandatory), records `notify_status: develop_session_id_stale` in the comment, and stops. The operator decides whether to paste the curl or wait for the poller. The develop orchestrator's `scripts/dev-loop-watch.sh` already treats `DEV_LOOP_WAKE` with `reason: TICKET_REVIEW_READY` (and `feature_report: FEATURE_REVIEW_READY`) as equivalent to the `ticket_report: READY_FOR_HUMAN_REVIEW` wake — no orchestrator-side changes required.
