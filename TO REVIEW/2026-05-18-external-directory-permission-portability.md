# 2026-05-18 — External directory permissions: portable deny-only model

**Session scope:** Fix repeated OpenCode **Permission required → Access external directory** prompts during unattended agent work (Ruby gems under mise, project code under `~/05_Repos/...`), then refactor to a **portable, multi-user-safe** permission model without hardcoded user paths in shared agent config.

**Status:** Design and implementation **finalised in chat (2026-05-18)**. Re-verify on disk before merge — the repository may have diverged since this session (see [Current on-disk state](#current-on-disk-state-post-session)).

---

## Background

During OpenCode orchestration (e.g. `developer` working on blocshed), the UI repeatedly showed:

```text
Permission required
Access external directory ~/.local/share/mise/installs/ruby/.../actionview-...
```

and later:

```text
Access external directory ~/05_Repos/Repos/01_PROJECTS/apps/blocshed/blocshed-web/lib
```

The user expected:

- **In-repo work** — no prompts.
- **Outside the session cwd** — allowed when needed for normal dev (toolchain, sibling repos), not confirm every few minutes.
- **Guardrails** — block credential stores and machine-destructive commands, not arbitrary folder allowlists tied to one user’s layout.

---

## Root cause

OpenCode `external_directory` fires when a tool touches paths **outside the directory where OpenCode was started**, not “outside the project you care about.”

| Layer | What was configured | Effect |
| --- | --- | --- |
| Global `opencode.json` | `"external_directory": { "*": "allow", ... }` | Looked permissive |
| Subagents (`developer`, `verifier`, `scribe`, reviewers, …) | `"external_directory": { "*": ask, ... }` | **Overrides global** — prompts on almost every external read |
| Session cwd | Often spec repo, opencode config, or parent folder — not the impl repo | Paths like `~/05_Repos/.../blocshed-web/lib` count as **external** even though they are app source |

**Agent permission rules take precedence over global config.** The global allow was irrelevant whenever a subagent defined `"*": ask`.

---

## Iteration 1 — Per-path allowlists (reverted)

**Approach:** Add explicit allows before `"*": ask` in agent frontmatter and `opencode.json`:

- `~/.local/share/mise/**` (+ `/Users/robo/.local/share/mise/**`)
- `~/05_Repos/**` (+ `/Users/robo/05_Repos/**`)
- Existing `~/.config/opencode/**` allows

**Result:** Stopped prompts for those specific paths on that machine.

**Problem:** Not portable — hardcodes `/Users/robo/...` and personal folder roots in **shared** `agents/*.md`. Unacceptable for other users and wrong layering (machine layout ≠ agent behaviour).

---

## Iteration 2 — Final design (portable deny-only)

### Principle

| Concern | Where it lives |
| --- | --- |
| “Can agents read/write outside session cwd?” | **Only** `opencode.json` → `permission.external_directory` |
| “Can agents edit shared OpenCode config?” | Agent `permission.edit` deny for `~/.config/opencode/**` (writers only) |
| “Can agents run destructive shell?” | `opencode.json` → `permission.bash` deny patterns |
| User-specific extra paths | **Local fork** of `opencode.json` — never shared agents |

### Global `opencode.json` — `permission.external_directory`

```json
"external_directory": {
  "*": "allow",
  "~/.ssh/**": "deny",
  "~/.gnupg/**": "deny",
  "~/.aws/**": "deny"
}
```

- **Allow by default** — any external path (repos, mise gems, monorepo siblings, `/tmp`, etc.) without prompts.
- **Deny credential stores** — portable `~` patterns, no `/Users/...` literals.

Optional per-machine tightening (e.g. `"~/.config/**": "ask"`) belongs in a **personal** `opencode.json` fork, not in shared agents.

### Global `opencode.json` — `permission.bash` (destructive guardrails)

Added deny patterns aligned with [`scripts/block-dangerous-git.sh`](../scripts/block-dangerous-git.sh):

| Pattern | Blocks |
| --- | --- |
| `rm -rf /*`, `rm -rf ~/*`, `rm -rf ~` | Home/root wipe |
| `git push * --force*`, `git push * -f*` | Force push |
| `git reset --hard*` | Hard reset |
| `git clean -fd*`, `git clean -f *` | Aggressive clean |
| `git branch -D *` | Force-delete branch |
| `git checkout .`, `git restore .` | Discard all local changes |

Existing global `permission.edit` rules (`.env*`, `*.pem`, `*.key`, `opencode.json`, etc.) unchanged in intent.

### Agents — remove `external_directory` entirely

**Removed** the whole `external_directory` block from these 12 agents so they **inherit** global deny-only rules:

- `developer`, `frontend-dev`, `ux-dev`, `senior-dev`
- `verifier`, `scribe`, `helper`, `worktree-env`
- `review`, `security-reviewer`, `performance-reviewer`, `doc-reviewer`

**Writers** retain portable edit guard only (no absolute paths):

```yaml
permission:
  edit:
    "~/.config/opencode/**": deny
    "*": allow
```

Removed all `/Users/robo/...` literals from agent frontmatter.

### MCP portability

`claude-context` MCP command changed from:

```json
"/Users/robo/.local/share/mise/installs/node/22.22.1/bin/npx"
```

to:

```json
"npx"
```

Requires `npx` on `PATH` (see RUNBOOK / `~/.zshenv` / `scripts/agent-run.zsh`).

### Validator — [`scripts/validate-opencode-config.sh`](../scripts/validate-opencode-config.sh)

New checks (in addition to existing agent/skill checks):

| Check | Rationale |
| --- | --- |
| No `/Users/` or `/home/.../` in agent frontmatter | Portable config |
| Agents must **not** define `external_directory` | Single source of truth in `opencode.json` |
| Global `external_directory` must be `*: allow` + `~/.ssh`, `~/.gnupg`, `~/.aws` denies only | No hardcoded user roots in global config |
| Writers must `edit` deny `~/.config/opencode/**` only (tilde form) | Shared config protection without absolute paths |

Removed old requirements that forced `"*": ask` and per-path allowlists on unattended agents.

### Documentation updates

| File | Change |
| --- | --- |
| [`docs/RUNBOOK.md`](../docs/RUNBOOK.md) | Permission Conventions: portable deny-only model, no user roots in agents, bash guardrails, local overrides in `opencode.json` fork |
| [`README.md`](../README.md) | Global permission summary (external allow + credential denies + bash guardrails) |
| [`skills/worktree-env/SKILL.md`](../skills/worktree-env/SKILL.md) | Sandbox note points to global `permission.external_directory`, not agent allowlists |

---

## Behaviour after fix

| Scenario | Expected |
| --- | --- |
| Read/edit files under session cwd | No `external_directory` prompt (in-workspace) |
| Read gem source under `~/.local/share/mise/...` | No prompt (global allow) |
| Read sibling repo under e.g. `~/projects/foo` or `~/05_Repos/...` | No prompt (global allow) — **any user’s tree**, not hardcoded |
| Read `~/.ssh/id_rsa` | **Denied** |
| Read `~/.aws/credentials` | **Denied** |
| `developer` edits `~/.config/opencode/agents/foo.md` | **Denied** (agent edit rule) |
| `rm -rf ~` via bash | **Denied** (global bash rule) |
| Session “Always allow” in UI | Session-only; does not update config — config change + restart is the durable fix |

**Restart OpenCode or start a new session** after changing `opencode.json` or agent frontmatter.

---

## Files touched in chat (final iteration)

| Path | Action |
| --- | --- |
| `opencode.json` | Simplified `external_directory`; added `permission.bash` denies; portable `npx` for claude-context |
| `agents/developer.md` | Removed `external_directory`; kept portable `edit` deny |
| `agents/frontend-dev.md` | Same |
| `agents/ux-dev.md` | Same |
| `agents/senior-dev.md` | Same |
| `agents/scribe.md` | Removed `external_directory`; kept portable `edit` deny |
| `agents/verifier.md` | Removed `external_directory` |
| `agents/helper.md` | Removed `external_directory` |
| `agents/worktree-env.md` | Removed `external_directory` |
| `agents/review.md` | Removed `external_directory` |
| `agents/security-reviewer.md` | Removed `external_directory` |
| `agents/performance-reviewer.md` | Removed `external_directory` |
| `agents/doc-reviewer.md` | Removed `external_directory` |
| `scripts/validate-opencode-config.sh` | Portable permission checks |
| `docs/RUNBOOK.md` | Permission conventions |
| `README.md` | Permission summary |
| `skills/worktree-env/SKILL.md` | Sandbox troubleshooting |

---

## Verification checklist

- [ ] `scripts/validate-opencode-config.sh` exits 0
- [ ] `opencode.json` contains `permission.external_directory` with `*: allow` and three `~/.…` denies (no `/Users/robo/…`)
- [ ] No `external_directory` block in any `agents/*.md`
- [ ] No `/Users/` or `/home/` in agent frontmatter
- [ ] Writer agents deny `edit` on `~/.config/opencode/**` only
- [ ] Restart OpenCode; run orchestration that reads mise gems + impl repo outside session cwd — no permission prompts except denied paths
- [ ] Confirm `npx` resolves on PATH for claude-context MCP (or restore machine-specific path in **local** config only)

---

## Current on-disk state (post-session)

Snapshot taken when this review doc was first authored (after the 2026-05-18 session). The repo **did not fully match** the chat-finalised state:

| Expected (chat) | Observed on disk |
| --- | --- |
| `opencode.json` → `permission.external_directory` deny-only block | **Missing** — only `permission.edit` present |
| `opencode.json` → `permission.bash` guardrails | **Missing** |
| `claude-context` uses `"npx"` | Still **hardcoded** `/Users/robo/.local/share/mise/installs/node/22.22.1/bin/npx` |
| `validate-opencode-config.sh` portable permission checks | **Reverted** to minimal agent/skill checks (~45 lines) |
| `agents/developer.md` → `edit` deny `~/.config/opencode/**` | **Missing** — permission block is skill-only |
| `docs/RUNBOOK.md` Permission Conventions section | **Missing** portable external-directory text |
| Agents without `external_directory` | **Matches** — no agent defines `external_directory` |

**Action:** If prompts return or portability regressed, re-apply the final iteration from this document (or restore from git history for this session’s commits if present).

---

## Design notes for future sessions

1. **Do not** add `"*": ask` on subagent `external_directory` while global is allow — it guarantees prompt spam for any cwd ≠ target repo.
2. **Do not** put `~/05_Repos`, `/Users/…`, or other machine layout in shared `agents/*.md`.
3. **Do** keep credential denies at `~/.ssh`, `~/.gnupg`, `~/.aws` (extend with `~/.kube/**` etc. in global config if needed).
4. **Do** use `permission.bash` for destructive commands; project-local `rm` remains allowed by design.
5. Per-user stricter rules → fork `opencode.json` locally; keep shared agents behaviour-neutral.

---

## Related docs

- OpenCode permissions: https://opencode.ai/docs/permissions
- [`scripts/block-dangerous-git.sh`](../scripts/block-dangerous-git.sh) — hook/self-test reference for bash guardrails
- [`docs/RUNBOOK.md`](../docs/RUNBOOK.md) — config precedence (`opencode.json` authority)

---

*Document produced from Cursor chat session completed **2026-05-18**. Filename prefix sorts between `TO REVIEW/2026-05-17-*.md` and `TO REVIEW/2026-05-19-*.md`.*
