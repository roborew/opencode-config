---
name: handoff
description: Compact the current conversation into a transfer document so another agent or session can continue. Use when the user asks for a handoff, session summary for a fresh agent, or context compaction before starting over.
argument-hint: "What will the next session be used for?"
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work.

## Output path

Persist the handoff document using **bash** (preferred when your agent has `bash: true`):

1. `HANDOFF_PATH=$(mktemp -t handoff-XXXXXX.md)` — capture the path.
2. Write the full document with a shell redirect or `tee` (heredoc / `printf`) to `"$HANDOFF_PATH"`.
3. Echo the path in your completion message.

**Orchestrate agent** has `bash: false` — do not rely on `mktemp`. Output the full handoff markdown **in your reply** for the user to save manually, or Task **`developer`** once with explicit instructions to write the file at a user-approved path under the workspace using the write tool.

**Architect** has `bash: true` and no direct write — use the bash + `mktemp` method above.

## Content

- Current goal, blockers, and **next concrete action** (one sentence).
- Pointers only — do **not** duplicate full plan bodies, CONTEXT.md, ADRs, or long transcripts. Reference paths and URLs (e.g. `feature:<slug>` label, `gh issue list -l "feature:<slug>"`, PRD path).
- Environment notes if relevant (branch, failing command, last error line).
- Suggest which skills the next session should load (e.g. `grill-me`, `to-tickets`, `ticket-lifecycle`, `feature-review`, `debug-fix`).

If the user passed arguments (or the hint), treat them as what the next session should focus on and tailor the doc accordingly.
