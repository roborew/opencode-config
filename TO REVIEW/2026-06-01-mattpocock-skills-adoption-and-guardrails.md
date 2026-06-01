# 2026-06-01 — Matt Pocock Skills Adoption, Domain Docs, and Config Fix

**Work completed:** 2026-06-01 — date prefix matches when implementation files were written in this chat (not the date this review note was requested, if later).

**Session scope:** Adopt high-value patterns from [mattpocock/skills](https://github.com/mattpocock/skills) into the existing `~/.config/opencode` setup: replace generic **`grill-me`** with the **`grill-with-docs`** discipline, extend **`scribe`** for per-repo domain docs, add productivity/engineering skills (`handoff`, `zoom-out`, `caveman`, `to-issues`, `setup-skills`), rewrite **`debug-fix`** with diagnose-style phases, add git/SQL guardrail scripts, wire agent skill routing, then fix OpenCode startup failures caused by invalid config and YAML frontmatter.

**Status:** Implemented and finalized 2026-06-01. OpenCode should load after the config/YAML fixes at the end of this document.

**Plan reference:** Cursor plan `skills-upgrade-from-mattpocock` (not committed; user chose not to edit the plan file).

---

## Executive summary

| Area | Outcome |
| --- | --- |
| **`grill-me`** | Replaced 13-line generic skill with full [grill-with-docs](https://github.com/mattpocock/skills/tree/main/skills/engineering/grill-with-docs) content; kept skill name/folder so architect Mode A auto-load is unchanged |
| **Domain docs** | `CONTEXT.md`, `CONTEXT-MAP.md`, `docs/adr/**`, `docs/agents/**`, `AGENTS.md` added to scribe allow-list; grill-me persists glossary/ADRs **via scribe only** |
| **New skills** | `zoom-out`, `handoff`, `to-issues`, `caveman`, `setup-skills` |
| **`debug-fix`** | Full diagnose-style loop (feedback loop → reproduce → hypotheses → instrument → fix/regression → cleanup) |
| **Git guardrails** | `scripts/block-dangerous-git.sh`, `scripts/preflight-git.sh`; hardened `ship` / `hotfix` skills |
| **Agent routing** | `architect`, `orchestrate`, `developer` permission.skill + Skill routing sections updated |
| **Post-fix** | Removed invalid `_skills_registry` from `opencode.json`; quoted YAML `description` in `developer.md` / `ux-dev.md` |
| **Not added** | Separate `grill-with-docs` folder (folded into `grill-me`); `to-prd` (plan said skip — `.plan/` remains source of truth); PreToolUse hooks in `opencode.json` (host-dependent; scripts only) |

---

## Architecture (data flow)

```text
User → architect
         │
         ├─ Mode A gate: grill-me (grill-with-docs)
         │     ├─ emits CONTEXT.md / ADR bodies → Task scribe
         │     └─ then architect-plan → scribe → .plan/<type>.<slug>.md
         │
         ├─ utility: handoff | zoom-out | caveman | to-issues | setup-skills
         │
         └─ user switches to orchestrate
               ├─ developer / frontend-dev / ux-dev / verifier …
               ├─ debug-fix (on .plan/debug or explicit diagnosis)
               └─ handoff | zoom-out | caveman

Per-repo (via setup-skills + grill-me):
  CONTEXT.md | CONTEXT-MAP.md | docs/adr/ | docs/agents/
```

---

## 1. `grill-me` — grill-with-docs adoption

**Source:** [mattpocock/skills/engineering/grill-with-docs](https://github.com/mattpocock/skills/tree/main/skills/engineering/grill-with-docs)

**Decision:** Keep folder/skill name **`grill-me`** so [`agents/architect.md`](../agents/architect.md) Mode A routing (`grill-me` before `architect-plan`) required **zero renames**.

### Files

| File | Role |
| --- | --- |
| [`skills/grill-me/SKILL.md`](../skills/grill-me/SKILL.md) | Main protocol: one question at a time, codebase-first, glossary challenges, scenario stress-tests, code cross-check, ADR triple-test |
| [`skills/grill-me/CONTEXT-FORMAT.md`](../skills/grill-me/CONTEXT-FORMAT.md) | Glossary structure (Language, Relationships, Example dialogue, Flagged ambiguities); single vs multi-context |
| [`skills/grill-me/ADR-FORMAT.md`](../skills/grill-me/ADR-FORMAT.md) | Sequential `docs/adr/NNNN-slug.md`; when to offer an ADR |

### OpenCode adaptation (only change from upstream)

Matt's skill writes `CONTEXT.md` inline. Here the **architect is read-only** — grill-me instructs:

1. Produce the **full updated file body** when a term or ADR is resolved (no batching, no empty stubs).
2. **Task `scribe`** with `target_path`, `content`, `mode: create|update`.
3. Lazy creation only when there is substantive content.

ADR creation uses the same scribe path with numbered paths under `docs/adr/` (or context-specific paths per `CONTEXT-MAP.md`).

---

## 2. Scribe — extended write allow-list

**Problem:** Domain docs from grill-me could not be persisted; scribe only allowed `.plan/`, changelog/guides/architecture, README, `.env.example`.

### [`skills/scribe/SKILL.md`](../skills/scribe/SKILL.md)

Hard Rule 3 now includes:

- `CONTEXT.md`, `CONTEXT-MAP.md` (root and nested context paths)
- `docs/adr/*.md`, `docs/adr/**/*.md` (including nested e.g. `src/ordering/docs/adr/`)
- `docs/agents/*.md`, `docs/agents/**/*.md`
- Root `AGENTS.md` (from `setup-skills`)

### [`agents/scribe.md`](../agents/scribe.md)

Matching `permission.edit` patterns added for the above paths (including limited-depth nested `CONTEXT.md` / `docs/adr` globs).

**Invariant preserved:** Scribe remains the **only** write path for architect/orchestrate domain and plan artifacts (except handoff temp files — see §5).

---

## 3. New skills

### `zoom-out` — [`skills/zoom-out/SKILL.md`](../skills/zoom-out/SKILL.md)

On-demand “step back”: map modules and callers using `CONTEXT.md` vocabulary before editing unfamiliar code. No file writes.

**Loaded by:** architect, orchestrate, developer (on user request).

### `handoff` — [`skills/handoff/SKILL.md`](../skills/handoff/SKILL.md)

Compact session state for a fresh agent: goal, blockers, next action, artifact paths, suggested skills. References existing `.plan/`, ADRs, CONTEXT by path — does not duplicate bodies.

**Output:**

- **Architect** (`bash: true`): `mktemp -t handoff-XXXXXX.md` + write via shell redirect.
- **Orchestrate** (`bash: false`): emit handoff markdown in chat (or delegate per skill text).

### `to-issues` — [`skills/to-issues/SKILL.md`](../skills/to-issues/SKILL.md)

Convert `.plan/<type>.<slug>.md` (or in-context plan) into **tracer-bullet** GitHub issues via `gh issue create`:

- Vertical slices (end-to-end, not layer-only)
- HITL vs AFK tagging
- User quiz on granularity before publish
- Dependency order so “Blocked by” cites real issue numbers
- Reads `docs/agents/issue-tracker.md` / `triage-labels.md` when present (from `setup-skills`)

**Loaded by:** architect only (user-initiated; does not replace scribe → orchestrate handoff).

### `caveman` — [`skills/caveman/SKILL.md`](../skills/caveman/SKILL.md)

Ultra-compressed replies (~75% token reduction) until user says `stop caveman` / `normal mode`. Auto-clarity exception for security warnings and irreversible ops.

**Loaded by:** architect, orchestrate, developer.

### `setup-skills` — [`skills/setup-skills/SKILL.md`](../skills/setup-skills/SKILL.md)

Per-repo bootstrap (prompt-driven, writes **via scribe**):

| Output | Purpose |
| --- | --- |
| `docs/agents/issue-tracker.md` | GitHub (default), GitLab, local `.scratch/`, or freeform |
| `docs/agents/triage-labels.md` | Map canonical five labels to repo labels |
| `docs/agents/domain.md` | Single vs multi-context layout |
| `AGENTS.md` or README `## Agent skills` block | Pointer to the three docs above |

**Loaded by:** architect.

---

## 4. `debug-fix` rewrite

**File:** [`skills/debug-fix/SKILL.md`](../skills/debug-fix/SKILL.md)

Replaced short 5-step workflow with diagnose-style phases:

1. **Build a feedback loop** — failing test, curl, CLI snapshot, browser, trace replay, harness, fuzz, bisect, differential, HITL last
2. **Reproduce** — confirm user's symptom, not a nearby failure
3. **Trace** — git history / bisect (with user approval for bisect)
4. **Hypothesise** — 3–5 ranked falsifiable hypotheses before testing
5. **Instrument** — debugger > targeted logs; **`[DEBUG-<id>]`** tag on all debug logs
6. **Root cause + fix + regression test** — test before fix at a **correct seam**; missing seam is a finding
7. **Verify** — targeted tests / original loop
8. **Cleanup + post-mortem** — grep-remove `[DEBUG-…]`, delete throwaway harnesses, state winning hypothesis in commit message; recommend `refactor` if architecture blocked regression tests

**Note:** [`skills/debugger/SKILL.md`](../skills/debugger/SKILL.md) unchanged — planning specialist for architect Mode A debug **plans**, not execution.

### Developer wiring — [`agents/developer.md`](../agents/developer.md)

- `permission.skill`: added `debug-fix`, `zoom-out`, `caveman`
- Auto-load **`debug-fix`** when artifact is `.plan/debug.<slug>.md` or parent requests structured diagnosis
- Safety line references `scripts/preflight-git.sh`

---

## 5. Git / SQL guardrails

OpenCode schema has **no** PreToolUse hook block in [`opencode.json`](../opencode.json). Fallback: executable scripts + skill hard rules.

### Scripts

| Script | Purpose |
| --- | --- |
| [`scripts/block-dangerous-git.sh`](../scripts/block-dangerous-git.sh) | Reads JSON stdin `{"tool_input":{"command":"..."}}`; blocks dangerous git, `rm -rf /`/`~`, `DROP`/`TRUNCATE TABLE`, `DELETE` without `WHERE`. `--self-test` for smoke check. `OPENCODE_ALLOW_FORCE_PUSH=1` allows `--force-with-lease` only. |
| [`scripts/preflight-git.sh`](../scripts/preflight-git.sh) | Wraps a command string through the same checker |

### Skill updates

- [`skills/ship/SKILL.md`](../skills/ship/SKILL.md) — expanded hard rules + script pointers
- [`skills/hotfix/SKILL.md`](../skills/hotfix/SKILL.md) — same git safety section

### [`README.md`](../README.md)

Documents guardrails row in quick reference; notes hooks are host-dependent.

---

## 6. Agent skill routing and permissions

Skill allowlists live in **`agents/*.md`** `permission.skill` — **not** in `opencode.json` (see §7).

### Architect — [`agents/architect.md`](../agents/architect.md)

**`permission.skill`:** `architect-plan`, `architect-review`, `grill-me`, `handoff`, `to-issues`, `zoom-out`, `caveman`, `setup-skills`

**Skill routing additions:** utility skills load alone for that turn; handoff / zoom-out / caveman / to-issues / setup-skills triggers documented.

### Orchestrate — [`agents/orchestrate.md`](../agents/orchestrate.md)

**`permission.skill`:** `orchestrate-execution`, `orchestrate-recovery`, `handoff`, `zoom-out`, `caveman`

### Developer — [`agents/developer.md`](../agents/developer.md)

**`permission.skill`:** `developer`, `preflight`, `debug-fix`, `zoom-out`, `caveman`

### Architect-plan — [`skills/architect-plan/SKILL.md`](../skills/architect-plan/SKILL.md)

Step 1 investigation: read `CONTEXT.md` / `CONTEXT-MAP.md` when present after grill-me completes.

---

## 7. OpenCode startup fix (post-implementation)

After the skills work, OpenCode failed with:

```text
Error: 4 of 5 requests failed: config.providers: ConfigInvalidError; …
```

### Cause 1 — invalid root key in `opencode.json`

A temporary **`_skills_registry`** string was added at the root. The [OpenCode config schema](https://opencode.ai/config.json) sets **`additionalProperties: false`** on `Config` — unknown keys invalidate the entire config.

**Fix:** Removed `_skills_registry`. Skill registry text lives in [`README.md`](../README.md) (optional skills list + pointer to `agents/*.md`).

### Cause 2 — invalid YAML in agent frontmatter

Unquoted `description:` values containing `Owner: developer` and `Owner: ux-dev` parse as nested YAML mappings (`:` + space after `Owner`).

**Fix:** Wrapped descriptions in double quotes:

- [`agents/developer.md`](../agents/developer.md)
- [`agents/ux-dev.md`](../agents/ux-dev.md)

All 21 agent frontmatter files validated with a YAML parse pass after the fix.

---

## 8. README updates

[`README.md`](../README.md):

- Scribe bullet lists `adr`, `agents`, `CONTEXT.md`, `CONTEXT-MAP.md`, `AGENTS.md`
- Quick reference row for guardrail scripts
- Optional workflow skills list extended
- **`grill-me`** linked to mattpocock grill-with-docs source
- Explicit note: skill permissions in `agents/*.md`, not `opencode.json`

---

## 9. Explicitly not in scope (this session)

| Item | Reason |
| --- | --- |
| **`to-prd`** skill | Plan decision: `.plan/` artifacts + `strategist` / `architect-plan` already cover planning; GitHub-as-source-of-truth PRD flow not requested |
| **`grill-with-docs`** as separate skill folder | Duplicates architect's existing `grill-me` load contract |
| **`tdd`**, **`prototype`**, **`triage`**, **`improve-codebase-architecture`** from mattpocock repo | Already covered by existing opencode skills |
| **PreToolUse hooks in `opencode.json`** | Schema/host support unclear; script + skill fallback implemented instead |
| **Global `CONTEXT.md` in `~/.config/opencode`** | Domain glossary is per-repo; `setup-skills` scaffolds into target repos |

---

## 10. File checklist (created or materially changed)

### New files

```
skills/grill-me/CONTEXT-FORMAT.md
skills/grill-me/ADR-FORMAT.md
skills/zoom-out/SKILL.md
skills/handoff/SKILL.md
skills/to-issues/SKILL.md
skills/caveman/SKILL.md
skills/setup-skills/SKILL.md
scripts/block-dangerous-git.sh
scripts/preflight-git.sh
```

### Replaced / heavily edited

```
skills/grill-me/SKILL.md          (was ~13 lines generic interview)
skills/debug-fix/SKILL.md         (diagnose-style phases)
skills/scribe/SKILL.md            (allow-list + descriptions)
skills/ship/SKILL.md
skills/hotfix/SKILL.md
skills/architect-plan/SKILL.md    (CONTEXT read in Step 1)
agents/architect.md
agents/orchestrate.md
agents/developer.md
agents/scribe.md
agents/ux-dev.md                  (YAML quote fix only)
README.md
opencode.json                     (_skills_registry removed; otherwise unchanged model routing)
```

---

## 11. Operator quick reference

| Intent | Agent | Skill / action |
| --- | --- | --- |
| Stress-test plan + build glossary | `architect` | Mode A → **`grill-me`** (auto before `architect-plan`) |
| Bootstrap repo agent config | `architect` | **`setup-skills`** → scribe writes `docs/agents/*` |
| Break `.plan` into GitHub issues | `architect` | **`to-issues`** (after plan exists; user confirms slices) |
| Map unfamiliar code | any allowed agent | **`zoom-out`** |
| Compact session for fresh context | `architect` (file) / `orchestrate` (chat) | **`handoff`** |
| Save tokens in long sessions | any allowed agent | **`caveman`** / exit with `normal mode` |
| Structured bug fix during execution | `developer` | **`debug-fix`** on debug artifacts |
| Validate risky git before running | subagent with bash | `scripts/preflight-git.sh '<cmd>'` |

---

## 12. Verification steps

1. **OpenCode loads** — no `ConfigInvalidError` on startup.
2. **YAML** — `python3 -c "import yaml; …"` over all `agents/*.md` frontmatter (or re-run when validator script CRLF is fixed).
3. **Guardrails** — `scripts/block-dangerous-git.sh --self-test` → `OK`.
4. **Architect Mode A** — new feature: confirm `grill-me` loads before planning; CONTEXT updates go through scribe when terms resolve.
5. **Per-repo** — run **`setup-skills`** once in a target repo before relying on **`to-issues`** label vocabulary.

---

## 13. Follow-ups (optional, not done)

- Wire `block-dangerous-git.sh` as a host PreToolUse hook if/when OpenCode documents hook config in schema.
- Add `to-prd` if GitHub Issues should replace `.plan/feature.*.md` as planning source of truth.
- Extend [`scripts/validate-opencode-config.sh`](../scripts/validate-opencode-config.sh) to YAML-parse agent frontmatter (script currently has CRLF line-ending issues on this machine).
- Run **`setup-skills`** in each active repo (Rails / Next.js / FastAPI / CV) so **`to-issues`** and **`grill-me`** read consistent `docs/agents/*` config.
