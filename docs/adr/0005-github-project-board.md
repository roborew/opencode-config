# GitHub Project board as portfolio view

The org-wide GitHub Project board (`GH_PROJECT`) provides a cross-repo portfolio view of PRD-driven work. GitHub issues remain the execution source of truth ([0001-github-issues-as-source-of-truth.md](0001-github-issues-as-source-of-truth.md)); the board is a read/rollup layer, not a second tracker.

**Decision:** Use linked GitHub issues (parent `prd` in spec repo, children `prd-task` in impl repos) with native sub-issue hierarchy. Do not use project draft cards.

**Configuration:** Machine-local `GH_PROJECT` in `~/.opencode-agent-env`. Scripts register issues via `gh project item-add` when set; GitHub Project auto-add workflows provide redundancy per repo.

**Auto-close:** Spec repo workflow `prd-parent-auto-close` closes PRD parents when all sub-issues are closed. `feature-complete` remains the human ceremony for rollup and delivery records.

**Considered:** Per-stack project boards. Rejected for now — org-wide board is sufficient; override can be added later via `issue-tracker.md` if needed.
