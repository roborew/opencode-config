# 2026-06-01 — Setup-project workflow, DeepSeek V4 diagnosis, and architect bash permission fixes

**Session completion date (filename prefix):** **2026-06-01** — date this Cursor chat finished its implementation and analysis work (transcript `af8e86be-f83a-4297-ac92-7ee05aeca7af`, ~16:17–19:20 BST). Use this date in the filename, **not** the calendar day you later open the file or add follow-up notes.

**Session scope:** OpenCode stack onboarding (`setup-project`), spec-driven vs direct development guidance, troubleshooting “fizzling” architect sessions on `fidget-spec`, root-cause analysis for DeepSeek V4 Flash vs Qwen, and configuration fixes for architect bash redirect rules.

**Status:** Finalized in chat (2026-06-01). **Verify on disk before merge** — the workspace may have diverged since this session (e.g. `agents/architect.md` frontmatter, `scripts/validate-opencode-config.sh`, or `skills/setup-project/SKILL.md` may differ from what was edited here).

**Companion doc (same day):** [`2026-06-01-model-routing-configuration.md`](2026-06-01-model-routing-configuration.md) — separate session on OpenRouter model routing.

---

## Executive summary

| Topic | Outcome |
| --- | --- |
| Spec vs impl workflow | Documented when to use spec PRD/fanout vs direct impl work (UI tweaks often skip spec). |
| OpenCode “does nothing” on `hi` / `setup-project` | Explained default agent (`orchestrate`), intentional no-skill-on-greeting for architect, two-layer bootstrap (shell vs skill). |
| `setup-project --check-only` | `INCOMPLETE` = registry metadata; `OK` = mechanical wiring — stack not broken. |
| DeepSeek “stopped working” | Config moved **V3.2 → V4 Flash** (May 2026); V4 + OpenRouter multi-turn **tool** sessions often fail `reasoning_content` round-trip; Qwen works because it lacks that protocol. |
| Bash permission errors | Broad denies `*>*` / `*>>*` blocked `gh … 2>&1` and `ls … 2>/dev/null`; **fixed** with spaced redirect denies only. |
| User workaround | Switched architect to **Qwen** — sessions progressed; aligns with V4 diagnosis. |

---

## 1. Guidance documented (no repo code changes)

### 1.1 When to use spec-driven development

Use the **spec repo** path (`grill-me` → `to-prd` → human PRD approval → `bin/fanout` → per-repo `issue-expand` → `orchestrate` → `feature-complete`) when:

- Work spans **multiple repos** or needs **product approval**
- You need a **parent issue**, **PRD** (`docs/prd/<slug>.md`), or **prototypes** in spec
- Cross-repo traceability via label **`feature:<slug>`** matters

Use **direct / implementation-repo** work when:

- Changes are **single-repo**, obvious scope (e.g. layout polish)
- No API/contracts/product decisions
- Optional: architect **option 2** (legacy `.plan`) or plain PR + optional GitHub issue

**Git linking is via issues/labels, not matching branch names** across repos. Fanout suggests `feature/<slug>` in issue bodies; branches can differ per repo.

### 1.2 Correct bootstrap sequence

| Step | Where | What |
| --- | --- | --- |
| 1 | Project parent (`~/code/APP` or `…/fidget`) | Shell: `setup-project` (from `~/.config/opencode/bin`) |
| 2 | `APP-spec` | OpenCode, agent **`architect`**, option **7** or **`Run setup-project`** |
| 3 | — | Architect skill: interview, fill `docs/agents/repos.md`, `Task` → `stack-bootstrap` / `scribe` / `developer` for `--check-only` |

Shell bootstrap does **not** replace the OpenCode skill pass (registry roles, interview, template copy via subagents).

### 1.3 OpenCode session expectations

- **`default_agent`** in `opencode.json` is **`orchestrate`** — fresh sessions do **not** show the architect menu on `hi`.
- Architect on **`hi`**: shows **8-option spec menu** (or impl menu) **without loading a skill** — by design.
- **`setup-project` skill** is **not** allowed on orchestrate; use **architect** in **spec** repo only.

### 1.4 Restart / reload (OpenCode 1.15.13)

- **Full restart:** Quit desktop app (Cmd+Q) or `/exit` / Ctrl+C in CLI, relaunch, reopen `*-spec`.
- **Config reload:** `/reload` (aliases often `/restart`, `/refresh`) or command palette.
- After model/config changes: `opencode models --refresh` in terminal.

---

## 2. Problems diagnosed

### 2.1 Symptom: architect starts `setup-project` then stops

Observed on **`fidget-spec`** (`/Users/robo/05_Repos/01_PROJECTS/apps/fidget/`):

- Skill loaded, `docs/agents/repos.md` read, siblings listed (`fidget-ingest`, `fidget-web`)
- **No** Setup status table, **no** Phase B interview, **no** `Task` → `stack-bootstrap` / `scribe`
- User prompts (“and?”, “are you done?”, “setup status”) met with more reads, not phase progression

### 2.2 `setup-project --check-only` output (not a stack failure)

```text
==> check-only: /Users/robo/05_Repos/01_PROJECTS/apps/fidget
INCOMPLETE: roborew/fidget-ingest, roborew/fidget-web
OK: fidget-ingest
OK: fidget-web
```

| Line | Meaning |
| --- | --- |
| `INCOMPLETE: roborew/...` | `docs/agents/repos.md` entries lack complete `application_role` and `capabilities` (no `TBD`, non-empty) — `migrate_repos_registry.py --check-only` exit **3** |
| `OK: fidget-*` | `check_impl_wiring.sh`: `issue-tracker`, `bin/feature-context`, expand bundles, `.gitignore` scratch paths — mechanical wiring **good** |

### 2.3 Bash permission denials (fixed in this session)

Architect (and planning subagents) had:

```yaml
"*>*": deny
"*>>*": deny
```

OpenCode pattern matching treated these as matching:

- `gh repo view … 2>&1` (contains `>` in `2>&1`)
- `ls … 2>/dev/null` (contains `>`)

So the model saw: *“essential tools blocked”* and burned turns on `Read` fallbacks.

### 2.4 DeepSeek V4 Flash vs “worked brilliantly before”

**Config history (this repo):** commit `3947d0c` (**2026-05-13**) switched provider model from **`deepseek/deepseek-v3.2`** to **`deepseek/deepseek-v4-flash`** for primaries and several agents.

**V4 change:** thinking mode expects **`reasoning_content`** on every assistant message in follow-up turns after tool calls. OpenCode + OpenRouter had widespread **turn-2+ failures** (400: `reasoning_content must be passed back`) — [OpenCode #24190](https://github.com/anomalyco/opencode/issues/24190).

**Why `setup-project` exposes it:** many tool turns per session (reads, bash, later `Task` subagents). Simple chat can still look fine.

**Why Qwen worked when tested:** no equivalent round-trip requirement on the same workflow.

User on **OpenCode 1.15.13** — past the cited 1.14.26 fix line, but OpenRouter/SDK edge cases were still reported in follow-up issues.

---

## 3. Implementations finalized in this chat

### 3.1 Architect bash redirect rules (narrowed)

**Files updated:**

- `agents/architect.md` — frontmatter `permission.bash`
- `agents/debugger.md`, `agents/refactor.md`, `agents/designer.md`, `agents/document.md`, `agents/strategist.md` — same redirect change

**Removed (too broad):**

```yaml
"*>*": deny
"*>>*": deny
```

**Added (file redirects only; allow `2>&1` and `2>/dev/null`):**

```yaml
"* > *": deny
"* >> *": deny
"* 2> *": deny
"* 2>> *": deny
```

**Unchanged:** `*| tee *`, destructive git, `rm`/`mv`/`cp`, package installs, etc. Writes remain on **scribe**.

**Comment added** in `architect.md`: do not reintroduce `*>*` — it blocks harmless stderr redirects.

### 3.2 `skills/setup-project/SKILL.md`

Added **## Bash (architect)** section:

- No redirects to files (`>`, `>>`)
- Allowed: `2>&1`, `2>/dev/null` (no space before `2>`)
- Prefer `git remote get-url origin` when `gh` is unnecessary

### 3.3 `scripts/validate-opencode-config.sh`

- Replaced required `*>*` / `*>>*` checks with spaced redirect patterns
- Split **architect** profile (`"*": allow` + common denies) vs **specialist** profile (`"*": ask` + `rg`/`find`/`git diff` allows)
- Added explicit failure if broad `*>*` deny is reintroduced

Validation was run successfully: `validate-opencode-config: OK` at end of session.

### 3.4 `docs/RUNBOOK.md`

One-line clarification under architect bash policy: use **spaced** file redirect denies; do not use `*>*` (blocks `gh`/`ls` stderr idioms).

---

## 4. Not implemented in repo (user / environment actions)

| Action | Who |
| --- | --- |
| Switch architect model to **Qwen** (or revert to **DeepSeek V3.2**) | User — confirmed working with Qwen |
| `/reload` or restart OpenCode after permission edits | User |
| `opencode models --refresh` | User |
| Complete **Phase B** interview and **scribe** update of `docs/agents/repos.md` for fidget | Architect session / user answers |
| Fill registry so `--check-only` prints **All checks passed** | After registry complete |
| Commit / push config changes | User (not done in chat per git rules) |

---

## 5. Reference: `setup-project` skill phases (for verification)

When architect runs correctly on **spec** repo:

| Phase | Content |
| --- | --- |
| **A** | Read `docs/agents/repos.md`, spec identity (`gh` or `git remote`), sibling dirs, emit **Setup status** table |
| **B** | Interview: triage labels, per-repo `application_role` / `capabilities` / `non_goals`, spec `CONTEXT.md` / `LANGUAGE.md` |
| **C** | Legacy `.plan` / `docs/agents` audit (human confirms moves) |
| **D** | `scribe` → registry; `stack-bootstrap` per impl repo; optional legacy archives; `developer` runs `setup-project --check-only` on parent |

**Hard rule:** skill does not invoke `to-prd`, `fanout`, or `orchestrate`.

---

## 6. Reference: architect subagents for setup

| Agent | Role in Phase D |
| --- | --- |
| `stack-bootstrap` | `copy_templates` into each impl repo (`load: full`, `local_path`, `spec_repo`) |
| `scribe` | Update `docs/agents/repos.md` |
| `developer` | Bash: `setup-project --check-only` on parent directory |

Architect `permission.task` must allow these (was `stack-bootstrap: allow`, `developer: allow`, `scribe: allow` in session-era `architect.md`).

---

## 7. DeepSeek: practical recommendations

| Goal | Recommendation |
| --- | --- |
| Restore “old brilliant” DeepSeek | Point architect at **`deepseek/deepseek-v3.2`** on OpenRouter (pre–V4 contract) |
| Keep V4 Flash | Stay on **1.15.13+**, refresh models; watch logs for `reasoning_content` 400; prefer fewer turns or Qwen for long `setup-project` |
| Reliable `setup-project` now | **Qwen** (user-validated) + bash redirect fix + `/reload` |

---

## 8. Fidget stack context (session example)

| Item | Value |
| --- | --- |
| Parent | `/Users/robo/05_Repos/01_PROJECTS/apps/fidget` |
| Spec | `fidget-spec` → `roborew/fidget-spec` |
| Impl | `fidget-ingest`, `fidget-web` (both `.git` present) |
| Registry | `roborew/fidget-ingest`, `roborew/fidget-web` listed; metadata **incomplete** at check time |

---

## 9. Review checklist

- [ ] Confirm spaced redirect denies exist in `agents/architect.md` (and planning subagents); **no** `*>*` / `*>>*`
- [ ] Confirm `skills/setup-project/SKILL.md` **Bash (architect)** section present
- [ ] Run `scripts/validate-opencode-config.sh` — expect **OK**
- [ ] `/reload` OpenCode after merging
- [ ] Re-test architect `Run setup-project` on `fidget-spec` with chosen model (Qwen or V3.2 vs V4)
- [ ] Confirm `gh … 2>&1` and `ls … 2>/dev/null` are **not** denied
- [ ] Complete registry interview; re-run `setup-project --check-only .` from parent until **All checks passed**

---

## 10. References

- In-repo: `skills/setup-project/SKILL.md`, `bin/setup-project`, `bin/lib/migrate_repos_registry.py`, `bin/stack/check_impl_wiring.sh`, `docs/FEATURE-PIPELINE.md`, `docs/RUNBOOK.md`, `agents/architect.md`
- OpenCode: [Issue #24190 — DeepSeek V4 reasoning_content](https://github.com/anomalyco/opencode/issues/24190)
- Git: `3947d0c` — V3.2 → V4 Flash model routing in `opencode.json`

---

*Document produced from Cursor chat `af8e86be-f83a-4297-ac92-7ee05aeca7af`. **Naming:** `YYYY-MM-DD-<slug>.md` where `YYYY-MM-DD` is the day that chat **completed** the work it describes—not “today” when you later edit or file review notes. Sorts with other `TO REVIEW/2026-06-01-*.md` files alphabetically by slug after the date.*
