---
name: fanout-issues
description: "Cross-repo companion to to-prd: after PRD frontmatter is filled, run bin/fanout <slug> from this spec repo to create child GitHub issues (one per ticket or legacy slice)."
modelTier: "fast"
roleReminder: "Operates in the application spec repo; uses gh + yq."
---

# Fanout issues

## When

`docs/prd/<slug>.md` has valid YAML frontmatter with **`tickets:`** (preferred) or legacy **`slices:`**, plus `parent_issue` and `target_repos` as defined in `docs/prd/_template.md`.

## How

From this repo root, run **exactly once** per slug (unless resuming after a failed run):

```bash
bin/fanout <slug>
```

`bin/fanout` (tickets mode) runs **`fanout-audit`**, then **`sync-fanout-bodies`**, then **`feature-check --level fanout`**. If any step fails, **stop** — do not hand-create issues.

After editing `docs/prd/<slug>.md` later, run `bin/feature-upgrade <slug>` (same body sync + broader checks).

## Hard rules

- **Only** `bin/fanout <slug>` creates child issues — never hand-roll `gh issue create` for PRD tickets.
- Never run fanout twice in parallel for the same slug.
- Never fanout in parallel subagents or parallel bash calls.
- If fanout reports `Skipping existing #N`, that is success — do not create another issue for the same ticket.
- Re-run fanout only when resuming after failure or after fixing the PRD; idempotent skips are expected.
- If duplicate open issues exist for one ticket id, close duplicates before re-running fanout.

## When fanout fails or exits non-zero

Do not assume zero issues were created. Partial fanout is common.

1. Run `bin/fanout-audit <slug>` and read the report (`OK`, `MISSING`, `DUPLICATE`, `ORPHAN` per ticket).
2. Never run `gh issue create` for PRD tickets — not even "just the missing ones."
3. If lock error (exit 8): wait, or remove stale `.fanout-lock-<slug>/` only when no fanout process is running, then run `bin/fanout-audit`, then `bin/fanout` again.
4. If duplicate (exit 10 or audit `DUPLICATE`): close the extra issues, re-run audit until `PASS`, then `bin/fanout`.
5. If audit shows only `MISSING`: `bin/fanout <slug>` again — it skips existing matches.
6. If fanout keeps failing: debug the script error; do not bypass with manual creates.

## Rules

### `tickets:` (preferred)

- Each ticket row becomes one child issue in the repo named by `repo` (full `owner/repo` matching `docs/agents/repos.md`).
- Issues are created in dependency order (`depends_on` task ids).
- Labels include `feature:<slug>`, `state:ready-for-agent`, `mode:afk` or `mode:hitl`, and `category:feature`.
- The issue body embeds fenced `opencode-task-json` metadata plus human-readable sections.

### Legacy `slices:`

- Each slice key must be a full `owner/repo` string matching `docs/agents/repos.md`.
- One broad issue per repo.

### Idempotency

- Before each create, `bin/fanout` checks existing issues by exact title and embedded task id.
- Duplicate ticket ids or duplicate `(repo, title)` pairs in the PRD cause fanout to exit before creating anything.
- Multiple GitHub issues matching one ticket cause fanout to exit; close extras first.
