# 2026-05-18 — Architect GitHub CLI permissions and PRD publishing access

**Session scope:** Diagnose why Architect could not publish a PRD GitHub issue via `gh`, verify local GitHub CLI access, and update Architect command permissions so the PRD workflow could run the required GitHub commands.

**Status:** Finalized in chat on 2026-05-18. Re-verify on disk before relying on it, because `agents/architect.md` appeared to have changed when this review note was created on 2026-06-01.

**Date convention:** The filename and title use the Cursor chat creation date, not the date this review note was written.

---

## Executive summary

- Confirmed the blocker was not GitHub authentication or the `gh` CLI itself.
- Identified OpenCode agent command permissions as the gate that prevented Architect from running `gh`.
- Updated `agents/architect.md` during the chat to allow the specific GitHub CLI commands needed for PRD issue publishing.
- Verified `gh` authentication, repository identity, and label access directly from the CLI.
- Added `gh label create *` after discovering the PRD-specific labels were missing.
- Ran `./scripts/validate-opencode-config.sh` after each permission update; validation passed.

---

## User-facing problem

Architect needed to publish a PRD and reported that it required GitHub CLI access for:

- `gh auth status`
- `gh repo view --json nameWithOwner`
- `gh label list`
- `gh issue create`

The user verbally approved the commands, but Architect still reported that the permission system blocked them and suggested per-command approval or an IDE popup.

The key clarification from the session:

- GitHub itself does not need an IDE permission popup.
- The relevant gate is OpenCode's agent-level command permission layer.
- A stale running Architect session may continue using old permissions until the OpenCode session is reloaded or restarted.

---

## Changes implemented in chat

### 1. Narrow `gh` allows for Architect

The Architect agent permission block was updated during the chat to allow:

```yaml
"gh auth status": allow
"gh repo view --json nameWithOwner": allow
"gh repo view --json nameWithOwner *": allow
"gh label list": allow
"gh label list *": allow
"gh issue create": allow
"gh issue create *": allow
```

This kept the permission surface focused on the PRD publishing flow rather than allowing all GitHub CLI commands.

### 2. Label creation allow

After checking repository labels, only GitHub's default labels existed. The PRD flow expects labels such as:

- `prd`
- `state:ready-for-agent`
- `feature:<slug>`

Because `skills/to-prd/SKILL.md` explicitly says to create missing labels before applying them, the permission block was extended with:

```yaml
"gh label create *": allow
```

### 3. Configuration validation

The config validator was run after the edits:

```sh
./scripts/validate-opencode-config.sh
```

Result:

```text
validate-opencode-config: OK
```

---

## Reconstruction details for another AI

This section captures the operational details needed to recreate the changes that were actioned in the original chat.

### Original target file

The changes were made in:

```text
agents/architect.md
```

At the time of the original chat, the file had a frontmatter permission structure like this:

```yaml
---
description: Planning coordinator. Decomposes features into sub-problems, investigates via claude-context, spawns scoped strategist instances, combines reports. Delegates other plan types to specialists. Passes output to scribe, then hands off to orchestrate.
mode: primary
model: openrouter/deepseek/deepseek-v4-flash
tools:
  write: false
  edit: false
  bash: true
  skill: true
permission:
  edit: deny
  bash:
    "*": ask
    "pwd": allow
    "ls": allow
    "ls *": allow
    "find": allow
    "find *": allow
    "rg": allow
    "rg *": allow
    "grep": allow
    "grep *": allow
    "sed -n *": allow
    "git status": allow
    "git status *": allow
    "git diff": allow
    "git diff *": allow
    "git show": allow
    "git show *": allow
    "git log": allow
    "git log *": allow
    "git ls-files": allow
    "git ls-files *": allow
    "git grep": allow
    "git grep *": allow
    "rm *": deny
    "mv *": deny
    "cp *": deny
    "mkdir *": deny
    "touch *": deny
    "chmod *": deny
    "git add *": deny
    "git commit *": deny
    "git push *": deny
    "git reset *": deny
    "git checkout *": deny
    "git restore *": deny
    "git clean *": deny
    "git apply *": deny
    "sed -i *": deny
    "*>*": deny
    "*>>*": deny
    "*| tee *": deny
  skill: { "architect-plan": "allow", "architect-review": "allow", "github-issue-run": "allow", "grill-me": "allow", "handoff": "allow", "to-issues": "allow", "to-prd": "allow", "triage": "allow", "research": "allow", "improve-codebase-architecture": "allow", "zoom-out": "allow", "caveman": "allow", "setup-skills": "allow" }
  task:
    "*": deny
    strategist: allow
    debugger: allow
    refactor: allow
    review: allow
    document: allow
    designer: allow
    scribe: allow
---
```

The important part was the `permission.bash` map. It defaulted to `"*": ask`, so any command not explicitly allowed could be blocked by OpenCode's permission system.

### Exact permission rules added

The first patch inserted the GitHub CLI read/check commands and issue publishing command immediately after the existing `git grep` allows and before destructive command denies:

```diff
     "git grep": allow
     "git grep *": allow
+    "gh auth status": allow
+    "gh repo view --json nameWithOwner": allow
+    "gh repo view --json nameWithOwner *": allow
+    "gh label list": allow
+    "gh label list *": allow
+    "gh issue create": allow
+    "gh issue create *": allow
     "rm *": deny
     "mv *": deny
     "cp *": deny
```

After verifying labels, a second patch added label creation:

```diff
     "gh label list": allow
     "gh label list *": allow
+    "gh label create *": allow
     "gh issue create": allow
     "gh issue create *": allow
```

The final intended `gh` block was:

```yaml
    "gh auth status": allow
    "gh repo view --json nameWithOwner": allow
    "gh repo view --json nameWithOwner *": allow
    "gh label list": allow
    "gh label list *": allow
    "gh label create *": allow
    "gh issue create": allow
    "gh issue create *": allow
```

### Why each command was allowed

| Command pattern | Reason |
| --- | --- |
| `gh auth status` | Confirm local GitHub CLI authentication before trying to publish. |
| `gh repo view --json nameWithOwner` | Confirm the issue would be created against the intended repository. |
| `gh repo view --json nameWithOwner *` | Cover variants with query flags such as `-q .nameWithOwner`. |
| `gh label list` / `gh label list *` | Check whether required labels already exist. |
| `gh label create *` | Allow creation of missing PRD/state/feature labels required by the PRD workflow. |
| `gh issue create` / `gh issue create *` | Publish the PRD issue. |

### PRD workflow reason for label creation

The `to-prd` skill used during the chat required a GitHub issue with these labels:

```text
prd
state:ready-for-agent
feature:<slug>
```

The relevant workflow requirement was:

```markdown
Create GitHub issue in `$(gh repo view --json nameWithOwner -q .nameWithOwner)`:
- Title: `[PRD] <slug>: <one-line summary>`
- Labels (create with `gh label create` if missing, then apply):
  - `prd`
  - `state:ready-for-agent`
  - `feature:<slug>`
```

This is why `gh label list` was not enough. The target repo only had GitHub's default labels, so Architect needed permission to create labels before creating or labeling the issue.

### Commands run during the session

These commands were run from:

```text
/Users/robo/.config/opencode
```

Read-only GitHub checks:

```sh
gh auth status
gh repo view --json nameWithOwner
gh label list
```

Config validation after permission edits:

```sh
./scripts/validate-opencode-config.sh
```

The validation output was:

```text
Checking agents/*.md have keys in opencode.json agent block...
Checking skills referenced in agents exist...
Checking read-only planning agents have guarded bash...
Checking unattended execution/review subagents allow bash...
Checking unattended writers cannot edit shared OpenCode config externally...
Checking architect Mode B cannot route to refactor...
validate-opencode-config: OK
```

### Expected verification checks

After applying the permission rules, another AI should verify:

```sh
rg 'gh (auth status|repo view|label list|label create|issue create)' agents/architect.md
./scripts/validate-opencode-config.sh
```

Expected `rg` result should include these lines somewhere inside `agents/architect.md`:

```yaml
"gh auth status": allow
"gh repo view --json nameWithOwner": allow
"gh repo view --json nameWithOwner *": allow
"gh label list": allow
"gh label list *": allow
"gh label create *": allow
"gh issue create": allow
"gh issue create *": allow
```

Expected validator result:

```text
validate-opencode-config: OK
```

### Current repo drift handling

When this document was expanded on 2026-06-01, the current `agents/architect.md` frontmatter looked different. It had `tools.bash: true`, but no visible `permission.bash` block:

```yaml
tools:
  write: false
  edit: false
  bash: true
  skill: true
permission:
  edit: deny
  skill: { "architect-plan": "allow", "architect-review": "allow", "grill-me": "allow", "handoff": "allow", "to-issues": "allow", "zoom-out": "allow", "caveman": "allow", "setup-skills": "allow" }
  task:
    "*": deny
    strategist: allow
    debugger: allow
    refactor: allow
    review: allow
    document: allow
    designer: allow
    scribe: allow
```

If the current architecture has intentionally removed per-command bash allowlists, do not blindly restore the old full `permission.bash` block without checking the newer permission model. Instead, apply the same intent in the current structure:

- Architect must be allowed to run the narrow `gh` commands listed above.
- Architect should not be granted broad `gh *` access unless the project has intentionally moved to broader CLI permissions.
- Keep destructive git/file commands denied or outside Architect's responsibilities.
- Re-run `./scripts/validate-opencode-config.sh`.

If the current permission model still supports `permission.bash`, add only the narrow `gh` command rules to the existing bash map. If there is no bash map and OpenCode falls back to default behavior, confirm whether the new default is intentionally permissive or intentionally delegated elsewhere.

---

## GitHub CLI verification

The required GitHub CLI checks were run directly from `/Users/robo/.config/opencode`.

### Authentication

Command:

```sh
gh auth status
```

Result:

- Logged in to `github.com`
- Active account: `roborew`
- Git protocol: `ssh`
- Token scopes included `repo`

### Repository identity

Command:

```sh
gh repo view --json nameWithOwner
```

Result:

```json
{"nameWithOwner":"roborew/opencode"}
```

### Existing labels

Command:

```sh
gh label list
```

Result:

- `bug`
- `documentation`
- `duplicate`
- `enhancement`
- `good first issue`
- `help wanted`
- `invalid`
- `question`
- `wontfix`

PRD-specific labels were not present, which is why `gh label create *` was added.

---

## Final conclusion

OpenCode can use the same `gh` CLI installation and authentication state as the user's terminal when it runs under the same user account.

For this machine, the CLI side was confirmed working:

- `gh` was available.
- Authentication was active as `roborew`.
- The current repository resolved to `roborew/opencode`.
- The token had `repo` scope.

The remaining requirement is that the active OpenCode agent permission config must allow the exact shell commands Architect wants to run. If Architect still reports blocked commands after the permission edit, the practical fix is to reload or restart the running OpenCode/Architect session so it picks up the updated agent definition.

---

## Current disk verification note

When this review document was created on 2026-06-01, `agents/architect.md` no longer appeared to contain the earlier `permission.bash` block with the `gh` allow rules. That means the repository may have diverged since the original chat edits.

Before relying on this workflow, verify whether `agents/architect.md` currently allows the required commands:

```sh
rg 'gh (auth status|repo view|label list|label create|issue create)' agents/architect.md
```

If no matches are returned, reapply the narrow allows listed above and run:

```sh
./scripts/validate-opencode-config.sh
```
