# 2026-05-18 — External directory permissions (`/tmp` and `~/05_Repos`)

**Session scope:** Diagnose and resolve OpenCode “Access external directory” permission prompts for system temp (`/tmp`) during integration testing, and for implementation-repo paths under `~/05_Repos/...` when review/architect sub-agents read across repos.

**Status:** Finalised in chat (2026-05-18). **Verify on disk before merge** — `opencode.json` may have diverged since this session (e.g. `permission.external_directory` block absent or `permission.edit` rules changed).

---

## Executive summary

| Topic | Outcome |
| --- | --- |
| `/tmp` permission prompt | Not OpenCode’s repo-local `tmp/` cache — system temp used by integration tests, shell tools, MCP, and package managers. |
| `~/05_Repos/.../blocshed-web/...` prompt | “External” means **outside the session workspace root**, not off-machine. Review sub-agents hit real impl-repo paths while the session may be rooted elsewhere (e.g. config repo or spec repo). |
| Config fix (chat) | Added explicit `permission.external_directory` allows for `/tmp/**` and `~/05_Repos/**`. |
| Repo-local `tmp/` | Unchanged — still project-relative (`tmp/feature-context.md`, etc.); documented separately in upgrade/onboarding docs. |

---

## 1. Problem: `/tmp` access required

### 1.1 Symptom

OpenCode showed:

```text
Permission required
Access external directory /tmp
Patterns
- /tmp/*
```

Observed in context of **integration testing** (not general file browsing).

### 1.2 Investigation

- **`opencode.json` had no `/tmp` reference** before the fix.
- **Repo workflow uses `tmp/` (relative)** — e.g. `tmp/feature-context.md` from `templates/bin/feature-context`, gitignored per `setup-skills` / `link-spec-repo`. That lives **inside the project**, not at macOS `/tmp`.
- **System `/tmp`** is used by:
  - Integration tests (DB fixtures, sockets, temp files)
  - Shell helpers (`mktemp`, redirects, `$TMPDIR`-adjacent tooling)
  - MCP / subprocess startup (`npx`, `uvx`, local servers in config)
  - Language runtimes and installers during cache/extract

**Conclusion:** The prompt was for **OS-level temp**, not OpenCode’s documented in-repo scratch folder.

### 1.3 Fix applied in chat

Under `permission.external_directory` in `opencode.json`:

```json
"/tmp/**": "allow"
```

Placed alongside existing deny/ask rules for sensitive home paths (`~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.config/**` with `~/.config/opencode/**` allowed).

---

## 2. Problem: `~/05_Repos/.../blocshed-web` access required

### 2.1 Symptom

During **review** (sub-agent), OpenCode showed:

```text
Permission required
Access external directory ~/05_Repos/01_PROJECTS/apps/blocs/blocshed/blocshed-web/app/javascript/controllers
Patterns
- /Users/robo/05_Repos/01_PROJECTS/apps/blocs/blocshed/blocshed-web/app/javascript/controllers/*
```

User goal: architect/review agents should have **full read** across implementation repos without stalling the review pipeline.

### 2.2 Why it appears as “external”

OpenCode treats **external directory** as any path **outside the current session workspace root**.

Typical layout:

| Session root | Path agents need | Treated as |
| --- | --- | --- |
| `~/.config/opencode` | `~/05_Repos/.../blocshed-web/...` | External |
| `blocshed-spec` | `blocshed-web/app/javascript/...` | External (sibling repo) |
| `blocshed-web` | `blocshed-web/app/javascript/...` | Internal |

Review and cross-repo orchestration often **follow absolute or sibling-repo paths** while the workspace is spec, config, or parent app folder — hence the prompt even though the path is the user’s own code.

This is **not** a bug in the review sub-agent logic; it is the sandbox boundary between workspace root and target repo paths.

### 2.3 Fix applied in chat

Under `permission.external_directory` in `opencode.json`:

```json
"~/05_Repos/**": "allow"
```

Covers `blocshed-web`, sibling impl repos, and other projects under the user’s standard checkout tree without per-repo rules.

---

## 3. Intended `permission.external_directory` block (post-chat)

As agreed and edited in session (merge with whatever is on disk today):

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
  "edit": { ... }
}
```

**Note:** At documentation time, the workspace copy of `opencode.json` may only contain `permission.edit` (no `external_directory` key). Re-apply the block above if prompts persist.

---

## 4. Distinction: repo `tmp/` vs system `/tmp`

| Location | Purpose | Permission issue? |
| --- | --- | --- |
| `<repo>/tmp/` | OpenCode scratch (`feature-context.md`, handoffs, QA scratch) | Usually internal if workspace is that repo |
| `/tmp/` (system) | Tests, MCP, shell, runtime temp | External unless explicitly allowed |

References in this config repo:

- `templates/bin/feature-context` → `OUT="tmp/feature-context.md"`, `mkdir -p tmp`
- `docs/upgrade-spec/onboarding-supplement.md` — `tmp/` gitignore and hydration flow
- `skills/handoff/SKILL.md` — `mktemp -t handoff-XXXXXX.md` (system temp; orchestrate has `bash: false`)

---

## 5. Cursor vs OpenCode

- **`opencode.json` `permission.external_directory`** applies when **OpenCode** enforces that config.
- **Cursor agent “Access external directory”** dialogs are a **separate** sandbox; approving `/tmp/*` or project paths in Cursor may still be required once per pattern even after OpenCode config changes.

---

## 6. Operational recommendations

1. **Re-open session with impl repo as root** when doing focused review on one app — fewer external prompts.
2. **Keep `~/05_Repos/**` allow** when working from spec/config/meta repos and pointing agents at multiple impl checkouts.
3. **Keep `/tmp/**` allow** if integration tests or MCP-heavy flows run inside OpenCode sessions.
4. If `~` expansion ever fails in a build, add a duplicate rule: `"/Users/robo/05_Repos/**": "allow"`.

---

## 7. Files touched in chat

| File | Change |
| --- | --- |
| `opencode.json` | Added `permission.external_directory` entries: `/tmp/**`, `~/05_Repos/**` (and retained prior deny/ask rules as in §3) |

No changes to agents, skills, or review sub-agent definitions — this was **permission configuration only**.

---

## 8. Verification checklist

- [ ] Confirm `opencode.json` contains `permission.external_directory` with `/tmp/**` and `~/05_Repos/**` allows
- [ ] Re-run integration tests in OpenCode session — no `/tmp` prompt (or one-time Cursor approve if using Cursor agent)
- [ ] Run review/architect flow against `blocshed-web` paths from spec or config workspace — no stall on `app/javascript/controllers`
- [ ] Sensitive paths still denied: `~/.ssh`, `~/.gnupg`, `~/.aws`
- [ ] `~/.config/**` still `ask` except `~/.config/opencode/**` allow

---

## 9. Related docs (same folder / stack)

- [`2026-05-18-external-directory-permission-portability.md`](2026-05-18-external-directory-permission-portability.md) — portable deny-only external-directory model (same day, broader refactor)
- [`2026-05-18-unattended-execution-permissions-and-opencode-config-access.md`](2026-05-18-unattended-execution-permissions-and-opencode-config-access.md) — execution-lane bash and OpenCode config access (same day)
- [`2026-05-16-warp-worktree-permission-flow-adjustments.md`](2026-05-16-warp-worktree-permission-flow-adjustments.md) — earlier worktree permission baseline
- Onboarding: `docs/upgrade-spec/onboarding-supplement.md` — `tmp/feature-context.md` hydration
