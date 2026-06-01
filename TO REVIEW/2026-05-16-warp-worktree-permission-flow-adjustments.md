# 2026-05-16 — Warp worktree permission flow adjustments

**Cursor chat created:** Saturday, 16 May 2026, 20:50 UTC+1  
**Cursor transcript:** [`456a6e3e-f208-453f-8922-766797b745aa`](456a6e3e-f208-453f-8922-766797b745aa)  
**Filename date rule:** Use the **chat creation date** (`2026-05-16`), not the date of later documentation edits.

**Session scope:** Diagnose why OpenCode permission prompts stall orchestration when using Warp git worktrees; adjust global and execution-agent permissions so routine in-repo work and common test/build commands proceed without mid-run freezes, while keeping secrets, keys, and coordinator agents guarded.

**Status:** Finalised in chat (2026-05-16). **Verify on disk before merge** — at documentation time the repository had reverted to pre-session permission blocks (see [§12 Current on-disk state](#12-current-on-disk-state-2026-05-16)).

---

## Executive summary

| Topic | Outcome |
| --- | --- |
| Warp worktrees vs OpenCode | Worktrees are **not** the root cause. Prompts come from OpenCode permission policy. Worktrees add edge cases: `.env` symlink paths resolve outside the worktree cwd; git internals and main-checkout paths can trigger `external_directory` checks. |
| Overnight / unattended stalls | User requirement: agents working inside the active repo should not pause on routine edits and test commands. Coordinator layer (`architect`, `orchestrate`) stays read-only / delegation-only. |
| Global `opencode.json` | Allow normal workspace edits (`"*": allow`); ask before changing `opencode.json`; deny `.env*` and key material at all depths; add `external_directory` allow with sensitive-home denies; remove global `package-lock.json` deny. |
| Execution agents | Explicit `edit` + `bash` policies on `developer`, `frontend-dev`, `senior-dev`, `ux-dev` — allow common test/build/git-read commands; deny destructive shell; keep env/key edits denied. |
| Worktree bootstrap | `worktree-env` agent gets `bash` allows for `ln -sfn` / `readlink` / `git rev-parse` and `external_directory` access to main checkout (with credential-path denies). |
| Docs | `README.md` permission summary updated; `skills/worktree-env/SKILL.md` sandbox note updated to match agent-level bash allow (not edit-on-`.env`). |

---

## 0. Original user request (verbatim)

> I use Warp to run opencode, and you normally use Warp's worktrees as a way to manage different git branch feature branches if I need to. However, I often run into permissions requests on certain files and certain file structures. Is that because I'm using worktrees in Warp, or is that a wider issue of opencode just not having permission? How do I get around this? If opencode is trying to do something that's within the directory or in the working code, I don't think it needs to ask for permission to move ahead, because it can stop the whole process. I could set something off overnight and come back in the morning and find it frozen 20 minutes in and not completed.

**Follow-up in same chat:** User approved permission adjustments so work does not stop mid-flow.

---

## 1. Problem: permission prompts blocking orchestration

### 1.1 User context

- OpenCode is run from **Warp**, often in **git worktrees** for feature branches.
- Permission dialogs appear on certain files and directory structures.
- Runs left overnight can freeze ~20 minutes in when a prompt is not answered.

### 1.2 User expectation

If OpenCode is doing work **within the active directory / working code**, it should not need to stop and ask — the operator cannot babysit every prompt.

### 1.3 Diagnosis (this chat)

| Cause | Explanation |
| --- | --- |
| **OpenCode permission model** | Primary cause. Global and per-agent `permission` rules use `allow`, `ask`, and `deny` with glob patterns; **first match wins** (insertion order matters). |
| **Not Warp-specific** | Warp worktrees are a normal git layout. They do not inherently block file access. |
| **Worktree edge cases** | Linked worktrees symlink `.env` from the main checkout; `worktree-env` touches paths outside session cwd. Git common-dir resolution reads main-repo metadata. |
| **Intentional guardrails** | Pre-session config denied edits to `opencode.json`, lockfiles, `.env*`, and keys globally. Planning agents use read-only bash allowlists with `"*": ask` for unknown commands. |
| **Execution agents under-specified** | `developer`, `frontend-dev`, `senior-dev`, and `ux-dev` had tools enabled but **no explicit** `permission.edit` / `permission.bash` blocks — behaviour fell through to defaults and global denies, causing unpredictable prompts. |
| **OpenCode defaults (reference)** | Without config, most permissions default to `allow`; `external_directory` defaults to `ask`. `.env` reads are denied by default. See [OpenCode permissions docs](https://opencode.ai/docs/permissions). |

### 1.4 Relationship to other TO REVIEW docs (later sessions)

This session is a **targeted, balanced** adjustment (allow in-repo work + routine commands; keep secret denies). Related but distinct sessions:

| Document | Focus |
| --- | --- |
| [`2026-06-01-unattended-execution-permissions-and-opencode-config-access.md`](2026-06-01-unattended-execution-permissions-and-opencode-config-access.md) | Wildcard `bash: { "*": allow }` on execution lane; `external_directory: ask` with explicit OpenCode config allows |
| [`2026-05-18-external-directory-permissions.md`](2026-05-18-external-directory-permissions.md) | `/tmp/**` and `~/05_Repos/**` allows in global config |
| [`2026-06-01-external-directory-permission-portability.md`](2026-06-01-external-directory-permission-portability.md) | Remove agent-level `external_directory`; single global deny-only block |

**This chat** chose a middle path: global `external_directory: { "*": allow }` with credential denies (not full wildcard bash on all execution agents). Reconcile with the above before merge if policies conflict.

---

## 2. Design principles (finalised in chat)

1. **Coordinators stay guarded** — `architect` and `orchestrate` unchanged: no direct file writes; orchestrate delegates shell to subagents.
2. **Execution lane gets explicit allows** — Normal source edits and common test/build/read-only git commands should not prompt.
3. **Secrets stay denied** — `.env`, `.env.*`, `*.pem`, `*.key` at root and nested paths (`**/.env`, etc.).
4. **Config edits ask, not deny** — `opencode.json` changes prompt once (`ask`) instead of hard `deny`, so intentional config updates are possible.
5. **Lockfiles no longer globally blocked** — Removed `package-lock.json: deny` from global edit rules (dependency lock updates during implementation no longer hard-fail).
6. **Worktree `.env` via bash only** — `worktree-env` creates symlinks with `ln -sfn` through bash; never reads or writes secret contents via edit tool.
7. **Dangerous shell still denied** — `rm -rf *`, `sudo *`, `chmod 777`, `curl|sh` patterns blocked on execution agents that received bash rules.

---

## 3. AI recreation guide (apply in order)

Use this section to re-apply the chat changes mechanically. Each step includes the **exact target state** after all patches (including the nested `.env`/key hardening pass).

### Step 1 — Replace `opencode.json` `permission` block

**Find** the existing `"permission": { ... }` object (currently edit-only denies).

**Replace entire `permission` value** with:

```json
  "permission": {
    "external_directory": {
      "*": "allow",
      "~/.ssh/**": "deny",
      "~/.gnupg/**": "deny",
      "~/.aws/**": "deny",
      "~/.config/**": "ask",
      "~/.config/opencode/**": "allow"
    },
    "edit": {
      "*": "allow",
      "opencode.json": "ask",
      "*.pem": "deny",
      "*/*.pem": "deny",
      "**/*.pem": "deny",
      "*.key": "deny",
      "*/*.key": "deny",
      "**/*.key": "deny",
      ".env": "deny",
      ".env.*": "deny",
      "*/.env": "deny",
      "*/.env.*": "deny",
      "**/.env": "deny",
      "**/.env.*": "deny"
    }
  },
```

**Removed from pre-session config:** `"package-lock.json": "deny"` and `"opencode.json": "deny"` (replaced with ask).

Validate JSON:

```bash
python3 -m json.tool opencode.json >/dev/null
```

---

### Step 2 — `agents/developer.md` frontmatter

**Find** (pre-session):

```yaml
permission:
  skill: { "developer": "allow", "preflight": "allow", "debug-fix": "allow", "zoom-out": "allow", "caveman": "allow" }
---
```

**Replace with** (insert `edit` + `bash` before closing `---`):

```yaml
permission:
  skill: { "developer": "allow", "preflight": "allow", "debug-fix": "allow", "zoom-out": "allow", "caveman": "allow" }
  edit:
    "*": allow
    "opencode.json": ask
    "*.pem": deny
    "*/*.pem": deny
    "**/*.pem": deny
    "*.key": deny
    "*/*.key": deny
    "**/*.key": deny
    ".env": deny
    ".env.*": deny
    "*/.env": deny
    "*/.env.*": deny
    "**/.env": deny
    "**/.env.*": deny
  bash:
    "*": ask
    "pwd": allow
    "ls": allow
    "ls *": allow
    "rg": allow
    "rg *": allow
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
    "npm test": allow
    "npm test *": allow
    "npm run *": allow
    "npm install": allow
    "npm install *": allow
    "pnpm *": allow
    "yarn *": allow
    "bun *": allow
    "npx tsc *": allow
    "python -m pytest *": allow
    "pytest *": allow
    "go test *": allow
    "cargo test *": allow
    "make test": allow
    "make test *": allow
    "rm -rf *": deny
    "sudo *": deny
    "chmod 777 *": deny
    "chmod a+rwx *": deny
    "curl *|*sh*": deny
    "wget *|*sh*": deny
---
```

---

### Step 3 — `agents/frontend-dev.md` frontmatter

Same as `developer` **plus one extra bash allow** for Vite:

```yaml
permission:
  skill: { "frontend-dev": "allow" }
  edit:
    "*": allow
    "opencode.json": ask
    "*.pem": deny
    "*/*.pem": deny
    "**/*.pem": deny
    "*.key": deny
    "*/*.key": deny
    "**/*.key": deny
    ".env": deny
    ".env.*": deny
    "*/.env": deny
    "*/.env.*": deny
    "**/.env": deny
    "**/.env.*": deny
  bash:
    "*": ask
    "pwd": allow
    "ls": allow
    "ls *": allow
    "rg": allow
    "rg *": allow
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
    "npm test": allow
    "npm test *": allow
    "npm run *": allow
    "npm install": allow
    "npm install *": allow
    "pnpm *": allow
    "yarn *": allow
    "bun *": allow
    "npx tsc *": allow
    "npx vite *": allow
    "python -m pytest *": allow
    "pytest *": allow
    "make test": allow
    "make test *": allow
    "rm -rf *": deny
    "sudo *": deny
    "chmod 777 *": deny
    "chmod a+rwx *": deny
    "curl *|*sh*": deny
    "wget *|*sh*": deny
---
```

---

### Step 4 — `agents/senior-dev.md` frontmatter

Identical to **`developer`** (Step 2), except keep existing skill line:

```yaml
permission:
  skill: { "senior-dev": "allow" }
  edit:
    # … same edit block as developer …
  bash:
    # … same bash block as developer …
---
```

Use the full blocks from Step 2 verbatim under `senior-dev`.

---

### Step 5 — `agents/ux-dev.md` frontmatter

**Find** (pre-session):

```yaml
permission:
  skill: { "ux-dev": "allow" }
---
```

**Replace with:**

```yaml
permission:
  skill: { "ux-dev": "allow" }
  edit:
    "*": deny
    ".prototype/**": allow
    "*/.prototype/**": allow
    "*.pem": deny
    "*/*.pem": deny
    "**/*.pem": deny
    "*.key": deny
    "*/*.key": deny
    "**/*.key": deny
    ".env": deny
    ".env.*": deny
    "*/.env": deny
    "*/.env.*": deny
    "**/.env": deny
    "**/.env.*": deny
  bash:
    "*": ask
    "pwd": allow
    "ls": allow
    "ls *": allow
    "rg": allow
    "rg *": allow
    "git status": allow
    "git status *": allow
    "git diff": allow
    "git diff *": allow
    "npm test": allow
    "npm test *": allow
    "npm run *": allow
    "pnpm *": allow
    "yarn *": allow
    "bun *": allow
    "rm -rf *": deny
    "sudo *": deny
    "chmod 777 *": deny
    "chmod a+rwx *": deny
    "curl *|*sh*": deny
    "wget *|*sh*": deny
---
```

---

### Step 6 — `agents/worktree-env.md` frontmatter

**Find** (pre-session):

```yaml
permission:
  edit: deny
  skill: { "worktree-env": "allow" }
---
```

**Replace with:**

```yaml
permission:
  edit: deny
  external_directory:
    "*": allow
    "~/.ssh/**": deny
    "~/.gnupg/**": deny
    "~/.aws/**": deny
  bash:
    "*": ask
    "pwd": allow
    "git rev-parse *": allow
    "test *": allow
    "readlink *": allow
    "ln -sfn *": allow
  skill: { "worktree-env": "allow" }
---
```

**Runtime command this enables** (from skill; do not paste `.env` contents):

```bash
cd "$(git rev-parse --show-toplevel)"
ln -sfn "$source_env" "$target"
```

Where `$source_env` is main checkout `.env` and `$target` is worktree root `.env`.

---

### Step 7 — `README.md` line edit

**Find:**

```markdown
Global **`instructions`** pull in [`rules/`](rules/). Global **`permission`** in `opencode.json` blocks edits to `opencode.json`, lockfiles, `.env*`, and keys.
```

**Replace with:**

```markdown
Global **`instructions`** pull in [`rules/`](rules/). Global **`permission`** in `opencode.json` allows normal workspace edits, asks before changing `opencode.json`, and denies `.env*` / key material; execution agents also allow routine test/build commands while keeping dangerous shell commands blocked.
```

---

### Step 8 — `skills/worktree-env/SKILL.md` Permissions section

**Find:**

```markdown
- If `ln` is **denied by the sandbox**, add under **`agents/worktree-env.md`** `permission.edit` with `"*": deny` and `".env": allow` at repo root (mirror `scribe` patterns), then retry—or run the same `ln` command manually in a terminal.
```

**Replace with:**

```markdown
- If `ln` is **denied by the sandbox**, ensure **`agents/worktree-env.md`** allows `bash` for `ln -sfn *` and `external_directory` for the main checkout path, then retry—or run the same `ln` command manually in a terminal.
```

---

### Step 9 — Validate

```bash
cd ~/.config/opencode   # or repo root

python3 -m json.tool opencode.json >/dev/null

git diff --check -- opencode.json README.md \
  agents/developer.md agents/frontend-dev.md agents/senior-dev.md \
  agents/ux-dev.md agents/worktree-env.md skills/worktree-env/SKILL.md
```

Expected: both commands exit 0.

---

## 4. Global changes — `opencode.json` (reference)

### 4.1 Before (pre-session)

```json
"permission": {
  "edit": {
    "opencode.json": "deny",
    "package-lock.json": "deny",
    "*.pem": "deny",
    "*.key": "deny",
    ".env": "deny",
    ".env.*": "deny"
  }
}
```

No `external_directory` block.

### 4.2 After (final chat state)

See [Step 1](#step-1--replace-opencodejson-permission-block).

### 4.3 Rationale

| Rule | Why |
| --- | --- |
| `external_directory: "*": allow` | Worktree main-checkout paths and cross-repo reads should not stall on every external path. |
| Credential denies | `~/.ssh`, `~/.gnupg`, `~/.aws` remain blocked. |
| `~/.config/**`: ask | General config may contain secrets; prompt unless explicitly allowed. |
| `~/.config/opencode/**`: allow | Shared skills/scripts live here; execution agents need read/execute without prompt. |
| `edit: "*": allow` | Default permit in-repo source changes. |
| Nested `.env` / key denies | Broad allow must not accidentally permit secrets in subdirectories. |
| `opencode.json`: ask | Safer than deny for harness updates; still requires conscious approval. |
| No `package-lock.json` deny | Lock updates are normal during dependency work. |

---

## 5. Execution agent summary

| Agent | Edit policy | Bash policy | Notes |
| --- | --- | --- | --- |
| `developer` | `*`: allow; secrets denied | Common test/build/git-read allows; `"*": ask` catch-all | Full blocks in §3 Step 2 |
| `frontend-dev` | Same as developer | Same + `npx vite *` | §3 Step 3 |
| `senior-dev` | Same as developer | Same as developer | §3 Step 4 |
| `ux-dev` | Only `.prototype/**` | Lighter bash set (no go/cargo/make) | §3 Step 5 |
| `worktree-env` | deny | `ln -sfn`, `readlink`, `git rev-parse` | §3 Step 6 |
| `architect` | deny (unchanged) | Read-only allowlist (unchanged) | Not modified |
| `orchestrate` | deny; no bash tool (unchanged) | — | Not modified |
| `scribe` | Path-scoped allowlist (unchanged) | — | Not modified |

**Important:** Bash `"*": ask` means commands like `bin/rails test … | head -60` or `/usr/bin/env bash ~/.config/opencode/skills/.../check-plan.sh` may **still prompt**. For fully unattended runs, see [`2026-06-01-unattended-execution-permissions-and-opencode-config-access.md`](2026-06-01-unattended-execution-permissions-and-opencode-config-access.md).

---

## 6. Chat conversation flow (for context)

| Turn | Action |
| --- | --- |
| 1 | User asked: Warp worktrees vs OpenCode permissions; overnight freeze concern |
| 2 | Diagnosis: mostly OpenCode policy; worktree `.env` symlink edge case; recommended balanced permission posture |
| 3 | User approved: "make those permission adjustments" |
| 4 | Patched `opencode.json` — external_directory + broadened edit |
| 5 | Patched `developer`, `frontend-dev`, `senior-dev`, `ux-dev` — edit + bash blocks |
| 6 | Patched `worktree-env` — external_directory + bash for symlink |
| 7 | Patched `README.md`, `skills/worktree-env/SKILL.md` |
| 8 | Second pass: added nested `*/*.pem`, `**/.env`, etc. to all edit blocks |
| 9 | Validated JSON + `git diff --check` + lints |
| 10 | Created this TO REVIEW doc (initially mis-dated 2026-06-01; corrected to chat creation date 2026-05-16) |

---

## 7. Files touched in this chat

| File | Change |
| --- | --- |
| [`opencode.json`](../opencode.json) | Added `external_directory`; broadened `edit` allow with nested secret denies; `opencode.json` → ask; removed `package-lock.json` deny |
| [`agents/developer.md`](../agents/developer.md) | Added `permission.edit` and `permission.bash` blocks |
| [`agents/frontend-dev.md`](../agents/frontend-dev.md) | Same + `npx vite *` |
| [`agents/senior-dev.md`](../agents/senior-dev.md) | Same as developer |
| [`agents/ux-dev.md`](../agents/ux-dev.md) | Prototype-scoped edit + bash allows |
| [`agents/worktree-env.md`](../agents/worktree-env.md) | `external_directory` + targeted bash allows |
| [`README.md`](../README.md) | Updated global permission summary |
| [`skills/worktree-env/SKILL.md`](../skills/worktree-env/SKILL.md) | Updated Permissions (OpenCode) note |

**Not modified:** `agents/architect.md`, `agents/orchestrate.md`, `agents/scribe.md`, `agents/verifier.md`, `scripts/validate-opencode-config.sh`.

---

## 8. Operational guidance

### 8.1 Warp worktree checklist (manual, once per worktree)

If `worktree-env` reports `blocked_regular_file` or `failed_ln`:

1. In the **main checkout**, ensure `.env` exists.
2. In the **worktree root**, remove or back up a real `.env` file if present (not a symlink).
3. Run manually:

```bash
cd /path/to/worktree
ln -sfn /path/to/main/checkout/.env .env
```

4. Re-run orchestrate startup preflight (`worktree-env` → `developer` preflight).

Optional env var when git common-dir layout is non-standard:

```bash
export PREFLIGHT_MAIN_REPO_ROOT=/path/to/main/checkout
```

### 8.2 After applying permission changes

1. **Restart OpenCode** (or start a fresh session) so agent frontmatter and `opencode.json` reload.
2. Run a short orchestration stage with a known test command; confirm no prompt for allowed patterns.
3. Confirm `.env` edits still **deny** on execution agents.
4. If prompts persist on piped/compound commands, consider merging with the unattended wildcard-bash policy in the related doc above.

### 8.3 Residual limitations

| Limitation | Detail |
| --- | --- |
| Bash `"*": ask` | Commands not matching allow patterns still prompt (Rails, pipes, absolute script paths). |
| Shell vs file-tool sandbox | Allowed bash can still mutate paths outside the repo even when `external_directory` restricts file tools. |
| Global vs agent `external_directory` | If agents define their own `external_directory`, they **override** global rules — avoid duplicating conflicting blocks. |
| Pattern ordering | List specific allows/denies **before** wildcard `ask` / `allow` in each permission block. |

---

## 9. Decisions and tradeoffs

| Decision | Rationale | Cost |
| --- | --- | --- |
| Global `external_directory: allow` + credential denies | Unblocks worktree and cross-path reads without per-repo hardcoding | Less restrictive than `"*": ask` on external paths |
| Per-agent bash allowlist (not full wildcard) | Covers common Node/Python/Go/Rust test flows without opening all shell | Novel commands still prompt |
| Remove lockfile global deny | Lock updates are normal during dependency work | Agents can modify lockfiles (review in PR) |
| `opencode.json`: ask | Allows harness fixes with confirmation | One prompt if an agent touches config |
| Keep `.env*` deny at all depths | Secrets must not be written by execution agents | Worktree symlink must use bash `ln`, not edit |

---

## 10. OpenCode permission syntax reference

For another AI applying or extending these rules:

```json
"permission": {
  "edit": "deny",
  "bash": { "git *": "allow", "rm *": "deny", "*": "ask" },
  "external_directory": { "~/secrets/**": "deny", "*": "allow" }
}
```

- Values: `"allow"` | `"ask"` | `"deny"`.
- Agent frontmatter uses YAML (`allow` without quotes is valid in OpenCode agent files).
- **First matching pattern wins** — put specific rules before wildcards.
- Agent-level `permission` overrides / supplements global `opencode.json` for that agent.
- Docs: [opencode.ai/docs/permissions](https://opencode.ai/docs/permissions), [opencode.ai/docs/config](https://opencode.ai/docs/config).

---

## 11. Validation performed in chat

```bash
python3 -m json.tool opencode.json >/dev/null
git diff --check -- opencode.json README.md agents/developer.md agents/frontend-dev.md \
  agents/senior-dev.md agents/ux-dev.md agents/worktree-env.md skills/worktree-env/SKILL.md
```

Both passed. No linter errors reported on changed files.

Post-apply verification:

```bash
grep -A30 '"permission"' opencode.json
grep -l 'bash:' agents/developer.md agents/worktree-env.md
grep 'allows normal workspace edits' README.md
```

---

## 12. Current on-disk state (2026-05-16)

At documentation time, the repository **did not** contain the chat implementation:

| Expected (chat) | Observed on disk |
| --- | --- |
| `opencode.json` → `permission.external_directory` block | **Missing** — only legacy `permission.edit` with deny rules |
| `opencode.json` → `edit: { "*": "allow", … }` | **Missing** — still denies `opencode.json` and `package-lock.json` |
| Agent frontmatter `edit` / `bash` blocks on execution agents | **Missing** — only `permission.skill` entries |
| `worktree-env.md` bash / external_directory | **Missing** |
| Updated README permission line | **Missing** — still mentions lockfile deny |
| Updated `worktree-env` skill Permissions note | **Missing** — still suggests edit-on-`.env` workaround |

**Re-apply using [§3 AI recreation guide](#3-ai-recreation-guide-apply-in-order)** or merge with related permission sessions before treating this work as live.

---

## 13. Acceptance checklist

- [ ] `opencode.json` contains `external_directory` and broadened `edit` rules per §3 Step 1
- [ ] `developer` / `frontend-dev` / `senior-dev` have explicit edit + bash blocks per §3 Steps 2–4
- [ ] `ux-dev` limited to `.prototype/**` edits per §3 Step 5
- [ ] `worktree-env` can run `ln -sfn` without prompt in a linked worktree per §3 Step 6
- [ ] `.env` and key files remain denied for edits at all depths
- [ ] `npm test`, `npm run lint`, `pytest`, etc. run without prompt on execution agents
- [ ] `architect` / `orchestrate` still cannot write files or run unrestricted bash
- [ ] README and worktree-env skill docs match applied policy per §3 Steps 7–8
- [ ] `python3 -m json.tool opencode.json` passes
- [ ] Overnight orchestration run completes at least one multi-stage plan without freezing on permission dialogs
