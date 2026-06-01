# 2026-05-18 — External directory permissions (`/tmp` and `~/05_Repos`)

**Session scope:** Diagnose and resolve OpenCode “Access external directory” permission prompts for system temp (`/tmp`) during integration testing, and for implementation-repo paths under `~/05_Repos/...` when review/architect sub-agents read across repos.

**Status:** Finalised in chat (**2026-05-18**). **Verify on disk before merge** — `opencode.json` may have diverged since this session (see [§10 Current on-disk state](#10-current-on-disk-state-post-session)).

---

## Session metadata (Cursor chat)

| Field | Value |
| --- | --- |
| **Document date / filename prefix** | `2026-05-18` — matches **Cursor chat creation date**, not the date the TO REVIEW doc was written later |
| **Cursor chat created** | **2026-05-18 13:50:38 BST** |
| **Cursor transcript ID** | `30cb06a0-927f-413c-9ffc-23f4cc2b08d7` |
| **Transcript path** | `~/.cursor/projects/Users-robo-config-opencode/agent-transcripts/30cb06a0-927f-413c-9ffc-23f4cc2b08d7/30cb06a0-927f-413c-9ffc-23f4cc2b08d7.jsonl` |
| **Workspace during session** | `/Users/robo/.config/opencode` |
| **Config file edited** | `opencode.json` (global OpenCode config) |
| **Agents / skills edited** | **None** — permission-only session |
| **User decisions** | (1) Allow `/tmp` for integration testing; (2) Allow `~/05_Repos/**` so review/architect sub-agents are not blocked reading sibling impl repos |

### Chat timeline (implementation order)

| Step | User prompt (summary) | Action taken |
| --- | --- | --- |
| 1 | Why `/tmp` permission prompt? Is it OpenCode cache? | Diagnosis only — explained repo-local `tmp/` vs system `/tmp` |
| 2 | Integration testing — allow `/tmp` | Added `"/tmp/**": "allow"` to `permission.external_directory` |
| 3 | Review sub-agent blocked on `blocshed-web/app/javascript/controllers` | Diagnosis + added `"~/05_Repos/**": "allow"` |
| 4 | (Later) TO REVIEW documentation | This file |

---

## Executive summary

| Topic | Outcome |
| --- | --- |
| `/tmp` permission prompt | Not OpenCode’s repo-local `tmp/` cache — system temp used by integration tests, shell tools, MCP, and package managers. |
| `~/05_Repos/.../blocshed-web/...` prompt | “External” means **outside the session workspace root**, not off-machine. Review sub-agents hit real impl-repo paths while the session may be rooted elsewhere (e.g. config repo or spec repo). |
| Config fix (chat) | Added explicit `permission.external_directory` allows for `/tmp/**` and `~/05_Repos/**` in global `opencode.json`. |
| Repo-local `tmp/` | Unchanged — still project-relative (`tmp/feature-context.md`, etc.); documented separately in upgrade/onboarding docs. |
| Sub-agent overrides | **No** `external_directory` blocks in `agents/*.md` at session time — global config is the lever. |

---

## 1. Problem: `/tmp` access required

### 1.1 Symptom (verbatim UI)

```text
Permission required
Access external directory /tmp
Patterns
- /tmp/*
```

Observed in context of **integration testing** (user confirmed: “Looks like its todo with integration testing”).

### 1.2 Investigation

- **`opencode.json` had no `/tmp` reference** before the fix.
- **Repo workflow uses `tmp/` (relative)** — e.g. `OUT="tmp/feature-context.md"` and `mkdir -p tmp` in the feature-context hydration script (installed to target repos as `bin/feature-context`). That lives **inside the project**, not at macOS `/tmp`.
- **System `/tmp`** is used by:
  - Integration tests (DB fixtures, sockets, temp files)
  - Shell helpers (`mktemp`, redirects, `$TMPDIR`-adjacent tooling)
  - MCP / subprocess startup (`npx`, `uvx`, local servers in config)
  - Language runtimes and installers during cache/extract

**Conclusion:** The prompt was for **OS-level temp**, not OpenCode’s documented in-repo scratch folder.

### 1.3 MCP / tooling context (why `/tmp` appears)

At session time, `opencode.json` enabled local MCP servers that commonly touch temp dirs during startup:

```json
"claude-context": {
  "type": "local",
  "enabled": true,
  "command": [
    "/Users/robo/.local/share/mise/installs/node/22.22.1/bin/npx",
    "-y",
    "@zilliz/claude-context-mcp@latest"
  ]
},
"dash-api": {
  "type": "local",
  "command": [
    "uvx",
    "--from",
    "git+https://github.com/Kapeli/dash-mcp-server.git",
    "dash-mcp-server"
  ],
  "enabled": true
}
```

The **review** agent uses `claude-context` for code discovery (`get_indexing_status`, `search_code`, `find_files`) before falling back to bash/`rg` — see `agents/review.md` § Claude Context Readiness Gate.

Handoff skill also documents system temp via `mktemp`:

```markdown
1. `HANDOFF_PATH=$(mktemp -t handoff-XXXXXX.md)` — capture the path.
```

(`skills/handoff/SKILL.md` — architect has `bash: true`; orchestrate does not.)

---

## 2. Problem: `~/05_Repos/.../blocshed-web` access required

### 2.1 Symptom (verbatim UI)

During **review** (sub-agent), OpenCode showed:

```text
Permission required
Access external directory ~/05_Repos/01_PROJECTS/apps/blocs/blocshed/blocshed-web/app/javascript/controllers
Patterns
- /Users/robo/05_Repos/01_PROJECTS/apps/blocs/blocshed/blocshed-web/app/javascript/controllers/*
```

User goal: architect/review agents should have **full read** across implementation repos without stalling the review pipeline.

### 2.2 Why it appears as “external”

OpenCode treats **external directory** as any path **outside the current session workspace root** (the directory OpenCode was started in), not “outside the machine.”

Typical layout:

| Session root (cwd) | Path agents need | Treated as |
| --- | --- | --- |
| `~/.config/opencode` | `~/05_Repos/.../blocshed-web/...` | **External** |
| `blocshed-spec` | `blocshed-web/app/javascript/...` | **External** (sibling repo) |
| `blocshed-web` | `app/javascript/controllers/...` | Internal |

Review and cross-repo orchestration often **follow absolute or sibling-repo paths** while the workspace is spec, config, or parent app folder — hence the prompt even though the path is the user’s own code.

This is **not** a bug in the review sub-agent logic; it is the sandbox boundary between workspace root and target repo paths.

### 2.3 Why explicit allow despite `"*": "allow"`

At session time, global `opencode.json` already had:

```json
"external_directory": {
  "*": "allow",
  ...
}
```

Prompts still appeared because:

1. Some OpenCode builds treat paths outside session cwd as a **separate check** that ignores or does not inherit the global wildcard.
2. **Sub-agent frontmatter** can override global rules (see companion doc [`2026-05-18-external-directory-permission-portability.md`](2026-05-18-external-directory-permission-portability.md) — later same-day refactor removed per-agent `external_directory: ask` overrides).
3. UI may show a **pattern-specific** allow dialog even when a broad rule exists — explicit `/tmp/**` and `~/05_Repos/**` entries make intent clear and improve first-match behaviour.

**This session’s fix:** add **explicit** allows for the two path classes that blocked the user, without changing agent files.

---

## 3. Implementation — exact changes (AI recreation playbook)

### 3.1 File and scope

| Item | Value |
| --- | --- |
| **File** | `/Users/robo/.config/opencode/opencode.json` |
| **Section** | top-level `"permission"` → `"external_directory"` |
| **Do not edit** | `agents/*.md`, `skills/*`, review sub-agent definitions |

### 3.2 `opencode.json` BEFORE this chat (baseline at first edit)

Immediately before the `/tmp` change, `permission.external_directory` looked like this (lines ~6–13):

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
    "package-lock.json": "deny",
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
}
```

*(Note: `permission.edit` block above reflects state at session start; current repo may differ — see §10.)*

### 3.3 Change 1 — allow `/tmp/**` (integration testing)

**Trigger:** User confirmed integration tests need system temp.

**Exact search/replace applied in chat:**

```diff
       "~/.aws/**": "deny",
+      "/tmp/**": "allow",
       "~/.config/**": "ask",
```

**Resulting snippet after change 1:**

```json
    "external_directory": {
      "*": "allow",
      "~/.ssh/**": "deny",
      "~/.gnupg/**": "deny",
      "~/.aws/**": "deny",
      "/tmp/**": "allow",
      "~/.config/**": "ask",
      "~/.config/opencode/**": "allow"
    },
```

### 3.4 Change 2 — allow `~/05_Repos/**` (cross-repo review reads)

**Trigger:** Review sub-agent blocked reading `blocshed-web/app/javascript/controllers` while session cwd was not that repo.

**Exact search/replace applied in chat:**

```diff
       "/tmp/**": "allow",
+      "~/05_Repos/**": "allow",
       "~/.config/**": "ask",
```

### 3.5 `opencode.json` AFTER both changes (final session target)

Full `permission.external_directory` block as left at end of chat:

```json
"permission": {
  "external_directory": {
    "*": "allow",
    "~/.ssh/**": "deny",
    "~/.gnupg/**": "deny",
    "~/.aws/**": "deny",
    "/tmp/**": "allow",
    "~/05_Repos/**": "allow",
    "~/.config/**": "ask",
    "~/.config/opencode/**": "allow"
  },
  "edit": {
    "*": "allow",
    "opencode.json": "ask",
    "package-lock.json": "deny",
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
}
```

### 3.6 Optional hardening (not applied in chat; add if `~` fails to expand)

If prompts persist with tilde paths, duplicate the projects allow with an absolute prefix:

```json
"/Users/robo/05_Repos/**": "allow"
```

Place it **next to** `"~/05_Repos/**": "allow"` (same specificity tier, before any wildcard `ask`).

### 3.7 Validation command (run after edits)

```bash
node -e "JSON.parse(require('fs').readFileSync('/Users/robo/.config/opencode/opencode.json','utf8')); console.log('ok')"
```

Expected output: `ok`

### 3.8 What was explicitly NOT changed

- No edits to `agents/review.md`, `agents/architect.md`, or other agent frontmatter.
- No new skills or rules files.
- No changes to repo-local `tmp/` gitignore or `bin/feature-context` scripts.
- No Cursor IDE settings — OpenCode config only.

---

## 4. Distinction: repo `tmp/` vs system `/tmp`

| Location | Purpose | Permission issue? |
| --- | --- | --- |
| `<repo>/tmp/` | OpenCode scratch (`feature-context.md`, handoffs, QA scratch) | Usually **internal** if workspace is that repo |
| `/tmp/` (system) | Tests, MCP, shell, runtime temp | **External** unless explicitly allowed |

Repo-local hydration pattern (from spec-repo tooling docs):

```bash
OUT="tmp/feature-context.md"
mkdir -p tmp
```

Installed via `setup-skills` / `link-spec-repo` as `bin/feature-context`; `tmp/` appended to `.gitignore`.

References in this config repo:

- `docs/upgrade-spec/onboarding-supplement.md` — `tmp/feature-context.md` hydration flow
- `bin/link-spec-repo` — appends `tmp/` to `.gitignore`
- `skills/handoff/SKILL.md` — `mktemp -t handoff-XXXXXX.md` (system temp)

---

## 5. Review agent context (why cross-repo reads happen)

`agents/review.md` is read-only (`write: false`, `edit: false`) but has `bash: true` and delegates to specialist reviewers. It instructs use of **claude-context** MCP for code discovery across the workspace path, with bash/`rg` fallback.

Relevant frontmatter (unchanged in this session):

```yaml
---
description: Planning specialist for review plans
mode: subagent
model: openrouter/deepseek/deepseek-v4-flash
tools:
  write: false
  edit: false
  bash: true
  skill: true
permission:
  edit: deny
  skill: { "review": "allow" }
  task:
    "*": deny
    security-reviewer: allow
    performance-reviewer: allow
    doc-reviewer: allow
---
```

When orchestration runs from **spec** or **config** repo but the review target is **blocshed-web** under `~/05_Repos/...`, tool reads hit **external_directory** unless allowed globally (this session) or the session is opened with impl repo as cwd.

---

## 6. Cursor vs OpenCode

| Layer | Applies `opencode.json`? | Notes |
| --- | --- | --- |
| **OpenCode CLI / desktop** | Yes | `permission.external_directory` in global config |
| **Cursor agent sandbox** | **Separate** | May still show “Access external directory” and require one-time UI approval for `/tmp/*` or project paths |

Changes in this session target **OpenCode** only.

---

## 7. Operational recommendations

1. **Open session with impl repo as root** when doing focused review on one app — fewer external prompts.
2. **Keep `~/05_Repos/**` allow** when working from spec/config/meta repos and pointing agents at multiple impl checkouts.
3. **Keep `/tmp/**` allow** if integration tests or MCP-heavy flows run inside OpenCode sessions.
4. Reconcile with [`2026-05-18-external-directory-permission-portability.md`](2026-05-18-external-directory-permission-portability.md) if migrating to deny-only portable model — that later session **removed** hardcoded `~/05_Repos` from shared config in favour of global `"*": "allow"` + credential denies only.

---

## 8. Files touched in chat

| File | Change |
| --- | --- |
| `opencode.json` | Added `permission.external_directory` entries: `"/tmp/**": "allow"`, `"~/05_Repos/**": "allow"` |

No other files modified during implementation turns.

---

## 9. Verification checklist

- [ ] Confirm `opencode.json` contains `permission.external_directory` with `/tmp/**` and `~/05_Repos/**` allows (or portable equivalent if merged with portability doc)
- [ ] Run JSON parse validation (§3.7)
- [ ] Re-run integration tests in OpenCode session — no `/tmp` prompt
- [ ] Run review/architect flow against `blocshed-web` paths from spec or config workspace — no stall on `app/javascript/controllers`
- [ ] Sensitive paths still denied: `~/.ssh`, `~/.gnupg`, `~/.aws`
- [ ] `~/.config/**` still `ask` except `~/.config/opencode/**` allow
- [ ] If using Cursor agent on same paths, approve once in Cursor UI if prompted separately

---

## 10. Current on-disk state (post-session)

At last documentation pass, **`opencode.json` had diverged** from the session target:

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

The entire `permission.external_directory` block (including `/tmp/**` and `~/05_Repos/**`) was **absent**. Re-apply §3.5 before expecting fixes to take effect.

---

## 11. Related docs (same folder / stack)

| Document | Relationship |
| --- | --- |
| [`2026-05-18-external-directory-permission-portability.md`](2026-05-18-external-directory-permission-portability.md) | Same day — broader refactor; may supersede hardcoded `~/05_Repos` |
| [`2026-05-18-unattended-execution-permissions-and-opencode-config-access.md`](2026-05-18-unattended-execution-permissions-and-opencode-config-access.md) | Same day — execution-lane bash + OpenCode config access |
| [`2026-05-16-warp-worktree-permission-flow-adjustments.md`](2026-05-16-warp-worktree-permission-flow-adjustments.md) | Earlier worktree permission baseline |
| [`2026-05-17-subagent-bash-permissions-and-orchestrator-delegation.md`](2026-05-17-subagent-bash-permissions-and-orchestrator-delegation.md) | Cross-references this doc for external path reads |

Onboarding: `docs/upgrade-spec/onboarding-supplement.md` — `tmp/feature-context.md` hydration.

---

## 12. One-shot AI prompt (recreate this session)

Use this verbatim-ish prompt in a fresh agent session to reproduce the implementation:

```text
In ~/.config/opencode/opencode.json, under permission.external_directory:

1. After "~/.aws/**": "deny", add "/tmp/**": "allow" (integration tests use system /tmp).
2. After "/tmp/**": "allow", add "~/05_Repos/**": "allow" (review sub-agents read sibling impl repos like blocshed-web when session cwd is spec or config repo).

Keep existing deny rules for ~/.ssh, ~/.gnupg, ~/.aws and ask rule for ~/.config/** with allow for ~/.config/opencode/**.
Do not edit agents/*.md or skills.
Validate with: node -e "JSON.parse(require('fs').readFileSync('opencode.json','utf8')); console.log('ok')"
```

Expected blocking symptoms if not applied:

```text
Access external directory /tmp
Access external directory ~/05_Repos/01_PROJECTS/apps/blocs/blocshed/blocshed-web/app/javascript/controllers
```
