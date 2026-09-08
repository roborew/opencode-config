# Worktree Plugin Plan (archived)

This document is **historical** and is **not an operational source of truth**.

The worktree/session architecture described by earlier planning notes has since been implemented and evolved. For current behavior, use these live documents instead:

- `agents/orchestrate.md`
- `skills/orchestrate/SKILL.md`
- `agents/worktree-manager.md`
- `skills/worktree-sandbox/SKILL.md`
- `docs/RUNBOOK.md`
- `docs/FEATURE-PIPELINE.md`
- `docs/smoke/feature-worktree-fanout-validation.md`

## Current authoritative model

- `orchestrate` owns outer-loop coordination on `develop`
- `worktree-manager` owns worktree lifecycle only
- `session_kickoff` is the direct kickoff path for coder sessions
- `session_notify` is the primary coder → orchestrator return path
- `scripts/dev-loop-poller.sh` is a **ticket-only** durable fallback
- feature-mode fallback is manual wake/resume of the develop orchestrator plus durable `feature_report:` fetch
- `worktree-sandbox` owns environment copy and verification-backend lifecycle

If you are searching the repo for current implementation guidance, stop here and follow the live files above.
