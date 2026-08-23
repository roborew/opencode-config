---
name: feature-complete
description: Close a spec-driven feature after all implementation repos finished — cross-repo rollup, merge gate, close child issues, merge PRs, close PRD parent.
modelTier: smart
roleReminder: "Run in PROJECT-spec only. Issue close and PR merge happen here—not in impl architect Mode F."
---

# Feature complete

**Level 3** ceremony: whole feature done across all repos. Per-repo work should already show **`state:done`** (issues still open) and Mode F Phase 2 docs via **impl architect option 4**.

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
4. Collect PR URLs from issue comments, linked PRs, orchestrate/impl architect handoffs, or:

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

## Per-repo gate (before merge)

If any repo has open `feature:<slug>` issues **without** `state:done`, **stop** — tell user to finish **impl architect Mode F** in that repo first.

If any `feature:<slug>` issue lacks the `verified` label, **stop** — every issue must carry `verified` (set only on verifier APPROVED) before merge. This is a cheap backstop; architect Mode F accept already refuses unverified issues.

If any repo PR is missing or not merge-ready, stop and report gaps.

## Merge gate (required human choice)

Present:

```markdown
## Merge gate

| PR | Repo | Branch | Checks | Mergeable |
|----|------|--------|--------|-----------|
| <url> | owner/name | head → base | pass/fail/pending | yes/no |

Choose:
1. **I will merge** on GitHub (checklist: merge each PR in dependency order; delete head branch after merge unless develop/main/master)
2. **Agent merges on my behalf** — coordinated merge + safe branch delete
```

- Multi-repo: merge in PRD dependency order unless PRD/handoff marks **staggered** deploy (then confirm order explicitly).
- Default merge method: **merge commit** (`--merge`). Use squash/rebase only when user or repo policy requests.

### Agent merge path (option 2 only)

Task **`developer`** `load: minimal` per PR in order:

```bash
OC="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
bash "$OC/skills/feature-complete/lib/merge-feature-prs.sh" \
  --repo <owner/name> --pr <number> [--merge-method merge|squash|rebase]
```

Script merges the PR and deletes the head branch unless it is `develop`, `main`, or `master`.

### Human merge path (option 1)

Print ordered PR links and checklist. Wait for user confirmation that merges are done before closing issues/PRD.

## Close child issues (at merge)

After merges confirmed (agent evidence or user yes), Task **`developer`** per impl repo:

```bash
bash "$OC/skills/feature-complete/lib/close-feature-issues.sh" "<slug>" "<pr_url>" --repo <owner/name>
```

Run for every registry repo with `feature:<slug>` issues.

## Close PRD parent

Task **`developer`** — check whether parent is already closed (`prd-parent-auto-close` workflow may have closed it):

```bash
gh issue view <parent-n> --repo <spec-owner/name> --json state -q .state
```

If still open and user confirmed ceremony complete:

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
- **Merge:** human | agent
```

## Hard rules

- Do not invoke `orchestrate` or write application source.
- **Issue close** and **PR merge** happen in **this spec session** only.
- Never delete `develop`, `main`, or `master` branches.
- `prd-parent-auto-close` is backup; this skill is the primary close ceremony.
