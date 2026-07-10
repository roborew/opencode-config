# Spec feature vs targeted change (two-mode model)

OpenCode's architect front door presents two modes: **Spec feature** (spec repo: grill-me → to-prd → fanout → issue-expand → handoff → orchestrate per impl repo → spec Mode F sign-off) and **Targeted change** (impl repo: optional grill-me → to-issues → orchestrate). Both use GitHub issues; spec features additionally require a PRD and cross-repo fanout. Technical planning (issue-expand) runs from the spec repo using path-scoped codebase discovery on sibling impl repos.

**Considered:** A single menu with a "legacy local plan" option. Rejected — GitHub-always simplifies the pipeline and removes `.plan` maintenance.
