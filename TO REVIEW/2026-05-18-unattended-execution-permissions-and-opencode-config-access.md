# 2026-05-18 — Unattended execution permissions and OpenCode config access

**Session scope:** Stop OpenCode permission prompts from blocking overnight orchestration runs. Allow execution subagents to run shell commands and read shared OpenCode skills/scripts without user confirmation, while keeping `architect` and `orchestrate` controlled. Tighten external-directory policy so shared config is readable/executable but not silently editable, and document remaining security tradeoffs.

**Status:** Finalised in chat (2026-05-18). **Verify on disk before merge** — agent frontmatter and `scripts/validate-opencode-config.sh` may have diverged since this session (see [Current on-disk state](#current-on-disk-state-2026-05-18)).

---

## Executive summary

| Topic | Outcome |
| --- | --- |
| `check-plan.sh` prompts | Initial fix: narrow `permission.bash` allows for orchestrate-execution plan validation delegated to `developer`. Superseded by wildcard bash allow on execution lane. |
| Unattended overnight runs | Execution/review subagents given `bash: { "*": allow }` so commands like `bin/rails test … \| head -60` no longer stall on per-pattern approval. |
| Primary agents stay guarded | `architect` and `orchestrate` unchanged: no direct bash mutations, delegation-only execution model preserved. |
| Security vs convenience | `external_directory: { "*": ask }` restored (after brief `"*": allow` experiment) with explicit denies for `~/.ssh`, `~/.gnupg`, `~/.aws`. Residual risk: unrestricted bash can still mutate paths outside repo via shell. |
| Shared OpenCode config | Explicit `external_directory` **allow** for `~/.config/opencode/**` and `/Users/robo/.config/opencode/**` on unattended subagents; **edit deny** on write-capable agents for those paths. |
| Pattern ordering | Specific allows/denies listed **before** wildcard `ask` / `allow` so first-match semantics cannot block OpenCode config access. |
| Validator | `scripts/validate-opencode-config.sh` extended to enforce unattended bash policy, external-directory rules, OpenCode config allows, edit denies, and ordering. |

---

## 1. Problem: permission prompts blocking orchestration

### 1.1 Symptoms

During `.plan` execution, OpenCode repeatedly showed permission dialogs, for example:

```text
Permission required
Run check-plan.sh script
$ /usr/bin/env bash /Users/robo/.config/opencode/skills/orchestrate-execution/lib/check-plan.sh ".plan/feature.org-management-ui.md"

Always allow
- /usr/bin/env *
```

Later, during Rails test runs:

```text
Permission required
Run organisations controller tests
$ cd /Users/robo/.warp/worktrees/BlocShed/cobalt-shimmer && bin/rails test test/controllers/organisations_controller_test.rb 2>&1 | head -60

Always allow
- bin/rails *
- head *
```

User requirement: leave agents running unattended (overnight) without mid-task confirmation. Guardrails should live at **orchestrator/architect** level; execution subagents should behave like the operator inside the active git directory.

### 1.2 Root cause

1. **`orchestrate` has no bash tool** — plan validation and shell work is delegated to `developer` via Task (`load: minimal`).
2. **`developer` (and peers) used `permission.bash: { "*": ask }`** with a long per-command allowlist. Any command not on the list (including pipelines, `head`, `/usr/bin/env bash …`, or `cd … && …` compound forms) triggered prompts.
3. **Shared skills live outside the implementation repo** — paths under `~/.config/opencode/skills/…` are **external directory** relative to a worktree session root, so file reads/executes there also prompted even when bash was allowed.

---

## 2. Iteration 1 — Narrow allows for `check-plan.sh`

**Approach:** Add explicit bash allows in `agents/developer.md` for:

- `bash skills/orchestrate-execution/lib/check-plan.sh *`
- `cd * && bash skills/orchestrate-execution/lib/check-plan.sh *`
- `/usr/bin/env bash /Users/robo/.config/opencode/skills/orchestrate-execution/lib/check-plan.sh *`

**Result:** Fixed the immediate plan-validation prompt but did not scale — every new command pattern (`bin/rails`, `head`, pipes, worktree paths) caused another prompt.

---

## 3. Iteration 2 — Unattended execution lane (wildcard bash)

**Approach:** Remove per-command bash allowlists for orchestration **execution and review subagents**. Grant:

```yaml
bash:
  "*": allow
```

**Agents updated in chat:**

| Agent | Bash | Edit | Notes |
| --- | --- | --- | --- |
| `developer` | allow all | `*`: allow (with OpenCode config deny — see §5) | Primary executor |
| `frontend-dev` | allow all | `*`: allow + OpenCode config deny | UI executor |
| `ux-dev` | allow all | `*`: allow + OpenCode config deny | Prototype lane |
| `senior-dev` | allow all | `*`: allow + OpenCode config deny | Escalation |
| `verifier` | allow all | deny (read-only by role) | Evidence gate |
| `scribe` | allow all | `*`: allow + OpenCode config deny | Markdown writer |
| `worktree-env` | allow all | deny | `.env` symlink setup |
| `helper` | allow all | deny | Recovery replanner |
| `review` | allow all | deny | Post-execution review |
| `security-reviewer` | allow all | deny | Nested review |
| `performance-reviewer` | allow all | deny | Nested review |
| `doc-reviewer` | allow all | deny | Nested review |

**Not changed (stay controlled):**

- `architect` — read-only bash allowlist, `edit: deny`
- `orchestrate` — `bash: false`, `edit: deny`, Task delegation only

**Brief experiment (reverted in same session):** `external_directory: { "*": allow }` on execution agents for maximum convenience. User correctly flagged security risk (shell can write outside repo regardless of file-tool permissions).

---

## 4. Iteration 3 — External directory tightening

**Final external-directory model for unattended subagents:**

```yaml
external_directory:
  "~/.config/opencode/**": allow
  "/Users/robo/.config/opencode/**": allow
  "~/.ssh/**": deny
  "~/.gnupg/**": deny
  "~/.aws/**": deny
  "*": ask
```

**Intent:**

| Path class | Policy |
| --- | --- |
| Shared OpenCode config (skills, lib scripts) | **Allow** read/execute without prompt |
| Credential stores | **Deny** |
| Everything else outside session cwd | **Ask** (restricted vs operator shell) |

**Important limitation:** `bash: "*": allow` means a subagent could still run destructive shell against paths outside the repo (e.g. `rm -rf ~/…`). File-tool `external_directory` rules do not sandbox shell. True “repo-only write, read-only elsewhere” needs OS-level sandboxing or a stricter bash policy (which reintroduces prompts).

---

## 5. OpenCode config: read/execute yes, edit no

User requirement: agents may **use** files from `~/.config/opencode` (skills, `check-plan.sh`, github-issue-run helpers) but must not **edit** shared config while working in an implementation repo.

**On write-capable agents** (`developer`, `frontend-dev`, `ux-dev`, `senior-dev`, `scribe`), add **before** wildcard edit allow:

```yaml
edit:
  "~/.config/opencode/**": deny
  "/Users/robo/.config/opencode/**": deny
  "*": allow
```

Read-only agents (`verifier`, reviewers, `helper`, `worktree-env`) already had `edit: deny`.

---

## 6. Pattern ordering (first-match safety)

User asked: if `"*": ask` appears first, will OpenCode prompt before reaching the OpenCode allow?

**Mitigation:** list **specific rules before wildcards** in agent frontmatter:

```yaml
# external_directory — allows and denies BEFORE catch-all ask
external_directory:
  "~/.config/opencode/**": allow
  "/Users/robo/.config/opencode/**": allow
  "~/.ssh/**": deny
  "~/.gnupg/**": deny
  "~/.aws/**": deny
  "*": ask

# edit — denies BEFORE catch-all allow (writers only)
edit:
  "~/.config/opencode/**": deny
  "/Users/robo/.config/opencode/**": deny
  "*": allow
```

Validator checks that OpenCode allow lines precede `"*": ask`, and OpenCode edit deny lines precede edit `"*": allow`.

---

## 7. Validator changes (`scripts/validate-opencode-config.sh`)

Extended in chat (may not match current file on disk):

1. **Read-only planning agents** — still require guarded bash (`architect`, `strategist`, `debugger`, `refactor`, `document`, `designer`). Review family moved to unattended policy.
2. **Unattended execution/review subagents** — must have:
   - `bash: { "*": allow }`
   - `external_directory: { "*": ask }`
   - allows for both OpenCode config path patterns
   - denies for `~/.ssh`, `~/.gnupg`, `~/.aws`
   - OpenCode allow lines **before** external `"*": ask`
3. **Unattended writers** — must deny edits to both OpenCode config path patterns **before** edit `"*": allow`

Run after changes:

```bash
./scripts/validate-opencode-config.sh
```

---

## 8. Operational notes

1. **Restart / re-enter OpenCode** after permission changes — running sessions cache prior rules; “Always allow until restart” applies to UI approvals, not necessarily to updated agent frontmatter until reload.
2. **Config persists on disk** at `~/.config/opencode` — exiting and re-entering loads updated agent markdown on next session start.
3. **Git tracks changes** in the implementation repo; execution agents are expected to commit per stage. Shared OpenCode config edits are intentionally blocked on execution agents.
4. **Related docs** in this folder (follow-on external-directory work):
   - `2026-05-18-external-directory-permissions.md`
   - `2026-06-01-external-directory-permission-portability.md`

---

## 9. Files touched in this chat

| File | Change |
| --- | --- |
| `agents/developer.md` | Unattended bash; external_directory policy; OpenCode config allow + edit deny; ordering |
| `agents/frontend-dev.md` | Same pattern |
| `agents/ux-dev.md` | Same pattern |
| `agents/senior-dev.md` | Same pattern |
| `agents/verifier.md` | Unattended bash; external_directory policy |
| `agents/scribe.md` | Unattended bash; external_directory allow; OpenCode edit deny |
| `agents/worktree-env.md` | Unattended bash; external_directory policy |
| `agents/helper.md` | Unattended bash; external_directory policy |
| `agents/review.md` | Unattended bash; external_directory policy |
| `agents/security-reviewer.md` | Unattended bash; external_directory policy |
| `agents/performance-reviewer.md` | Unattended bash; external_directory policy |
| `agents/doc-reviewer.md` | Unattended bash; external_directory policy |
| `scripts/validate-opencode-config.sh` | Unattended + ordering enforcement |

**Not modified:** `agents/architect.md`, `agents/orchestrate.md`, `opencode.json` (global permission block unchanged in this chat).

---

## 10. Decisions and tradeoffs (final)

| Decision | Rationale | Cost |
| --- | --- | --- |
| Wildcard bash on execution lane | Eliminates prompt death-by-a-thousand-patterns for overnight runs | Shell is not path-sandboxed |
| Keep architect/orchestrate guarded | User wants control at coordinator layer | Coordinators must delegate all shell |
| `external_directory: ask` for non-config paths | Reduces silent cross-repo file tool access | May still prompt on some external reads; bash bypass remains |
| Explicit OpenCode config allow | Skills/scripts live in shared config checkout | Hardcoded `/Users/robo/…` path alongside `~/.config/…` (machine-specific; see portability doc) |
| OpenCode config edit deny on writers | Prevents agents mutating harness while fixing app code | Manual config updates still required in config repo |

---

## 11. Current on-disk state (2026-05-18)

At documentation time, the repository **may not** still contain all frontmatter blocks from this chat — some agent files showed only minimal `permission.skill` entries (bash/external_directory blocks absent), and `scripts/validate-opencode-config.sh` may have reverted to a shorter agent/skill existence check only.

**Before treating this session as merged:**

```bash
grep -l 'external_directory:' agents/*.md
grep -l '"\*": allow' agents/developer.md agents/verifier.md
./scripts/validate-opencode-config.sh
```

If blocks are missing, re-apply §4–§6 from this document or reconcile with the portable external-directory model in `2026-06-01-external-directory-permission-portability.md`.

---

## 12. Acceptance checklist

- [ ] `developer` can run `check-plan.sh` from `~/.config/opencode/skills/orchestrate-execution/lib/` without prompt
- [ ] `developer` can run `bin/rails test …`, piped commands, and worktree `cd … && …` without prompt
- [ ] Access to `~/.config/opencode/skills/**` does not prompt (after OpenCode restart)
- [ ] Other external directories still **ask** (or deny for sensitive paths)
- [ ] Execution agents cannot edit `~/.config/opencode/**` via file tools
- [ ] `architect` / `orchestrate` still cannot run unrestricted bash
- [ ] `./scripts/validate-opencode-config.sh` passes with extended rules (if still present)
