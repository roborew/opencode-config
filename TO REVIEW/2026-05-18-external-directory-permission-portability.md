# 2026-05-18 — External directory permissions: portable deny-only model

**Cursor chat created:** 2026-05-18 (Sunday) 23:18:26 BST — date prefix matches when this Cursor session started.

**Cursor transcript:** [`7acb546f-f3cc-4d5a-b704-27fa39445ab4`](../../.cursor/projects/Users-robo-config-opencode/agent-transcripts/7acb546f-f3cc-4d5a-b704-27fa39445ab4/7acb546f-f3cc-4d5a-b704-27fa39445ab4.jsonl)

**Work completed:** 2026-05-18 — same session (three user turns: mise gem prompt → `~/05_Repos` prompt → portable redesign).

**Session scope:** Fix repeated OpenCode **Permission required → Access external directory** prompts during unattended agent work (Ruby gems under mise, project code under sibling repos), then refactor to a **portable, multi-user-safe** permission model without hardcoded user paths in shared agent config.

**Status:** Design and implementation **finalised in chat**. Re-verify on disk before merge — the repository **has diverged** since this session (see [Current on-disk state](#current-on-disk-state-post-session)).

---

## Executive summary

| Area | Outcome |
| --- | --- |
| **`opencode.json`** | Single source of truth: `permission.external_directory` allow-by-default + credential denies; new `permission.bash` destructive guardrails; portable `npx` for claude-context MCP |
| **12 execution/review agents** | Remove entire `external_directory` blocks (inherit global); remove all `/Users/...` literals |
| **Writer agents (5)** | Keep portable `edit` deny for `~/.config/opencode/**` only |
| **`validate-opencode-config.sh`** | Fail on hardcoded home paths, agent-level `external_directory`, missing global deny-only rules |
| **Docs** | RUNBOOK Permission Conventions, README permission summary, worktree-env skill sandbox note |

---

## User-reported symptoms (verbatim triggers)

### Trigger 1 — Ruby gem / mise toolchain

```text
Permission required
Access external directory ~/.local/share/mise/installs/ruby/3.4.9/lib/ruby/gems/3.4.0/gems/actionview-8.0.2/lib/action_view
Patterns
- /Users/robo/.local/share/mise/installs/ruby/3.4.9/lib/ruby/gems/3.4.0/gems/actionview-8.0.2/lib/action_view/*
```

### Trigger 2 — Implementation repo outside session cwd

```text
Permission required
Access external directory ~/05_Repos/Repos/01_PROJECTS/apps/blocshed/blocshed-web/lib
Patterns
- /Users/robo/05_Repos/Repos/01_PROJECTS/apps/blocshed/blocshed-web/lib/*
```

---

## Root cause (OpenCode permission model)

From [OpenCode permissions docs](https://opencode.ai/docs/permissions):

1. **`external_directory`** applies when any tool touches paths **outside the directory where OpenCode was started** (read, edit, glob, grep, many bash commands).
2. **Agent frontmatter overrides global `opencode.json`.** If a subagent sets `"*": ask`, global `"*": allow` is ignored for that agent.
3. **Pattern matching:** last matching rule wins. Put catch-all `"*"` first, specific rules after — or use deny-only lists with `"*": allow` first.
4. **Home expansion:** `~/…` in patterns expands to the current user’s home; does not make external paths “in workspace.”

| Layer | Pre-fix configuration | Effect |
| --- | --- | --- |
| Global `opencode.json` | `"external_directory": { "*": "allow", … }` | Appeared permissive |
| Subagents (`developer`, `verifier`, `scribe`, reviewers, …) | `"external_directory": { "*": ask, … }` | **Overrides global** — prompt on almost every external read |
| Session cwd | Often spec repo, `~/.config/opencode`, or parent — not impl repo | App source under another path counts as **external** |

The validator **previously required** `"*": ask` on unattended agents (`scripts/validate-opencode-config.sh`), which encoded the prompt spam into CI.

---

## Chat iteration timeline

| Step | User input | Action taken | Kept? |
| --- | --- | --- | --- |
| 1 | mise / actionview prompt | Added `~/.local/share/mise/**` (+ absolute `/Users/robo/…`) to agents + global | **Reverted** |
| 2 | `~/05_Repos/.../blocshed-web/lib` prompt | Added `~/05_Repos/**` (+ absolute) to agents + global | **Reverted** |
| 3 | “No user folder roots in agents — must work for other users” | Portable deny-only model; remove agent `external_directory`; centralize in `opencode.json` | **Final** |

---

## Final design (portable deny-only)

| Concern | Where it lives |
| --- | --- |
| Read/write outside session cwd | **Only** `opencode.json` → `permission.external_directory` |
| Block edits to shared OpenCode config | Agent `permission.edit` → `~/.config/opencode/**`: deny (writers only) |
| Block destructive shell | `opencode.json` → `permission.bash` deny patterns |
| User-specific extra paths | Personal fork of `opencode.json` — **never** shared `agents/*.md` |

---

## Recreation guide (for another AI)

Apply changes in this order. After each major step, run `scripts/validate-opencode-config.sh`.

### Step 1 — Replace `permission` block in `opencode.json`

**Remove** user-specific allows (`~/05_Repos/**`, `/Users/…`, `/tmp/**`, `~/.config/**`: ask, etc.) from `external_directory`.

**Insert** (merge with existing `permission.edit` — do not drop edit rules already on disk):

```json
"permission": {
  "external_directory": {
    "*": "allow",
    "~/.ssh/**": "deny",
    "~/.gnupg/**": "deny",
    "~/.aws/**": "deny"
  },
  "bash": {
    "*": "allow",
    "rm -rf /*": "deny",
    "rm -rf ~/*": "deny",
    "rm -rf ~": "deny",
    "git push * --force*": "deny",
    "git push * -f*": "deny",
    "git reset --hard*": "deny",
    "git clean -fd*": "deny",
    "git clean -f *": "deny",
    "git branch -D *": "deny",
    "git checkout .": "deny",
    "git restore .": "deny"
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
}
```

**Note:** If the repo’s `permission.edit` already uses different keys (e.g. `"opencode.json": "deny"` instead of `"ask"`), keep the **current** edit block and only add `external_directory` + `bash`. The chat session’s global edit block matched the pre-session file (see [Before state](#before-state-at-chat-start)).

#### MCP — `claude-context` command (portable `npx`)

**Before (machine-specific — remove):**

```json
"claude-context": {
  "type": "local",
  "enabled": true,
  "command": [
    "/Users/robo/.local/share/mise/installs/node/22.22.1/bin/npx",
    "-y",
    "@zilliz/claude-context-mcp@latest"
  ]
}
```

**After:**

```json
"claude-context": {
  "type": "local",
  "enabled": true,
  "command": [
    "npx",
    "-y",
    "@zilliz/claude-context-mcp@latest"
  ]
}
```

Requires `npx` on `PATH` when OpenCode starts (see `scripts/agent-run.zsh`, `~/.zshenv`).

---

### Step 2 — Remove `external_directory` from 12 agents

**Target files:**

```text
agents/developer.md
agents/frontend-dev.md
agents/ux-dev.md
agents/senior-dev.md
agents/verifier.md
agents/scribe.md
agents/helper.md
agents/worktree-env.md
agents/review.md
agents/security-reviewer.md
agents/performance-reviewer.md
agents/doc-reviewer.md
```

**Delete entire block** (exact content removed in chat — iteration 1+2 intermediate):

```yaml
  external_directory:
    "~/.config/opencode/**": allow
    "/Users/robo/.config/opencode/**": allow
    "~/.local/share/mise/**": allow
    "/Users/robo/.local/share/mise/**": allow
    "~/05_Repos/**": allow
    "/Users/robo/05_Repos/**": allow
    "~/.ssh/**": deny
    "~/.gnupg/**": deny
    "~/.aws/**": deny
    "*": ask
```

Also remove any standalone line:

```yaml
    "/Users/robo/.config/opencode/**": deny
```

from `permission.edit` sections (portable deny uses tilde form only).

#### Bulk-removal script used in chat

```python
import re
from pathlib import Path

external_block = re.compile(
    r"\n  external_directory:\n"
    r'    "~/.config/opencode/\*\*": allow\n'
    r'    "/Users/robo/.config/opencode/\*\*": allow\n'
    r'    "~/.local/share/mise/\*\*": allow\n'
    r'    "/Users/robo/.local/share/mise/\*\*": allow\n'
    r'    "~/05_Repos/\*\*": allow\n'
    r'    "/Users/robo/05_Repos/\*\*": allow\n'
    r'    "~/.ssh/\*\*": deny\n'
    r'    "~/.gnupg/\*\*": deny\n'
    r'    "~/.aws/\*\*": deny\n'
    r'    "\*": ask\n',
    re.M,
)

abs_edit = '    "/Users/robo/.config/opencode/**": deny\n'

for path in Path("agents").glob("*.md"):
    text = path.read_text()
    new = external_block.sub("", text)
    new = new.replace(abs_edit, "")
    if new != text:
        path.write_text(new)
```

**YAML fix after bulk removal:** several files briefly had broken frontmatter (`permission:  skill:` on one line). Each must be:

```yaml
permission:
  skill: ...
```

not `permission:  skill: ...`.

---

### Step 3 — Writer agent frontmatter (final targets)

#### `agents/developer.md` (and `frontend-dev`, `ux-dev`, `senior-dev`)

```yaml
---
description: "Unified executor for .plan artifacts. Execute only stages with Owner: developer."
mode: subagent
model: openrouter/minimax/minimax-m2.7
steps: 45
tools:
  write: true
  edit: true
  bash: true
  skill: true
permission:
  skill: { "developer": "allow", "preflight": "allow", "debug-fix": "allow", "zoom-out": "allow", "caveman": "allow" }
  edit:
    "~/.config/opencode/**": deny
    "*": allow
  bash:
    "*": allow
---
```

(`frontend-dev` / `ux-dev` / `senior-dev`: same shape; swap `skill` allow map and description.)

#### `agents/scribe.md`

Remove `external_directory`. Keep scribe-specific **allowlist** `edit` patterns if present on disk; **add** (or ensure) deny for shared config:

```yaml
permission:
  bash:
    "*": allow
  skill: { "scribe": "allow" }
  edit:
    "~/.config/opencode/**": deny
    "*": allow
    # … existing scribe path allowlist (.plan, docs/, etc.) may follow …
```

If scribe uses a deny-first allowlist model (current repo has `"*": deny` plus explicit allows), add `"~/.config/opencode/**": deny` **before** wildcard allow/deny rules without duplicating `/Users/…` paths.

#### Read-only / review agents (`verifier`, `helper`, `worktree-env`, `review`, `*-reviewer`)

**Final target — no `external_directory`:**

```yaml
permission:
  edit: deny
  skill: { "verifier": "allow" }
  bash:
    "*": allow
```

(`helper`, `worktree-env`: `bash` first; `review` + nested reviewers: same read-only pattern as in chat.)

---

### Step 4 — Extend `scripts/validate-opencode-config.sh`

**Remove** (old policy — caused prompt spam):

```bash
  if ! echo "$fm" | grep -Fq '"*": ask'; then
    echo "  UNSAFE: $f should ask before external directory file access"
    ERR=1
  fi
  for external_allow_path in \
    '~/.config/opencode/**' \
    '/Users/robo/.config/opencode/**' \
    '~/.local/share/mise/**' \
    '/Users/robo/.local/share/mise/**' \
    '~/05_Repos/**' \
    '/Users/robo/05_Repos/**'
  do
    # … require allow before ask …
  done
```

**Add** inside the existing `UNATTENDED_BASH_AGENTS` loop (after bash `"*": allow` check):

```bash
  if echo "$fm" | grep -qE '/Users/|/home/[^/]+/'; then
    echo "  UNSAFE: $f hardcodes absolute home paths — use opencode.json permission only"
    ERR=1
  fi
  if echo "$fm" | grep -q '^[[:space:]]*external_directory:'; then
    echo "  UNSAFE: $f should not define external_directory — inherit global deny-only rules from opencode.json"
    ERR=1
  fi
done

echo "Checking global external_directory is deny-only (portable)..."
if ! python3 - <<'PY'
import json
from pathlib import Path
perm = json.loads(Path("opencode.json").read_text())["permission"]
ext = perm["external_directory"]
if ext.get("*") != "allow":
    raise SystemExit("external_directory * must be allow")
for key in ext:
    if key.startswith("/Users/") or key.startswith("/home/"):
        raise SystemExit(f"hardcoded absolute path: {key}")
if ext.get("~/.ssh/**") != "deny":
    raise SystemExit("missing ~/.ssh/** deny")
if ext.get("~/.gnupg/**") != "deny":
    raise SystemExit("missing ~/.gnupg/** deny")
if ext.get("~/.aws/**") != "deny":
    raise SystemExit("missing ~/.aws/** deny")
PY
then
  echo "  UNSAFE: opencode.json external_directory must use *:allow plus ~/.ssh, ~/.gnupg, ~/.aws denies only"
  ERR=1
fi
```

**Writer edit check** — use tilde path only:

```bash
  for opencode_path in '~/.config/opencode/**'; do
    if ! echo "$fm" | grep -Fq "\"$opencode_path\": deny"; then
      echo "  UNSAFE: $f should deny edits to shared OpenCode config path $opencode_path"
      ERR=1
    fi
    # … deny must appear before wildcard edit allow …
  done
```

Keep existing checks: agent keys in `opencode.json`, skills exist, read-only bash guards, architect Mode B guard, etc.

---

### Step 5 — Documentation

#### `docs/RUNBOOK.md` — add under **Permission Conventions (skill creep prevention)**

```markdown
- **External directories (portable):** Only **`opencode.json`** defines `permission.external_directory`: `*: allow` plus **deny** for `~/.ssh/**`, `~/.gnupg/**`, `~/.aws/**`. Do not put user-specific roots (`~/05_Repos`, `/Users/...`) in agent frontmatter — agents inherit global rules. Destructive shell guardrails live in `permission.bash` (force-push, `rm -rf ~`, hard reset, etc.). Unattended writers still **deny** `edit` under `~/.config/opencode/**`. Per-machine overrides belong in a local fork of `opencode.json`, not shared agents.
```

#### `README.md` — global permission bullet (replace or extend)

```markdown
- **Global:** [`rules/`](rules/) via **`instructions`**; **`permission`** in `opencode.json` allows reads/edits outside the session cwd (with deny rules for `~/.ssh`, `~/.gnupg`, `~/.aws`), bash guardrails for destructive git/rm, asks before changing `opencode.json`, blocks secrets in `.env*`.
```

#### `skills/worktree-env/SKILL.md` — sandbox troubleshooting

**Replace** agent-specific external_directory guidance with:

```markdown
- If `ln` is **denied by the sandbox**, ensure that global `opencode.json` `permission.external_directory` allows paths outside the session cwd, then retry—or run the same `ln` command manually in a terminal.
```

---

## Before state (at chat start)

### Global `opencode.json` — `permission` (excerpt)

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

No `permission.bash` block existed at chat start.

### Agent `developer.md` — `permission` (excerpt, pre-fix)

```yaml
permission:
  external_directory:
    "~/.config/opencode/**": allow
    "/Users/robo/.config/opencode/**": allow
    "~/.ssh/**": deny
    "~/.gnupg/**": deny
    "~/.aws/**": deny
    "*": ask
  skill: { "developer": "allow", "preflight": "allow", "debug-fix": "allow", "zoom-out": "allow", "caveman": "allow" }
  edit:
    "~/.config/opencode/**": deny
    "/Users/robo/.config/opencode/**": deny
    "*": allow
  bash:
    "*": allow
```

Same `"*": ask` + allowlist pattern existed on all 12 agents listed above.

### Validator — old unattended-agent policy (excerpt)

```bash
  if ! echo "$fm" | grep -Fq '"*": ask'; then
    echo "  UNSAFE: $f should ask before external directory file access"
    ERR=1
  fi
  for opencode_path in '~/.config/opencode/**' '/Users/robo/.config/opencode/**'; do
    if ! echo "$fm" | grep -Fq "\"$opencode_path\": allow"; then
      echo "  BLOCKING: $f should allow read/execute access to $opencode_path"
      ERR=1
    fi
    # … allow lines must appear before "*": ask …
  done
```

---

## After state (chat-finalised)

| File | Final state |
| --- | --- |
| `opencode.json` | `external_directory` deny-only; `bash` guardrails; portable `npx`; preserve `edit` rules |
| 12 agents | No `external_directory`; no `/Users/…` |
| 5 writers | `edit` deny `~/.config/opencode/**` only |
| `validate-opencode-config.sh` | Portable checks; **no** `"*": ask` requirement |
| RUNBOOK / README / worktree-env skill | As in Step 5 |

---

## Expected behaviour after re-application

| Scenario | Expected |
| --- | --- |
| Read/edit under session cwd | No `external_directory` prompt |
| Read mise gem source `~/.local/share/mise/...` | No prompt |
| Read any sibling repo path (any user’s home layout) | No prompt |
| Read `~/.ssh/id_rsa` | **Denied** |
| Read `~/.aws/credentials` | **Denied** |
| `developer` edits `~/.config/opencode/agents/foo.md` | **Denied** |
| `rm -rf ~` via bash | **Denied** |
| UI “Always allow” | Session-only — restart + config change is durable fix |

**Restart OpenCode** after applying.

---

## Verification checklist

```bash
# From repo root
scripts/validate-opencode-config.sh
python3 -m json.tool opencode.json >/dev/null

# Must not match
grep -R '/Users/' agents/ || echo "OK: no absolute paths in agents"
grep -R 'external_directory:' agents/ && echo "FAIL" || echo "OK: agents inherit global"

# Should match
grep -F '"*": "allow"' opencode.json
grep -F '~/.ssh/**' opencode.json
```

Manual:

- [ ] Orchestrate from spec repo; `developer` reads impl repo + gem source — no prompts
- [ ] Attempt read of `~/.ssh` — blocked
- [ ] `which npx` works in OpenCode’s environment

---

## Current on-disk state (post-session)

Snapshot when this review doc was expanded (**2026-06-01**). Repo **does not match** chat-finalised state:

| Expected (chat) | Observed on disk |
| --- | --- |
| `opencode.json` → `permission.external_directory` | **Missing** |
| `opencode.json` → `permission.bash` | **Missing** |
| `claude-context` → `"npx"` | Still **hardcoded** mise path |
| `validate-opencode-config.sh` portable checks | **Reverted** (~45 lines, agent/skill only) |
| `agents/developer.md` → `edit` deny `~/.config/opencode/**` | **Missing** (skill-only permission) |
| `docs/RUNBOOK.md` portable external-directory bullet | **Missing** |
| Agents without `external_directory` | **Matches** |

**Action:** Re-apply using [Recreation guide](#recreation-guide-for-another-ai) above.

---

## Anti-patterns (do not reintroduce)

1. `"external_directory": { "*": ask }` on subagents while global is allow.
2. `/Users/username/...` or `~/05_Repos/**` in shared `agents/*.md`.
3. Per-path allowlists in agents instead of global deny-only + optional local `opencode.json` fork.
4. Validator rules that **require** `"*": ask` on external_directory.

---

## Related references

- OpenCode permissions: https://opencode.ai/docs/permissions
- [`scripts/block-dangerous-git.sh`](../scripts/block-dangerous-git.sh) — bash deny pattern reference
- [`docs/RUNBOOK.md`](../docs/RUNBOOK.md) — config precedence
- Prior art (same `TO REVIEW/` folder): [`2026-05-16-warp-worktree-permission-flow-adjustments.md`](2026-05-16-warp-worktree-permission-flow-adjustments.md)

---

*Document produced from Cursor chat **7acb546f-f3cc-4d5a-b704-27fa39445ab4** (created **2026-05-18**). Filename prefix sorts between `TO REVIEW/2026-05-17-*.md` and `TO REVIEW/2026-05-19-*.md`.*
