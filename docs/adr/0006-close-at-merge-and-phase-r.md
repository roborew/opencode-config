# Close at merge and Phase R review ownership

## Status

Accepted

## Context

The feature pipeline previously closed impl issues during architect Mode F in the impl or spec session, and left PR merge as a manual step after docs. Operators wanted:

- Remediation localized to work repos (impl architect after PR).
- Full issue context visible through final PRD review.
- Spec to own coordinated merge and close (including multi-repo PRs).
- Explicit human vs agent merge choice with safe branch cleanup.

## Decision

1. **Phase R** — impl architect option 4 triages post-PR feedback (hosted comments, CI, incomplete tickets, user input) before acceptance. Remediation tickets publish in the impl repo as PRD sub-issues.
2. **Label-only acceptance** — impl Mode F Phase 1 sets `state:done` via `mode-f-accept-issues.sh`; issues remain **open**.
3. **Close at merge** — spec **feature-complete** closes all `feature:<slug>` child issues after merge gate (human or agent).
4. **Merge gate** — feature-complete asks user to merge manually or authorize agent merge; agent path uses `merge-feature-prs.sh` and deletes head branch unless `develop`/`main`/`master`.
5. **Orchestrate handoff** — after PR, paste targets **impl** architect Phase R (not spec close).

## Consequences

- `mode-f-close-issues.sh` is deprecated for impl Mode F; use `mode-f-accept-issues.sh` and `close-feature-issues.sh` at merge.
- `prd-parent-auto-close` remains backup; primary ceremony is feature-complete.
- Review subagent gains `github_pr_feedback_triage` execution mode.
- Strategist is allowed for architect only during Mode F Phase R.

## See also

- [FEATURE-PIPELINE.md](../FEATURE-PIPELINE.md)
- [skills/architect-review/SKILL.md](../../skills/architect-review/SKILL.md)
- [skills/feature-complete/SKILL.md](../../skills/feature-complete/SKILL.md)
