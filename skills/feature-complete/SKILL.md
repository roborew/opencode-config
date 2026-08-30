---
name: feature-complete
description: Close a spec-driven feature after all implementation repos finished — cross-repo rollup, merged-state verification, close child issues, close PRD parent.
modelTier: smart
roleReminder: "Run in PROJECT-spec only. Issue close happens here — impl feature PR merges happen in the impl orchestrator session."
---

# Feature complete

**Level 3** ceremony: whole feature done across all repos. Per-repo work should already show **`state:done`** (issues still open) — docs come from the feature coder's `feature-review` loop on the merged feature branch. The impl orchestrator already merged the feature PR.

## Preconditions

- Session cwd is **spec repo** (`docs/prd/`, `docs/agents/repos.md`).
- User provides kebab **`feature:<slug>`** (without prefix) or `feature:<slug>` label string.
- `docs/prd/<slug>.md` exists with `parent_issue` URL in frontmatter.

## Data collection

1. Read `docs/prd/<slug>.md` and `docs/agents/repos.md`.
2. Task **`developer`** `load: minimal` — for each registry `repo`:

   ```bash
   gh issue list --repo <owner/name> -l "feature:<slug>" --state open -L 200 \
     --json number,title,state,url,labels
   ```

3. Compare PRD **`tickets:`** `id` values to issues per repo. Every issue for this slug should have **`state:done`** label and remain **open** until this ceremony.
4. Collect PR URLs from issue comments, linked PRs, or:

   ```bash
   gh search prs "repo:<owner/name> <slug>" --json number,url,state,headRefName --limit 20
   ```

5. For each PR, collect mergeability and checks:

   ```bash
   gh pr view <url> --json mergeable,state,headRefName,baseRefName,statusCheckRollup
   ```

## Rollup comment on spec parent

Parse `parent_issue` from PRD frontmatter. Task **`developer`**:

```bash
gh issue comment <parent-n> --repo <spec-owner/name> --body-file /tmp/rollup.md
```

Rollup table columns: **Repo** | **Issue** | **Labels** | **PR link** | **PR state**

## Per-repo gate (before close)

If any repo has open `feature:<slug>` issues **without** `state:done`, **stop** — tell the user to finish the feature coder loop in that repo (re-kick the feature coder via the impl `orchestrate` session).

If any `feature:<slug>` issue lacks the `verified` label, **stop** — every issue must carry `verified` (set only on code-review APPROVED) before close.

## Merge gate (merged-state verification — required)

Every impl feature PR must already show `gh pr view --json state` = `MERGED` (merged by the impl orchestrator on "all reviewed"). If any PR is not yet merged, **stop** and tell the user to finish the orchestrator gate — say "all reviewed" to the impl `orchestrate` session for that repo.

This is a verify-only check. There is no merge choice UI and no agent-merge path here.

## Close child issues (at merge)

After merged-state verification passes (delegated `developer` confirms `state: MERGED` for every impl feature PR), Task **`developer`** per impl repo:

```bash
bash "$OC/skills/feature-complete/lib/close-feature-issues.sh" "<slug>" "<pr_url>" --repo <owner/name>
```

Run for every registry repo with `feature:<slug>` issues.

## Close PRD parent

Task **`developer`** — check whether parent is already closed (`prd-parent-auto-close` workflow may have closed it):

```bash
gh issue view <parent-n> --repo <spec-owner/name> --json state -q .state
```

If still open and the merged-state gate passed for every impl repo:

```bash
gh issue close <parent-n> --repo <spec-owner/name>
```

Optional: add label `state:done`.

## PRD delivery record

Task **`scribe`** to append to `docs/prd/<slug>.md`:

```markdown
## Delivery record

- **Completed:** <date>
- **PRs:** <bulleted list with merge evidence>
- **Merge:** human | agent (impl orchestrator)
```

## Hard rules

- Do not invoke `orchestrate` or write application source.
- **Issue close** happens in **this spec session** only.
- **PR merge** happens in the impl `orchestrate` session, not here. Verify only.
- Never delete `develop`, `main`, or `master` branches.
- `prd-parent-auto-close` is backup; this skill is the primary close ceremony.
