---
name: feature-complete
description: Close a spec-driven feature after all implementation repos finished — cross-repo issue rollup, PR links on spec parent issue, close PRD parent.
modelTier: smart
roleReminder: "Run in PROJECT-spec only. Do not close the spec parent from an implementation repo session."
---

# Feature complete

**Level 3** ceremony: whole feature done across all repos. Per-repo work should already be closed via **Mode F** in each implementation repo.

## Preconditions

- Session cwd is **spec repo** (`docs/prd/`, `docs/agents/repos.md`).
- User provides kebab **`feature:<slug>`** (without prefix) or `feature:<slug>` label string.
- `docs/prd/<slug>.md` exists with `parent_issue` URL in frontmatter.

## Data collection

1. Read `docs/prd/<slug>.md` and `docs/agents/repos.md`.
2. Task **`developer`** `load: minimal` — for each registry `repo`:

   ```bash
   gh issue list --repo <owner/name> -l "feature:<slug>" --state all -L 200 \
     --json number,title,state,url,labels
   ```

3. Compare PRD **`tickets:`** `id` values to closed issues per repo. Flag open or missing tickets.
4. Collect PR URLs from issue comments, linked PRs, or:

   ```bash
   gh search prs "repo:<owner/name> <slug>" --json number,url,state --limit 20
   ```

## Rollup comment on spec parent

Parse `parent_issue` from PRD frontmatter (GitHub issue URL). Task **`developer`**:

```bash
gh issue comment <parent-n> --repo <spec-owner/name> --body-file /tmp/rollup.md
```

Rollup table columns: **Repo** | **Issue** | **State** | **PR link**

## Human gate

Present rollup and gaps. Ask: **Close spec parent issue?** Only on explicit yes.

## Close parent

```bash
gh issue close <parent-n> --repo <spec-owner/name>
```

Optional: `gh issue edit` add label `state:done`.

## PRD delivery record

Task **`scribe`** to append to `docs/prd/<slug>.md`:

```markdown
## Delivery record

- **Completed:** <date>
- **PRs:** <bulleted list>
```

## Per-repo reminder

If any repo still has **open** `feature:<slug>` issues, **stop** — tell user to finish **Mode F** in that impl repo first. Do not close spec parent.

## Hard rules

- Do not invoke `orchestrate` or write application source.
- Final **parent close** happens in **this spec session** only (not from impl repo architect).
