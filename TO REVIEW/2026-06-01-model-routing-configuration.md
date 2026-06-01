# OpenCode Model Routing Configuration

**Cursor chat created:** 2026-06-01 (17:36 BST) — filename date prefix uses **chat creation date**, not a later TO REVIEW request date.

**Cursor chat ID:** `d2c6920b-0013-4ce8-89ee-7d08314dda45`

**Filename:** `TO REVIEW/2026-06-01-model-routing-configuration.md`

**Session scope:** Map an OpenRouter role-to-model recommendation onto `opencode.json`, sync agent markdown frontmatter for changed agents, and update `docs/RUNBOOK.md`. User later corrected `designer` / `ux-dev` to stay on Gemini 3 Flash.

**Status:** Finalized in chat. **Workspace may have diverged** since then (e.g. current disk may show `minimax-m2.7`, architect still on DeepSeek V4 Flash). Re-apply from this document if grep shows missing targets.

**Companion doc (same chat day, narrower scope):** [`2026-06-01-minimax-m3-openrouter-upgrade.md`](2026-06-01-minimax-m3-openrouter-upgrade.md) — M2.7 → M3 swap for `developer` / `frontend-dev` only.

---

## Objective

Configure OpenCode’s agent stack:

| Layer | Target model | OpenRouter ID |
| --- | --- | --- |
| Architect / planning | Qwen3.7 Max | `qwen/qwen3.7-max` |
| Orchestrator | MiniMax M3 | `minimax/minimax-m3` |
| Primary implementation | MiniMax M3 | `minimax/minimax-m3` |
| Senior / second opinion | DeepSeek V4 Pro | `deepseek/deepseek-v4-pro` |
| Fast utility | DeepSeek V4 Flash | `deepseek/deepseek-v4-flash` |
| Vision | Qwen3 VL | `qwen/qwen3-vl-235b-a22b-instruct` |
| Design briefs & HTML prototypes | Gemini 3 Flash | `google/gemini-3-flash-preview` |
| Writing / docs | GPT-5 Nano | `openai/gpt-5-nano` |

**Config precedence:** `opencode.json` is runtime authority; agent frontmatter `model:` should match for changed agents; RUNBOOK is operator documentation only.

---

## Incoming recommendation (user-provided)

User supplied a role-to-model table with **Qwen3.7 Max as architect** and **MiniMax M3 as orchestrator**, DeepSeek V4 Flash for utility workers, DeepSeek V4 Pro or M3 for senior work, Qwen3 VL for vision, cheap text models for scribe/docs. User asked to map onto the full `opencode.json` agent list with explicit model names and step-limit tweaks.

References:

- [Qwen3.7 Max](https://openrouter.ai/qwen/qwen3.7-max)
- [MiniMax provider](https://openrouter.ai/provider/minimax)
- [DeepSeek V4 Flash](https://openrouter.ai/deepseek/deepseek-v4-flash/apps)

---

## Pre-session baseline (what was on disk when chat started)

At session start, `opencode.json` already had:

- `developer` / `frontend-dev` → `openrouter/minimax/minimax-m3`
- `designer` / `ux-dev` → `openrouter/google/gemini-3-flash-preview`
- `architect`, `orchestrate`, `strategist`, `build` → DeepSeek V4 Flash
- `plan` → DeepSeek V4 Pro (**no** `steps` key)
- Provider included unused `qwen/qwen3-next-80b-a3b-instruct` (no agent referenced it)

### Pre-session provider snippet (Qwen entry to replace)

```json
"qwen/qwen3-next-80b-a3b-instruct": {
  "name": "Qwen3 Next 80B A3B Instruct",
  "options": {
    "temperature": 0.1,
    "top_p": 0.9
  }
},
```

### Pre-session agent block (agents changed in this chat)

```json
"architect": {
  "model": "openrouter/deepseek/deepseek-v4-flash",
  "steps": 30
},
"orchestrate": {
  "model": "openrouter/deepseek/deepseek-v4-flash",
  "steps": 50
},
"plan": {
  "model": "openrouter/deepseek/deepseek-v4-pro"
},
"strategist": {
  "mode": "subagent",
  "model": "openrouter/deepseek/deepseek-v4-flash",
  "steps": 15
},
"build": {
  "model": "openrouter/deepseek/deepseek-v4-flash",
  "steps": 30
},
"designer": {
  "mode": "subagent",
  "model": "openrouter/google/gemini-3-flash-preview",
  "steps": 10
},
"ux-dev": {
  "mode": "subagent",
  "model": "openrouter/google/gemini-3-flash-preview",
  "steps": 30
}
```

### Pre-session agent frontmatter (line 4 of each file)

```yaml
# agents/architect.md
model: openrouter/deepseek/deepseek-v4-flash

# agents/orchestrate.md
model: openrouter/deepseek/deepseek-v4-flash

# agents/strategist.md
model: openrouter/deepseek/deepseek-v4-flash

# agents/designer.md
model: openrouter/google/gemini-3-flash-preview

# agents/ux-dev.md
model: openrouter/google/gemini-3-flash-preview
```

---

## Implementation order (for another AI)

Apply edits in this sequence. Run validation after step 4 and again after step 6.

1. **`opencode.json`** — replace Qwen provider entry; update agent models (pass 1 includes designer/ux-dev → M3).
2. **Agent frontmatter** — `architect`, `orchestrate`, `strategist`, `designer`, `ux-dev` (pass 1).
3. **`docs/RUNBOOK.md`** — overview bullet, agent matrix rows (pass 1).
4. **`docs/RUNBOOK.md`** — insert **Model routing (OpenRouter)** section after OpenRouter preset guidance.
5. **Validate:** `scripts/validate-opencode-config.sh && python3 -m json.tool opencode.json`
6. **User correction** — revert `designer` / `ux-dev` to Gemini in `opencode.json`, agent files, RUNBOOK matrix + routing table row split.
7. **Validate again.**

---

## Change 1 — Provider model registry (`opencode.json`)

**File:** `opencode.json`  
**Path:** `provider.openrouter.models`

**Replace** the `qwen/qwen3-next-80b-a3b-instruct` block **with:**

```json
"qwen/qwen3.7-max": {
  "name": "Qwen3.7 Max",
  "options": {
    "temperature": 0.1,
    "top_p": 0.9
  }
},
```

**Leave unchanged** (must remain registered for agents that use them):

```json
"minimax/minimax-m3": {
  "name": "MiniMax M3",
  "options": {
    "temperature": 0.3,
    "top_p": 0.95
  }
},
"google/gemini-3-flash-preview": {
  "name": "Gemini 3 Flash Preview",
  "options": {
    "temperature": 0.5
  }
}
```

(and all other existing provider entries: `openai/gpt-5-nano`, `qwen/qwen3-vl-235b-a22b-instruct`, `deepseek/deepseek-v4-flash`, `deepseek/deepseek-v4-pro`)

---

## Change 2 — Agent model routing (`opencode.json`)

**File:** `opencode.json`  
**Path:** `agent`

**Replace** the opening primary/built-in agents block:

```json
"architect": {
  "model": "openrouter/deepseek/deepseek-v4-flash",
  "steps": 30
},
"orchestrate": {
  "model": "openrouter/deepseek/deepseek-v4-flash",
  "steps": 50
},
"plan": {
  "model": "openrouter/deepseek/deepseek-v4-pro"
},
"strategist": {
  "mode": "subagent",
  "model": "openrouter/deepseek/deepseek-v4-flash",
  "steps": 15
},
"build": {
  "model": "openrouter/deepseek/deepseek-v4-flash",
  "steps": 30
},
```

**With:**

```json
"architect": {
  "model": "openrouter/qwen/qwen3.7-max",
  "steps": 30
},
"orchestrate": {
  "model": "openrouter/minimax/minimax-m3",
  "steps": 50
},
"plan": {
  "model": "openrouter/qwen/qwen3.7-max",
  "steps": 20
},
"strategist": {
  "mode": "subagent",
  "model": "openrouter/qwen/qwen3.7-max",
  "steps": 15
},
"build": {
  "model": "openrouter/minimax/minimax-m3",
  "steps": 30
},
```

**Note:** Only net-new step cap is `plan.steps: 20`. All other step values unchanged from baseline.

### Agents intentionally NOT changed in this chat

These should already match the final mapping; verify but do not blindly overwrite if a later session changed them:

```json
"developer": {
  "mode": "subagent",
  "model": "openrouter/minimax/minimax-m3",
  "steps": 45
},
"frontend-dev": {
  "mode": "subagent",
  "model": "openrouter/minimax/minimax-m3",
  "steps": 45
},
"senior-dev": {
  "mode": "subagent",
  "model": "openrouter/deepseek/deepseek-v4-pro",
  "steps": 40
},
"vision": {
  "mode": "subagent",
  "model": "openrouter/qwen/qwen3-vl-235b-a22b-instruct",
  "steps": 5
},
"helper": { "mode": "subagent", "model": "openrouter/deepseek/deepseek-v4-flash", "steps": 15 },
"debugger": { "mode": "subagent", "model": "openrouter/deepseek/deepseek-v4-flash", "steps": 15 },
"scribe": { "mode": "subagent", "model": "openrouter/openai/gpt-5-nano", "steps": 5 },
"worktree-env": { "mode": "subagent", "model": "openrouter/openai/gpt-5-nano", "steps": 10 },
"verifier": { "mode": "subagent", "model": "openrouter/deepseek/deepseek-v4-flash", "steps": 10 },
"review": { "mode": "subagent", "model": "openrouter/deepseek/deepseek-v4-flash", "steps": 15 },
"security-reviewer": { "mode": "subagent", "model": "openrouter/deepseek/deepseek-v4-flash", "steps": 15 },
"performance-reviewer": { "mode": "subagent", "model": "openrouter/deepseek/deepseek-v4-flash", "steps": 15 },
"doc-reviewer": { "mode": "subagent", "model": "openrouter/openai/gpt-5-nano", "steps": 10 },
"document": { "mode": "subagent", "model": "openrouter/openai/gpt-5-nano", "steps": 10 },
"mentor": { "mode": "subagent", "model": "openrouter/deepseek/deepseek-v4-flash", "steps": 10 },
"refactor": { "mode": "subagent", "model": "openrouter/deepseek/deepseek-v4-flash", "steps": 15 }
```

(`stack-bootstrap` existed in the longer baseline at chat start; include if present in your tree.)

---

## Change 3 — Agent frontmatter (pass 1, then user revert for designer/ux-dev)

**Rule:** Line 4 of each agent markdown file under `agents/` — YAML frontmatter field `model:`.

### Pass 1 (initial routing)

| File | Old value | New value |
| --- | --- | --- |
| `agents/architect.md` | `openrouter/deepseek/deepseek-v4-flash` | `openrouter/qwen/qwen3.7-max` |
| `agents/orchestrate.md` | `openrouter/deepseek/deepseek-v4-flash` | `openrouter/minimax/minimax-m3` |
| `agents/strategist.md` | `openrouter/deepseek/deepseek-v4-flash` | `openrouter/qwen/qwen3.7-max` |
| `agents/designer.md` | `openrouter/google/gemini-3-flash-preview` | `openrouter/minimax/minimax-m3` *(temporary)* |
| `agents/ux-dev.md` | `openrouter/google/gemini-3-flash-preview` | `openrouter/minimax/minimax-m3` *(temporary)* |

Example frontmatter head after pass 1 for architect:

```yaml
---
description: Planning coordinator. ...
mode: primary
model: openrouter/qwen/qwen3.7-max
tools:
  write: false
  ...
```

### Pass 2 — user correction (final for designer / ux-dev)

User message (paraphrased): keep `designer` and `ux-dev` on Gemini models at `opencode.json` lines 179–188.

**Revert** in both `opencode.json` and frontmatter:

```json
"designer": {
  "mode": "subagent",
  "model": "openrouter/google/gemini-3-flash-preview",
  "steps": 10
},
"ux-dev": {
  "mode": "subagent",
  "model": "openrouter/google/gemini-3-flash-preview",
  "steps": 30
},
```

```yaml
# agents/designer.md — line 4
model: openrouter/google/gemini-3-flash-preview

# agents/ux-dev.md — line 4
model: openrouter/google/gemini-3-flash-preview
```

**Do not modify** `agents/developer.md` or `agents/frontend-dev.md` in this chat (already M3 at session start).

---

## Change 4 — `docs/RUNBOOK.md` overview bullet

**Find:**

```markdown
- **Built-in agents:** `plan` uses DeepSeek V4 Pro; `build` uses DeepSeek V4 Flash in `opencode.json` for generic/quick tasks.
```

**Replace with:**

```markdown
- **Built-in agents:** `plan` uses Qwen3.7 Max; `build` uses MiniMax M3 in `opencode.json` for generic implementation tasks.
```

---

## Change 5 — `docs/RUNBOOK.md` agent matrix rows

### Planning specialists row

**Find:**

```markdown
| Planning specialists    | `debugger`, `refactor`, `review`, `designer` | smart      | Return type-specific plan drafts to architect. `designer` uses Gemini 3 Flash. `review` may also be invoked by orchestrate on **medium** Difficulty after execution.    |
```

**After pass 1 (temporary):** `designer` uses MiniMax M3.

**Final (after user correction):** restore Gemini wording — same as **Find** line above.

### Execution row

**Find (baseline):**

```markdown
| Execution               | `developer`, `frontend-dev`, `ux-dev`        | smart/fast | Execute assigned `stage_id` tasks. `ux-dev` uses `google/gemini-3-flash-preview` (see `opencode.json`) for HTML-only prototype generation into `.prototype/<slug>/`.                                            |
```

**Final (after user correction):**

```markdown
| Execution               | `developer`, `frontend-dev`, `ux-dev`        | smart/fast | Execute assigned `stage_id` tasks. `developer` and `frontend-dev` use MiniMax M3; `ux-dev` uses Gemini 3 Flash (see `opencode.json`) for HTML-only prototype generation into `.prototype/<slug>/`.                                            |
```

---

## Change 6 — `docs/RUNBOOK.md` new section (insert after OpenRouter preset)

**Anchor:** immediately after this line:

```markdown
2. Bind that preset to the **API key** OpenCode uses, per OpenRouter’s current key/preset UX.
```

**Insert this entire block** (final version after user correction — note separate rows for implementation vs design):

```markdown

## Model routing (OpenRouter)

Runtime authority: [`opencode.json`](../opencode.json) `agent` block. Temperature and sampling live under `provider.openrouter.models`.

| Layer | Agents | Model | OpenRouter ID |
| --- | --- | --- | --- |
| Planning / architecture | `architect`, `plan`, `strategist` | Qwen3.7 Max | `qwen/qwen3.7-max` |
| Orchestration | `orchestrate` | MiniMax M3 | `minimax/minimax-m3` |
| Primary implementation | `developer`, `frontend-dev`, `build` | MiniMax M3 | `minimax/minimax-m3` |
| Design / prototypes | `designer`, `ux-dev` | Gemini 3 Flash | `google/gemini-3-flash-preview` |
| Senior / second opinion | `senior-dev` | DeepSeek V4 Pro | `deepseek/deepseek-v4-pro` |
| Fast utility | `debugger`, `helper`, `refactor`, `verifier`, `review`, `security-reviewer`, `performance-reviewer`, `mentor` | DeepSeek V4 Flash | `deepseek/deepseek-v4-flash` |
| Vision / UI screenshots | `vision` | Qwen3 VL | `qwen/qwen3-vl-235b-a22b-instruct` |
| Writing / docs | `scribe`, `document`, `doc-reviewer`, `stack-bootstrap`, `worktree-env` | GPT-5 Nano | `openai/gpt-5-nano` |

**Step caps:** orchestrate `50`; developer/frontend-dev `45`; architect `30`; senior-dev `40`; scribe `5`. See `opencode.json` for the full list.

```

**Do not** leave the pass-1 routing table row that grouped `ux-dev` under Primary implementation with M3.

---

## Final target state — complete changed `agent` keys

After all edits (copy-paste reference for verification):

```json
"architect": {
  "model": "openrouter/qwen/qwen3.7-max",
  "steps": 30
},
"orchestrate": {
  "model": "openrouter/minimax/minimax-m3",
  "steps": 50
},
"plan": {
  "model": "openrouter/qwen/qwen3.7-max",
  "steps": 20
},
"strategist": {
  "mode": "subagent",
  "model": "openrouter/qwen/qwen3.7-max",
  "steps": 15
},
"build": {
  "model": "openrouter/minimax/minimax-m3",
  "steps": 30
},
"developer": {
  "mode": "subagent",
  "model": "openrouter/minimax/minimax-m3",
  "steps": 45
},
"frontend-dev": {
  "mode": "subagent",
  "model": "openrouter/minimax/minimax-m3",
  "steps": 45
},
"designer": {
  "mode": "subagent",
  "model": "openrouter/google/gemini-3-flash-preview",
  "steps": 10
},
"ux-dev": {
  "mode": "subagent",
  "model": "openrouter/google/gemini-3-flash-preview",
  "steps": 30
}
```

---

## Final agent-to-model table (all agents)

| Agent | Mode | Final model | Steps | Changed in chat? |
| --- | --- | --- | --- | --- |
| `architect` | primary | `openrouter/qwen/qwen3.7-max` | 30 | Yes |
| `orchestrate` | primary | `openrouter/minimax/minimax-m3` | 50 | Yes |
| `plan` | built-in | `openrouter/qwen/qwen3.7-max` | 20 | Yes (+ steps) |
| `strategist` | subagent | `openrouter/qwen/qwen3.7-max` | 15 | Yes |
| `build` | built-in | `openrouter/minimax/minimax-m3` | 30 | Yes |
| `developer` | subagent | `openrouter/minimax/minimax-m3` | 45 | No (already M3) |
| `frontend-dev` | subagent | `openrouter/minimax/minimax-m3` | 45 | No (already M3) |
| `senior-dev` | subagent | `openrouter/deepseek/deepseek-v4-pro` | 40 | No |
| `vision` | subagent | `openrouter/qwen/qwen3-vl-235b-a22b-instruct` | 5 | No |
| `designer` | subagent | `openrouter/google/gemini-3-flash-preview` | 10 | No (kept Gemini) |
| `ux-dev` | subagent | `openrouter/google/gemini-3-flash-preview` | 30 | No (kept Gemini) |
| `helper` | subagent | `openrouter/deepseek/deepseek-v4-flash` | 15 | No |
| `debugger` | subagent | `openrouter/deepseek/deepseek-v4-flash` | 15 | No |
| `scribe` | subagent | `openrouter/openai/gpt-5-nano` | 5 | No |
| `stack-bootstrap` | subagent | `openrouter/openai/gpt-5-nano` | 15 | No |
| `worktree-env` | subagent | `openrouter/openai/gpt-5-nano` | 10 | No |
| `verifier` | subagent | `openrouter/deepseek/deepseek-v4-flash` | 10 | No |
| `review` | subagent | `openrouter/deepseek/deepseek-v4-flash` | 15 | No |
| `security-reviewer` | subagent | `openrouter/deepseek/deepseek-v4-flash` | 15 | No |
| `performance-reviewer` | subagent | `openrouter/deepseek/deepseek-v4-flash` | 15 | No |
| `doc-reviewer` | subagent | `openrouter/openai/gpt-5-nano` | 10 | No |
| `document` | subagent | `openrouter/openai/gpt-5-nano` | 10 | No |
| `mentor` | subagent | `openrouter/deepseek/deepseek-v4-flash` | 10 | No |
| `refactor` | subagent | `openrouter/deepseek/deepseek-v4-flash` | 15 | No |

---

## Files modified (complete list)

| File | Summary |
| --- | --- |
| `opencode.json` | Add `qwen/qwen3.7-max`; remove `qwen3-next-80b`; route architect/plan/strategist → Qwen; orchestrate/build → M3; `plan.steps: 20`; designer/ux-dev stay Gemini |
| `agents/architect.md` | `model: openrouter/qwen/qwen3.7-max` |
| `agents/orchestrate.md` | `model: openrouter/minimax/minimax-m3` |
| `agents/strategist.md` | `model: openrouter/qwen/qwen3.7-max` |
| `agents/designer.md` | `model: openrouter/google/gemini-3-flash-preview` (unchanged from baseline) |
| `agents/ux-dev.md` | `model: openrouter/google/gemini-3-flash-preview` (unchanged from baseline) |
| `docs/RUNBOOK.md` | Built-in agents bullet; agent matrix; new **Model routing (OpenRouter)** section |

**Not modified:** `agents/developer.md`, `agents/frontend-dev.md`, utility/doc agents, skills, scripts.

---

## OpenRouter preset (operator action)

Add to API key allowlist preset:

- `qwen/qwen3.7-max` **(new)**
- `minimax/minimax-m3`
- `deepseek/deepseek-v4-flash`
- `deepseek/deepseek-v4-pro`
- `qwen/qwen3-vl-235b-a22b-instruct`
- `openai/gpt-5-nano`
- `google/gemini-3-flash-preview`

Remove if unused:

- `qwen/qwen3-next-80b-a3b-instruct`

See `docs/RUNBOOK.md` → “OpenRouter preset (limit Others model spend)”.

---

## Validation

```bash
cd ~/.config/opencode   # or $OPENCODE_CONFIG_DIR
scripts/validate-opencode-config.sh
python3 -m json.tool opencode.json > /dev/null && echo "JSON OK"
```

**Expected:** `validate-opencode-config: OK` after each edit round.

### Quick grep acceptance checks

```bash
grep -E 'qwen3\.7-max|minimax-m3' opencode.json
grep '^model:' agents/architect.md agents/orchestrate.md agents/strategist.md
grep 'Model routing (OpenRouter)' docs/RUNBOOK.md
grep 'gemini-3-flash-preview' opencode.json | head -2   # designer + ux-dev
```

---

## Session transcript (decision log)

| Order | Event |
| --- | --- |
| 1 | User provided role-to-model recommendation table |
| 2 | Applied full mapping including designer/ux-dev → M3 |
| 3 | Added RUNBOOK model routing section |
| 4 | Validation passed |
| 5 | User: keep designer/ux-dev on Gemini |
| 6 | Reverted designer/ux-dev in opencode.json, agents, RUNBOOK; split routing table row |
| 7 | Validation passed |
| 8 | User requested TO REVIEW documentation |

---

## Reconciliation with later workspace state

If `opencode.json` on disk shows **M2.7** instead of **M3**, apply **both**:

1. This document (Qwen architect, M3 orchestrate/build, etc.)
2. [`2026-06-01-minimax-m3-openrouter-upgrade.md`](2026-06-01-minimax-m3-openrouter-upgrade.md) if `developer`/`frontend-dev` still reference M2.7

If `docs/RUNBOOK.md` lacks **Model routing (OpenRouter)**, re-insert Change 6 above.

---

## Review checklist

- [ ] Filename date = Cursor chat creation date (`2026-06-01`)
- [ ] `qwen/qwen3.7-max` in provider; `qwen3-next-80b` removed
- [ ] `architect`, `plan`, `strategist` → Qwen3.7 Max
- [ ] `orchestrate`, `build`, `developer`, `frontend-dev` → MiniMax M3
- [ ] `designer`, `ux-dev` → Gemini 3 Flash
- [ ] Agent frontmatter matches for architect, orchestrate, strategist
- [ ] RUNBOOK section + matrix rows present
- [ ] OpenRouter preset updated
- [ ] `scripts/validate-opencode-config.sh` passes

---

## References

- [Qwen3.7 Max on OpenRouter](https://openrouter.ai/qwen/qwen3.7-max)
- [MiniMax provider on OpenRouter](https://openrouter.ai/provider/minimax)
- [DeepSeek V4 Flash on OpenRouter](https://openrouter.ai/deepseek/deepseek-v4-flash/apps)
- In-repo: `opencode.json`, `docs/RUNBOOK.md`
