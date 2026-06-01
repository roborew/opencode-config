# GitHub issues as universal source of truth

Every planned unit of work becomes a GitHub issue before implementation. Repositories store application code and operational files only — no local `.plan/` work-tracking artifacts. Planning output lives on GitHub (and PRDs in the spec repo for multi-repo features). Commits reference or close issues so delivery stays reviewable in GitHub.

**Considered:** Keeping local `.plan/` for ad-hoc debug/refactor work. Rejected — dual paths caused confusion and untracked work.
