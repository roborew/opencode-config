# 2026-06-01 — MiniMax M2.7 → M3 OpenRouter Upgrade

**Cursor chat created:** 2026-06-01 17:24 (local) — transcript `25568e19-42b6-4eb1-aa0d-cc322603a9b0`

**Work completed:** 2026-06-01 (implementation edits in the same chat; transcript last updated ~19:20)

**Filename:** `2026-06-01-minimax-m3-openrouter-upgrade.md` — `YYYY-MM-DD` prefix is the **Cursor chat creation date** (not a later calendar day when this review doc was edited).

**Session scope:** Upgrade all OpenCode references from **MiniMax M2.7** to **MiniMax M3** on OpenRouter (`minimax/minimax-m3`).

**Status:** Finalized in chat. **Verify on disk before merge** — workspace may have reverted to `minimax-m2.7` since this session.

**Related (same chat creation date, different session):** `2026-06-01-model-routing-configuration.md` — broader Qwen3.7 / M3 orchestration routing; reconcile if both apply.

---

## User request (verbatim)

> Can we upgrade minmax from open router from 2.7 to 3: minimax/minimax-m3

---

## Executive summary

| Item | Before | After |
| --- | --- | --- |
| OpenRouter provider slug | `minimax/minimax-m2.7` (+ optional `:nitro`) | `minimax/minimax-m3` only |
| OpenCode agent model string | `openrouter/minimax/minimax-m2.7` | `openrouter/minimax/minimax-m3` |
| Agents touched | `developer`, `frontend-dev` | Same (only these used M2.7) |
| Sampling | `temperature: 0.3`, `top_p: 0.95` | Unchanged |
| Validation | — | `scripts/validate-opencode-config.sh` → OK |

---

## OpenCode model ID convention

OpenCode stores models as:

```text
openrouter/<provider-model-slug>
```

For this upgrade:

| Layer | Value |
| --- | --- |
| Provider key in `opencode.json` | `openrouter` |
| Model slug under `provider.openrouter.models` | `minimax/minimax-m3` |
| Agent `model` field | `openrouter/minimax/minimax-m3` |

Do **not** confuse with MiniMax’s direct API name `MiniMax-M3`; OpenRouter uses `minimax/minimax-m3`.

---

## Discovery (how the session found targets)

These ripgrep commands were run from repo root `~/.config/opencode`:

```bash
rg -i 'minimax' .
rg -i '2\.7|m2\.7|minimax-m' .
rg -i 'm2\.7|MiniMax M2' .
```

**Hits at session start (implementation-relevant):**

| Path | Match |
| --- | --- |
| `opencode.json` | `minimax/minimax-m2.7`, `minimax/minimax-m2.7:nitro`, agent models |
| `agents/developer.md` | `model: openrouter/minimax/minimax-m2.7` |
| `agents/frontend-dev.md` | `model: openrouter/minimax/minimax-m2.7` |
| `docs/upgrade-spec/upgrade-plan.md` | Pipeline table: `MiniMax M2.7` |

**Not modified:** `scripts/validate-opencode-config.sh`, `README.md`, `docs/RUNBOOK.md` (no hard-coded M2.7 slugs).

**Research:** OpenRouter [MiniMax M3](https://openrouter.ai/minimax/minimax-m3) — no public `minimax/minimax-m3:nitro` slug at upgrade time.

---

## Files modified (complete list)

| File | Change |
| --- | --- |
| `opencode.json` | Provider registry + `developer` / `frontend-dev` agent models |
| `agents/developer.md` | Frontmatter `model:` |
| `agents/frontend-dev.md` | Frontmatter `model:` |
| `docs/upgrade-spec/upgrade-plan.md` | One table cell: `MiniMax M2.7` → `MiniMax M3` |

---

## Recreation guide (for another AI)

Apply edits in this order, then validate.

### Step 1 — `opencode.json` provider models

**Locate:** `provider.openrouter.models` (near top of file, after `chunkTimeout`).

**Replace this block (DELETE both M2.7 entries):**

```json
        "minimax/minimax-m2.7": {
          "name": "MiniMax M2.7",
          "options": {
            "temperature": 0.3,
            "top_p": 0.95
          }
        },
        "minimax/minimax-m2.7:nitro": {
          "name": "MiniMax M2.7 (nitro)",
          "options": {
            "temperature": 0.3,
            "top_p": 0.95
          }
        },
```

**With:**

```json
        "minimax/minimax-m3": {
          "name": "MiniMax M3",
          "options": {
            "temperature": 0.3,
            "top_p": 0.95
          }
        },
```

**Exact `StrReplace` used in chat:**

- `old_string`: entire M2.7 + nitro block (as above, including trailing comma after closing `}`)
- `new_string`: single M3 block (as above)

---

### Step 2 — `opencode.json` agent model fields

**Replace all occurrences** of:

```json
openrouter/minimax/minimax-m2.7
```

**With:**

```json
openrouter/minimax/minimax-m3
```

**Expected hit count:** 2 (only `developer` and `frontend-dev`).

**`developer` block — before:**

```json
    "developer": {
      "mode": "subagent",
      "model": "openrouter/minimax/minimax-m2.7",
      "steps": 45
    },
```

**`developer` block — after:**

```json
    "developer": {
      "mode": "subagent",
      "model": "openrouter/minimax/minimax-m3",
      "steps": 45
    },
```

**`frontend-dev` block — before:**

```json
    "frontend-dev": {
      "mode": "subagent",
      "model": "openrouter/minimax/minimax-m2.7",
      "steps": 45
    }
```

**`frontend-dev` block — after:**

```json
    "frontend-dev": {
      "mode": "subagent",
      "model": "openrouter/minimax/minimax-m3",
      "steps": 45
    }
```

**Do not change** other agents in this session (e.g. `orchestrate`, `build`, `architect`) unless applying `2026-06-01-model-routing-configuration.md` separately.

---

### Step 3 — `agents/developer.md` frontmatter

**Before (lines 1–5):**

```yaml
---
description: "Unified executor for .plan artifacts. Execute only stages with Owner: developer."
mode: subagent
model: openrouter/minimax/minimax-m2.7
steps: 45
```

**After:**

```yaml
---
description: "Unified executor for .plan artifacts. Execute only stages with Owner: developer."
mode: subagent
model: openrouter/minimax/minimax-m3
steps: 45
```

**Single-line replace:**

```text
model: openrouter/minimax/minimax-m2.7
→
model: openrouter/minimax/minimax-m3
```

Leave `tools`, `permission`, and body unchanged.

---

### Step 4 — `agents/frontend-dev.md` frontmatter

**Before (lines 1–5):**

```yaml
---
description: UI specialist
mode: subagent
model: openrouter/minimax/minimax-m2.7
steps: 45
```

**After:**

```yaml
---
description: UI specialist
mode: subagent
model: openrouter/minimax/minimax-m3
steps: 45
```

**Single-line replace:** same `model:` swap as `developer.md`.

---

### Step 5 — `docs/upgrade-spec/upgrade-plan.md`

**Replace once (global):**

```text
MiniMax M2.7
→
MiniMax M3
```

**Context at time of edit** — pipeline capability table row (approx. line 36):

**Before:**

```markdown
| Architect → Orchestrate → Subagents pipeline | **Strong** | Model-routed (DeepSeek V4 Pro/Flash, MiniMax M2.7, GPT-5 Nano, Gemini 3 Flash, Qwen3 VL); difficulty grading drives gate selection. |
```

**After:**

```markdown
| Architect → Orchestrate → Subagents pipeline | **Strong** | Model-routed (DeepSeek V4 Pro/Flash, MiniMax M3, GPT-5 Nano, Gemini 3 Flash, Qwen3 VL); difficulty grading drives gate selection. |
```

**Note:** `docs/upgrade-spec/upgrade-plan.md` may be absent on disk in a later checkout; recreate the one-line substitution if the file exists.

---

### Step 6 — Validate

```bash
cd ~/.config/opencode
scripts/validate-opencode-config.sh
python3 -m json.tool opencode.json >/dev/null
rg 'minimax-m2\.7' opencode.json agents/developer.md agents/frontend-dev.md
```

**Expected:**

- Validator: `validate-opencode-config: OK`
- `rg`: no matches (exit code 1)

**Validator checks relevant to this change:**

- Every `agents/*.md` with a `model:` key must match `opencode.json` `agent.<name>.model`
- JSON schema validity

---

## Target end state (full snippets for copy-paste verification)

### `opencode.json` — provider excerpt (target)

```json
      "models": {
        "minimax/minimax-m3": {
          "name": "MiniMax M3",
          "options": {
            "temperature": 0.3,
            "top_p": 0.95
          }
        },
```

(M3 entry should sit among other OpenRouter models, e.g. before or after `openai/gpt-5-nano` depending on file order.)

### `opencode.json` — agents excerpt (target)

```json
    "developer": {
      "mode": "subagent",
      "model": "openrouter/minimax/minimax-m3",
      "steps": 45
    },
```

```json
    "frontend-dev": {
      "mode": "subagent",
      "model": "openrouter/minimax/minimax-m3",
      "steps": 45
    }
```

### Agent frontmatter (target)

`agents/developer.md`:

```yaml
model: openrouter/minimax/minimax-m3
```

`agents/frontend-dev.md`:

```yaml
model: openrouter/minimax/minimax-m3
```

---

## Why M3 (reference)

| Aspect | M2.7 (previous) | M3 (target) |
| --- | --- | --- |
| OpenRouter ID | `minimax/minimax-m2.7` | `minimax/minimax-m3` |
| Positioning | Multi-agent productivity / document workflows | Coding, agentic work, long context, native multimodal |
| Context (OpenRouter) | Prior generation | Up to ~1M tokens (MSA) |
| Nitro variant | `minimax/minimax-m2.7:nitro` was registered | No public `minimax/minimax-m3:nitro` at upgrade time |

**Decisions recorded in chat:**

- Keep `temperature: 0.3` and `top_p: 0.95` for continuity.
- Remove `:nitro` registry entry to avoid stale preset models.
- Do **not** add OpenRouter `reasoning` parameters in this session (optional follow-up).

---

## Pre-session baseline (grep snapshot)

At chat start, **only** these paths referenced M2.7:

```
opencode.json
  - provider.openrouter.models: minimax/minimax-m2.7, minimax/minimax-m2.7:nitro
  - agent.developer.model
  - agent.frontend-dev.model
agents/developer.md
agents/frontend-dev.md
docs/upgrade-spec/upgrade-plan.md (prose only)
```

Other agents already used DeepSeek, Qwen, Gemini, or GPT-5 Nano per earlier routing.

---

## Operator follow-ups (not done in chat)

### OpenRouter preset allowlist

If the API key uses a preset, update allowed models:

**Add:**

- `minimax/minimax-m3`

**Remove (if no longer used anywhere):**

- `minimax/minimax-m2.7`
- `minimax/minimax-m2.7:nitro`

See `docs/RUNBOOK.md` → “OpenRouter preset (limit Others model spend)”.

### Optional: reasoning on M3

OpenRouter M3 supports `reasoning` / `reasoning_details` in streaming. This session did not add `reasoning` under `provider.openrouter.models["minimax/minimax-m3"].options`.

Example (not applied — reference only):

```json
"minimax/minimax-m3": {
  "name": "MiniMax M3",
  "options": {
    "temperature": 0.3,
    "top_p": 0.95,
    "reasoning": { "enabled": true }
  }
}
```

Confirm option shape against current OpenCode + OpenRouter docs before enabling.

---

## Broader routing (separate session)

`2026-06-01-model-routing-configuration.md` documents a **wider** change the same day (Qwen3.7 architect, M3 orchestrate/build, etc.). That doc’s table may show `developer` / `frontend-dev` “already MiniMax M3” if routing landed first; **this chat** was the explicit **M2.7 → M3** swap when the repo still had M2.7 slugs.

Apply both docs if your tree should match the full June 1 stack.

---

## Review checklist

- [ ] Filename still `2026-06-01-minimax-m3-openrouter-upgrade.md` (chat created 2026-06-01)
- [ ] `opencode.json` provider has `minimax/minimax-m3` only (no `minimax-m2.7`)
- [ ] `agent.developer.model` and `agent.frontend-dev.model` → `openrouter/minimax/minimax-m3`
- [ ] `agents/developer.md` and `agents/frontend-dev.md` frontmatter matches
- [ ] `docs/upgrade-spec/upgrade-plan.md` says MiniMax M3 in pipeline row (if file exists)
- [ ] OpenRouter preset allowlist updated
- [ ] `scripts/validate-opencode-config.sh` passes
- [ ] Smoke-test: delegate to `developer` or `frontend-dev`; confirm billing uses `minimax/minimax-m3`

---

## One-shot shell re-apply (optional)

Only if you accept automated substitution — review diff before commit:

```bash
cd ~/.config/opencode

# opencode.json: provider block — prefer manual edit using Step 1 snippets
# opencode.json + agents: model string
rg -l 'minimax/minimax-m2\.7' opencode.json agents/developer.md agents/frontend-dev.md \
  | xargs -I{} sed -i '' 's|openrouter/minimax/minimax-m2.7|openrouter/minimax/minimax-m3|g' {}

# upgrade-plan prose (if present)
[ -f docs/upgrade-spec/upgrade-plan.md ] && \
  sed -i '' 's/MiniMax M2.7/MiniMax M3/g' docs/upgrade-spec/upgrade-plan.md

scripts/validate-opencode-config.sh
rg 'minimax-m2\.7' opencode.json agents/developer.md agents/frontend-dev.md || true
```

Manual Step 1 (provider block) is still required if `sed` cannot remove the nitro entry cleanly.

---

## References

- [MiniMax M3 on OpenRouter](https://openrouter.ai/minimax/minimax-m3)
- [MiniMax provider on OpenRouter](https://openrouter.ai/minimax)
- Cursor transcript: `25568e19-42b6-4eb1-aa0d-cc322603a9b0` (chat created 2026-06-01)
- In-repo authority: `opencode.json`, `agents/developer.md`, `agents/frontend-dev.md`
