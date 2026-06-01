# Spec feature vs targeted change (two-mode model)

OpenCode's architect front door presents two modes: **Spec feature** (spec repo: grill-me → to-prd → fanout → issue-expand → orchestrate across repos) and **Targeted change** (impl repo: optional grill-me → to-issues → optional issue-expand → orchestrate). Both use GitHub issues; spec features additionally require a PRD and cross-repo fanout.

**Considered:** A single menu with a "legacy local plan" option. Rejected — GitHub-always simplifies the pipeline and removes `.plan` maintenance.
