# 2026-05-18 — Architect GitHub CLI permissions and PRD publishing access

**Session scope:** Diagnose why Architect could not publish a PRD GitHub issue via `gh`, verify local GitHub CLI access, and update Architect command permissions so the PRD workflow could run the required GitHub commands.

**Status:** Finalized in chat on 2026-05-18. Re-verify on disk before relying on it, because `agents/architect.md` appeared to have changed when this review note was created on 2026-06-01.

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
