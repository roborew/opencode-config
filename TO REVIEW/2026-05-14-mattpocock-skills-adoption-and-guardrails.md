# 2026-05-14 — Matt Pocock Skills Adoption, Domain Docs, and Config Fix

**Cursor chat created:** 2026-05-14 (first message timestamp: Thursday, May 14, 2026, 8:56 PM UTC+1)  
**Cursor transcript ID:** `fbbca11f-6c43-490a-8810-f1d6af2884e3`  
**Filename date rule:** Use **`2026-05-14`** prefix — matches **chat creation**, not file mtime or review-doc edit date.

**Session scope:** Adopt high-value patterns from [mattpocock/skills](https://github.com/mattpocock/skills) into `~/.config/opencode`: replace **`grill-me`** with **[grill-with-docs](https://github.com/mattpocock/skills/tree/main/skills/engineering/grill-with-docs)** (keeping skill name `grill-me`), extend **`scribe`** for domain docs, add five new skills, rewrite **`debug-fix`**, add git guardrail scripts, wire agent routing, fix OpenCode `ConfigInvalidError`.

**Status:** Implemented and finalized in this chat. OpenCode loads after §7 fixes.

**Plan reference:** Cursor plan `skills-upgrade-from-mattpocock` (`skills-upgrade-from-mattpocock_3a8c2ab4.plan.md` — not committed).

---

## Executive summary

| Area | Outcome |
| --- | --- |
| **`grill-me`** | Replaced 13-line generic skill with grill-with-docs; kept folder/name for architect Mode A |
| **Domain docs** | Scribe allow-list: `CONTEXT.md`, `CONTEXT-MAP.md`, `docs/adr/**`, `docs/agents/**`, `AGENTS.md` |
| **New skills** | `zoom-out`, `handoff`, `to-issues`, `caveman`, `setup-skills` |
| **`debug-fix`** | Diagnose-style 8-phase loop (feedback loop first) |
| **Git guardrails** | `scripts/block-dangerous-git.sh`, `scripts/preflight-git.sh`; `ship` / `hotfix` hard rules |
| **Agents** | `architect`, `orchestrate`, `developer`, `scribe`, `ux-dev` updated |
| **Post-fix** | Removed `_skills_registry` from `opencode.json`; quoted YAML in `developer.md` / `ux-dev.md` |
| **Not added** | Separate `grill-with-docs` folder; `to-prd`; PreToolUse hooks in `opencode.json` |

---

## Architecture (data flow)

```text
User → architect
         │
         ├─ Mode A gate: grill-me (grill-with-docs content)
         │     ├─ CONTEXT.md / ADR bodies → Task scribe
         │     └─ architect-plan → scribe → .plan/<type>.<slug>.md
         │
         ├─ utility: handoff | zoom-out | caveman | to-issues | setup-skills
         │
         └─ orchestrate → developer / frontend-dev / …
               ├─ debug-fix (.plan/debug or explicit diagnosis)
               └─ handoff | zoom-out | caveman

Per-repo: setup-skills + grill-me → CONTEXT.md | docs/adr/ | docs/agents/
```

---

## Appendix A — Recreation guide for another AI

Apply changes **in this order** (later steps depend on earlier ones):

1. Extend **`agents/scribe.md`** `permission.edit` and **`skills/scribe/SKILL.md`** Hard Rule 3 (domain paths).
2. Replace **`skills/grill-me/`** (add `CONTEXT-FORMAT.md`, `ADR-FORMAT.md`, rewrite `SKILL.md` with scribe routing).
3. Create new skill folders: `zoom-out`, `handoff`, `to-issues`, `caveman`, `setup-skills`.
4. Rewrite **`skills/debug-fix/SKILL.md`**.
5. Add **`scripts/block-dangerous-git.sh`**, **`scripts/preflight-git.sh`** (`chmod +x`).
6. Update **`skills/ship/SKILL.md`**, **`skills/hotfix/SKILL.md`**, **`skills/architect-plan/SKILL.md`**, **`README.md`**.
7. Update **`agents/architect.md`**, **`agents/orchestrate.md`**, **`agents/developer.md`** frontmatter + Skill routing.
8. **Do not** add `_skills_registry` to `opencode.json`.
9. Quote YAML **`description`** fields that contain `Owner: …` colons in **`agents/developer.md`** and **`agents/ux-dev.md`**.

**Upstream sources to fetch verbatim (then adapt grill-me write path only):**

- https://github.com/mattpocock/skills/tree/main/skills/engineering/grill-with-docs
- https://github.com/mattpocock/skills/tree/main/skills/engineering/zoom-out
- https://github.com/mattpocock/skills/tree/main/skills/productivity/handoff
- https://github.com/mattpocock/skills/tree/main/skills/productivity/caveman
- https://github.com/mattpocock/skills/tree/main/skills/engineering/to-issues
- https://github.com/mattpocock/skills/tree/main/skills/engineering/setup-matt-pocock-skills (adapt to `setup-skills` + scribe writes)
- https://github.com/mattpocock/skills/tree/main/skills/engineering/diagnose (adapt into `debug-fix`, keep filename)
- https://github.com/mattpocock/skills/tree/main/skills/misc/git-guardrails-claude-code (adapt to `block-dangerous-git.sh`)

---

## Appendix B — `grill-me` (was 13 lines → grill-with-docs)

### B.1 Before (delete/replace entirely)

```markdown
---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Architect Mode A loads this after plan type + first substantive requirements and before architect-plan. Also when the user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
---

Interview me relentlessly about every aspect of this plan until
we reach a shared understanding. Walk down each branch of the design
tree resolving dependencies between decisions one by one.

If a question can be answered by exploring the codebase, explore
the codebase instead.

For each question, provide your recommended answer.
```

### B.2 After — frontmatter + OpenCode scribe adaptation (excerpt)

Full file: [`skills/grill-me/SKILL.md`](../skills/grill-me/SKILL.md). Supporting docs copied from upstream:

- [`skills/grill-me/CONTEXT-FORMAT.md`](../skills/grill-me/CONTEXT-FORMAT.md) — verbatim from mattpocock
- [`skills/grill-me/ADR-FORMAT.md`](../skills/grill-me/ADR-FORMAT.md) — verbatim from mattpocock

**Critical adaptation** (replace mattpocock “Update CONTEXT.md inline”):

```markdown
**Lazy creation (OpenCode):** … **You do not write these files yourself** — the Architect agent is read-only.
After each resolved term or ADR body is ready, **Task `scribe`** with explicit `target_path` and full file `content` (and `mode: create` or `update`).

### Persist CONTEXT.md via scribe (do not write inline yourself)
…
Then **invoke `scribe` via Task** with:
- `target_path`: the context file (e.g. `CONTEXT.md` or `src/ordering/CONTEXT.md`)
- `content`: full markdown file body
- `mode`: `create` or `update`
```

**Scribe Task example for architect:**

```text
Task scribe with:
  target_path: CONTEXT.md
  mode: update
  content: |
    # MyApp Context
    …full file body per CONTEXT-FORMAT.md…
```

**ADR scribe Task example:**

```text
Task scribe with:
  target_path: docs/adr/0001-event-sourced-orders.md
  mode: create
  content: |
    # Event-sourced order write model
    We chose event sourcing because …
```

**Architect routing unchanged** — still loads `grill-me` before `architect-plan` in Mode A ([`agents/architect.md`](../agents/architect.md) Skill routing).

---

## Appendix C — Scribe allow-list

### C.1 `skills/scribe/SKILL.md` — add to Hard Rule 3

```markdown
   - `docs/adr/*.md` and `docs/adr/**/*.md` (and the same under any package subtree, e.g. `src/ordering/docs/adr/*.md`)
   - `docs/agents/*.md` and `docs/agents/**/*.md`
   - `CONTEXT.md` and `CONTEXT-MAP.md` at repo root, or `CONTEXT.md` / `CONTEXT-MAP.md` under a subdirectory when used for a bounded context
   - `AGENTS.md` at repo root (optional per-repo agent notes from setup-skills)
```

Update workflow validation bullet to include domain paths.

### C.2 `agents/scribe.md` — add to `permission.edit`

```yaml
    "AGENTS.md": allow
    "CONTEXT.md": allow
    "CONTEXT-MAP.md": allow
    "*/CONTEXT.md": allow
    "*/*/CONTEXT.md": allow
    "*/*/*/CONTEXT.md": allow
    "*/CONTEXT-MAP.md": allow
    "*/*/CONTEXT-MAP.md": allow
    "docs/adr/*.md": allow
    "docs/adr/**/*.md": allow
    "*/docs/adr/*.md": allow
    "*/docs/adr/**/*.md": allow
    "*/*/docs/adr/*.md": allow
    "*/*/docs/adr/**/*.md": allow
    "docs/agents/*.md": allow
    "docs/agents/**/*.md": allow
    "*/docs/agents/*.md": allow
    "*/docs/agents/**/*.md": allow
```

Update Hard Rules §2 responsibilities text to list `docs/adr/*`, `docs/agents/*`, `CONTEXT.md`, `AGENTS.md`.

---

## Appendix D — New skills (create these files)

### D.1 `skills/zoom-out/SKILL.md` (full file)

```markdown
---
name: zoom-out
description: Step back and map how unfamiliar code fits the whole system before changing it. Use when you need a higher-level view, module/caller map, or how a path relates to the rest of the repo.
---

I don't know this area of code well. Go up a layer of abstraction. Give me a map of all the relevant modules and callers, using the project's domain glossary from `CONTEXT.md` (or the context file pointed to by `CONTEXT-MAP.md` if present). Do not edit files until this map is clear.
```

### D.2 `skills/handoff/SKILL.md` (structure)

- Architect (`bash: true`): `HANDOFF_PATH=$(mktemp -t handoff-XXXXXX.md)` → write via heredoc/tee → echo path.
- Orchestrate (`bash: false`): return markdown in chat.
- Content: goal, blockers, next action, `.plan` paths, skill suggestions; **no** full plan/CONTEXT duplication.

See [`skills/handoff/SKILL.md`](../skills/handoff/SKILL.md) for full text.

### D.3 `skills/to-issues/SKILL.md`

Tracer-bullet vertical slices → user quiz → `gh issue create` in dependency order. Reads `docs/agents/issue-tracker.md` and `triage-labels.md` when present. Full file: [`skills/to-issues/SKILL.md`](../skills/to-issues/SKILL.md).

**Issue body template (from skill):**

```markdown
## What to build
…end-to-end behavior, not layer-by-layer…

## Acceptance criteria
- [ ] …

## Blocked by
- #NNN or None — can start immediately
```

### D.4 `skills/caveman/SKILL.md`

Persistent ultra-terse mode until `stop caveman` / `normal mode`. Auto-clarity exception for destructive ops. Full file: [`skills/caveman/SKILL.md`](../skills/caveman/SKILL.md).

### D.5 `skills/setup-skills/SKILL.md`

Per-repo bootstrap via **scribe** writes:

- `docs/agents/issue-tracker.md`
- `docs/agents/triage-labels.md`
- `docs/agents/domain.md`
- `AGENTS.md` **or** README `## Agent skills` block (not both)

Seed templates embedded in skill file — see [`skills/setup-skills/SKILL.md`](../skills/setup-skills/SKILL.md) from `## Seed:` onward.

---

## Appendix E — `debug-fix` rewrite

### E.1 Before (replaced)

```markdown
## Debug-fix workflow
1. **Reproduce** — minimal repro steps or failing test.
2. **Trace** — read code path; git log …
3. **Root cause** — one paragraph
4. **Fix** — smallest change; regression test
5. **Verify** — run targeted tests
```

### E.2 After — phase outline (full file ~128 lines)

File: [`skills/debug-fix/SKILL.md`](../skills/debug-fix/SKILL.md)

| Phase | Name | Key requirement |
| --- | --- | --- |
| 1 | Build feedback loop | Do not proceed without agent-runnable pass/fail signal |
| 2 | Reproduce | Must match **user's** failure |
| 3 | Trace | `git log`, optional `git bisect` with approval |
| 4 | Hypothesise | **3–5 ranked**, falsifiable, show user before testing |
| 5 | Instrument | `[DEBUG-<id>]` on every debug log |
| 6 | Root cause + fix + regression test | Test **before** fix at correct seam |
| 7 | Verify | Re-run Phase 1 loop |
| 8 | Cleanup + post-mortem | Grep-remove `[DEBUG-…]`; hypothesis in commit message |

**Hypothesis format:**

```markdown
> Format: "If `<cause>` is the cause, then `<probe>` will make the bug disappear / will make it worse."
```

**Developer auto-load** ([`agents/developer.md`](../agents/developer.md)):

```markdown
- **Debug-heavy work:** When the artifact is `.plan/debug.<slug>.md` or the parent/user asks for structured diagnosis, load **`debug-fix`** (`load: full`) before substantive fixes.
```

---

## Appendix F — Git / SQL guardrails

### F.1 `scripts/block-dangerous-git.sh` (full file — 69 lines)

See [`scripts/block-dangerous-git.sh`](../scripts/block-dangerous-git.sh).

**Interface:**

```bash
echo '{"tool_input":{"command":"git push --force origin main"}}' | scripts/block-dangerous-git.sh
# exit 2 + stderr BLOCKED message

scripts/block-dangerous-git.sh --self-test
# prints OK
```

**Blocks:** force push, `reset --hard`, `clean -f/-fd`, `branch -D`, `checkout .`, `restore .`, `rm -rf /` or `~`, `DROP TABLE`, `TRUNCATE TABLE`, `DELETE FROM` without `WHERE`.  
**Opt-in:** `OPENCODE_ALLOW_FORCE_PUSH=1` for `--force-with-lease` only.

### F.2 `scripts/preflight-git.sh` (full file)

```bash
#!/usr/bin/env bash
# Usage: scripts/preflight-git.sh 'git push --force origin main'
# Pipes JSON to block-dangerous-git.sh
```

See [`scripts/preflight-git.sh`](../scripts/preflight-git.sh).

### F.3 `skills/ship/SKILL.md` — Hard rules block

```markdown
## Hard rules

- No force push, `git reset --hard`, `git clean -f` / `-fd`, `git branch -D`, `git checkout .`, `git restore .`, or `rm -rf /` / `rm -rf ~`. No `DELETE` SQL without `WHERE`. No `DROP`/`TRUNCATE TABLE` without explicit user confirmation in chat.
- `git push --force-with-lease` only if user typed explicit approval **and** `OPENCODE_ALLOW_FORCE_PUSH=1` is set in the environment.
- Before running a risky git command, optionally validate with `scripts/preflight-git.sh '<command>'` …
```

Mirror same section in [`skills/hotfix/SKILL.md`](../skills/hotfix/SKILL.md).

---

## Appendix G — Agent frontmatter and routing

### G.1 `agents/architect.md`

```yaml
permission:
  edit: deny
  skill: { "architect-plan": "allow", "architect-review": "allow", "grill-me": "allow", "handoff": "allow", "to-issues": "allow", "zoom-out": "allow", "caveman": "allow", "setup-skills": "allow" }
```

**Skill routing additions** (after Mode B bullet):

```markdown
- **Handoff:** User asks to compact session / hand off … → load **`handoff`**.
- **Zoom out:** … → load **`zoom-out`**.
- **Caveman:** … → load **`caveman`** until exit phrase.
- **To issues:** … → load **`to-issues`**.
- **Setup skills:** … → load **`setup-skills`**.
```

Also add rule: utility skills load **alone** for that turn (not combined with `architect-plan` unless user asks).

### G.2 `agents/orchestrate.md`

```yaml
  skill: { "orchestrate-execution": "allow", "orchestrate-recovery": "allow", "handoff": "allow", "zoom-out": "allow", "caveman": "allow" }
```

Handoff note: no bash — emit markdown in chat.

### G.3 `agents/developer.md`

```yaml
description: "Unified executor for .plan artifacts. Execute only stages with Owner: developer."
permission:
  skill: { "developer": "allow", "preflight": "allow", "debug-fix": "allow", "zoom-out": "allow", "caveman": "allow" }
```

**YAML rule:** Any `description` containing `Owner: developer` (colon + space) **must be double-quoted** or YAML parses a nested mapping.

### G.4 `agents/ux-dev.md` (YAML fix only)

```yaml
# BEFORE (invalid YAML — breaks OpenCode app.agents):
description: Prototype code generator. Executes design artifact stages with Owner: ux-dev. …

# AFTER:
description: "Prototype code generator. Executes design artifact stages with Owner: ux-dev. Writes HTML-only framework-agnostic code to .prototype/<slug>/."
```

---

## Appendix H — `architect-plan` + README

### H.1 One-line addition in Step 1 (`skills/architect-plan/SKILL.md`)

```markdown
After satisfying the Claude Context readiness gate above, read **`CONTEXT.md`** or the context file from **`CONTEXT-MAP.md`** when present (domain glossary from **`grill-me`**). Then use `claude-context` …
```

### H.2 `README.md` changes (summary)

- Quick reference row: guardrail scripts
- Scribe bullet: `adr|agents`, `CONTEXT.md`, `CONTEXT-MAP.md`, `AGENTS.md`
- Optional skills list extended
- grill-with-docs link + note that skill permissions live in `agents/*.md`, not `opencode.json`

---

## Appendix I — OpenCode startup fix (ConfigInvalidError)

### I.1 Error observed

```text
Error: 4 of 5 requests failed: config.providers: ConfigInvalidError; provider.list: ConfigInvalidError; app.agents: ConfigInvalidError; config.get: ConfigInvalidError
```

### I.2 Cause 1 — invalid `opencode.json` key

**Do not add** (was added briefly during implementation, then removed):

```json
  "_skills_registry": "Skill allowlists live in agents/*.md permission.skill. Summary: architect — …"
```

OpenCode schema [`https://opencode.ai/config.json`](https://opencode.ai/config.json) sets `"additionalProperties": false` on root `Config`. Any unknown key fails entire config load.

**Correct ending of `opencode.json`:**

```json
    "frontend-dev": {
      "mode": "subagent",
      "model": "openrouter/minimax/minimax-m2.7",
      "steps": 45
    }
  }
}
```

Skill allowlists belong only in **`agents/*.md`** `permission.skill` and [`README.md`](../README.md) prose.

### I.3 Cause 2 — invalid agent YAML frontmatter

Unquoted descriptions with `Owner: developer` / `Owner: ux-dev` fail YAML parse → `app.agents: ConfigInvalidError`.

**Validate all agents:**

```python
import yaml, pathlib
for p in pathlib.Path("agents").glob("*.md"):
    text = p.read_text()
    if text.startswith("---"):
        fm = text[3:text.index("---", 3)]
        yaml.safe_load(fm)  # must not raise
```

---

## Appendix J — Complete file manifest

### New files

| Path |
| --- |
| `skills/grill-me/CONTEXT-FORMAT.md` |
| `skills/grill-me/ADR-FORMAT.md` |
| `skills/zoom-out/SKILL.md` |
| `skills/handoff/SKILL.md` |
| `skills/to-issues/SKILL.md` |
| `skills/caveman/SKILL.md` |
| `skills/setup-skills/SKILL.md` |
| `scripts/block-dangerous-git.sh` |
| `scripts/preflight-git.sh` |

### Modified files

| Path | Change |
| --- | --- |
| `skills/grill-me/SKILL.md` | Full replace (grill-with-docs + scribe) |
| `skills/scribe/SKILL.md` | Domain allow-list |
| `skills/debug-fix/SKILL.md` | Diagnose phases |
| `skills/ship/SKILL.md` | Git hard rules |
| `skills/hotfix/SKILL.md` | Git hard rules |
| `skills/architect-plan/SKILL.md` | Read CONTEXT in Step 1 |
| `agents/architect.md` | skill permissions + routing |
| `agents/orchestrate.md` | skill permissions + routing |
| `agents/developer.md` | skill permissions + debug-fix + quoted description |
| `agents/scribe.md` | permission.edit patterns |
| `agents/ux-dev.md` | quoted description only |
| `README.md` | docs + skills list + guardrails |
| `opencode.json` | ensure no `_skills_registry` |

---

## Appendix K — Operator quick reference

| Intent | Agent | Skill |
| --- | --- | --- |
| Stress-test plan + glossary | `architect` | `grill-me` → `architect-plan` |
| Bootstrap repo agent config | `architect` | `setup-skills` |
| Plan → GitHub issues | `architect` | `to-issues` |
| System map | any allowed | `zoom-out` |
| Session compaction | `architect` / `orchestrate` | `handoff` |
| Token economy | any allowed | `caveman` |
| Execution debug | `developer` | `debug-fix` |
| Validate git command | bash agent | `scripts/preflight-git.sh '<cmd>'` |

---

## Appendix L — Verification

```bash
python3 -m json.tool opencode.json >/dev/null
python3 -c "import yaml,pathlib; [yaml.safe_load(p.read_text()[3:p.read_text().index('---',3)]) for p in pathlib.Path('agents').glob('*.md') if p.read_text().startswith('---')]"
scripts/block-dangerous-git.sh --self-test
# OpenCode app starts without ConfigInvalidError
```

---

## Appendix M — Explicitly not in scope

| Item | Reason |
| --- | --- |
| `to-prd` | `.plan/` + `architect-plan` / `strategist` sufficient |
| Separate `grill-with-docs` folder | Duplicates architect `grill-me` load |
| PreToolUse in `opencode.json` | Schema/host-dependent; scripts used instead |
| Global `CONTEXT.md` in `~/.config/opencode` | Per-repo via `setup-skills` |

---

## Appendix N — Optional follow-ups

- Wire `block-dangerous-git.sh` as host PreToolUse hook when OpenCode documents hook config.
- Run `setup-skills` in each active repo before `to-issues` / label mapping.
- Extend `scripts/validate-opencode-config.sh` with YAML frontmatter checks (fix CRLF on script if needed).
