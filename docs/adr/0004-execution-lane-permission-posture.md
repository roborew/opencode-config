# Execution-lane permission posture (broad allow + deny-list)

Execution subagents (`developer`, `frontend-dev`, `ux-dev`, `senior-dev`, `scribe`, `verifier`, etc.) use `bash: "*": allow` with explicit dangerous-command denies and `edit` denied on `~/.config/opencode/**`. This supports unattended orchestration overnight. Planning agents (`architect`, `orchestrate`) stay guarded — architect is read-only with an explicit bash allowlist; orchestrate has `bash: false` and delegates shell to `developer`.

**Considered:** Granular per-command allowlists for execution agents. Rejected — too much approval friction for overnight runs; trust boundary is in-repo git + verifier + human PR review.
