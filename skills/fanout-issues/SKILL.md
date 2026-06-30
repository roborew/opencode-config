---
name: fanout-issues
description: "Cross-repo companion to to-prd: after PRD frontmatter is filled, run opencode-run spec fanout <slug> from this spec repo to create child GitHub issues (one per ticket or legacy slice)."
modelTier: "fast"
roleReminder: "Spec repo. opencode-run spec fanout for child issues (never gh issue create). Task scribe for files; Task developer for gh edits."
---

# Fanout issues

## When

`docs/prd/<slug>.md` has valid YAML frontmatter with **`tickets:`** (preferred) or legacy **`slices:`**, plus `parent_issue` and `target_repos` as defined in `docs/prd/_template.md`.

## How

From this repo root, run **exactly once** per slug (unless resuming after a failed run):

```bash
opencode-run spec fanout <slug>
```

`opencode-run spec fanout` (tickets mode) runs **`fanout-audit`**, then **`sync-fanout-bodies`**, then **`feature-check --level fanout`**. If any step fails, **stop** — do not hand-create issues.

After editing `docs/prd/<slug>.md` later, run `opencode-run spec feature-upgrade <slug>` (same body sync + broader checks).

## Hard rules

- **Only** `opencode-run spec fanout <slug>` creates child issues — never hand-roll `gh issue create` for PRD tickets.
- Never run fanout twice in parallel for the same slug.
- Never fanout in parallel subagents or parallel bash calls.
- If fanout reports `Skipping existing #N`, that is success — do not create another issue for the same ticket.
- Re-run fanout only when resuming after failure or after fixing the PRD; idempotent skips are expected.
- If duplicate open issues exist for one ticket id, close duplicates before re-running fanout.

## When fanout fails or exits non-zero

Do not assume zero issues were created. Partial fanout is common.

1. Run `opencode-run spec fanout-audit <slug>` and read the report (`OK`, `MISSING`, `DUPLICATE`, `ORPHAN` per ticket).
2. Never run `gh issue create` for PRD tickets — not even "just the missing ones."
3. If lock error (exit 8): wait, or remove stale `.fanout-lock-<slug>/` only when no fanout process is running, then run `opencode-run spec fanout-audit`, then `opencode-run spec fanout` again.
4. If duplicate (exit 10 or audit `DUPLICATE`): close the extra issues, re-run audit until `PASS`, then `opencode-run spec fanout`.
5. If audit shows only `MISSING`: `opencode-run spec fanout <slug>` again — it skips existing matches.
6. If fanout keeps failing: debug the script error; do not bypass with manual creates.

## Rules

### `tickets:` (preferred)

- Each ticket row becomes one child issue in the repo named by `repo` (full `owner/repo` matching `docs/agents/repos.md`).
- Issues are created in dependency order (`depends_on` task ids).
- Labels include `feature:<slug>`, `state:ready-for-agent`, `mode:afk` or `mode:hitl`, `category:feature`, and **`prd-task`** (for org project board auto-add).
- Child issues are created as **sub-issues** of the PRD parent (`parent_issue` in PRD frontmatter) via `gh issue create --parent`.
- When `GH_PROJECT` is set in `~/.opencode-agent-env`, fanout also adds each child issue to the org project board.
- The issue body embeds fenced `opencode-task-json` metadata plus human-readable sections.

### Legacy `slices:`

- Each slice key must be a full `owner/repo` string matching `docs/agents/repos.md`.
- One broad issue per repo.

### Idempotency

- Before each create, fanout checks existing issues by exact title and embedded task id.
- Re-running fanout on existing issues re-links them as sub-issues and adds them to the project board when `GH_PROJECT` is set.
- Duplicate ticket ids or duplicate `(repo, title)` pairs in the PRD cause fanout to exit before creating anything.
- Multiple GitHub issues matching one ticket cause fanout to exit; close extras first.

## After fanout completes

Report a **Fanout summary** table to the user (mandatory):

| Field | Value |
|-------|-------|
| PRD | `docs/prd/<slug>.md` |
| Parent issue | `<url>` |
| Project board | `<GH_PROJECT url or "skipped (GH_PROJECT unset)">` |
| Sub-issues linked | `<count> / <ticket count>` |
| Child issues | `<repo>#<n>` per ticket (or compact table) |
