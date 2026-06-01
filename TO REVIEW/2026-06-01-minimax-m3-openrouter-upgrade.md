# 2026-06-01 — MiniMax M2.7 → M3 OpenRouter Upgrade

**Session completed:** 2026-06-01 (when the M2.7 → M3 implementation finished in this chat — not the calendar day of a later TO REVIEW or rename request).

**Filename:** `2026-06-01-minimax-m3-openrouter-upgrade.md` — date prefix matches **session completed**, so it sorts with other work from that day in `TO REVIEW/`.

**Session scope:** Upgrade all OpenCode references from **MiniMax M2.7** to **MiniMax M3** on OpenRouter (`minimax/minimax-m3`).

**Status:** Finalized in this chat. Re-run the review checklist below if the workspace has diverged (e.g. still shows `minimax-m2.7` on disk).

---

## Objective

Replace the previous OpenRouter coding tier **MiniMax M2.7** with **MiniMax M3**, which OpenRouter lists as `minimax/minimax-m3` — a multimodal, agent-oriented model with up to 1M context, aimed at long-horizon coding and tool use.

User request (verbatim intent): upgrade MiniMax from OpenRouter **2.7** to **3** using `minimax/minimax-m3`.

---

## Why M3 (summary)

| Aspect | M2.7 (previous) | M3 (target) |
| --- | --- | --- |
| OpenRouter ID | `minimax/minimax-m2.7` | `minimax/minimax-m3` |
| Positioning | Multi-agent productivity / document workflows | Coding, agentic work, long context, native multimodal |
| Context (OpenRouter) | Smaller (prior generation) | Up to ~1M tokens (MSA architecture) |
| Nitro variant | `minimax/minimax-m2.7:nitro` was registered | No public `minimax/minimax-m3:nitro` at time of upgrade |

OpenRouter docs: [MiniMax M3](https://openrouter.ai/minimax/minimax-m3).

---

## What was implemented

### 1. Provider model registry (`opencode.json` → `provider.openrouter.models`)

**Before:**

```json
"minimax/minimax-m2.7": {
  "name": "MiniMax M2.7",
  "options": { "temperature": 0.3, "top_p": 0.95 }
},
"minimax/minimax-m2.7:nitro": {
  "name": "MiniMax M2.7 (nitro)",
  "options": { "temperature": 0.3, "top_p": 0.95 }
}
```

**After:**

```json
"minimax/minimax-m3": {
  "name": "MiniMax M3",
  "options": { "temperature": 0.3, "top_p": 0.95 }
}
```

**Decisions:**

- **Sampling unchanged** — kept `temperature: 0.3` and `top_p: 0.95` from M2.7 so behavior stays comparable across the swap.
- **Removed `:nitro` entry** — OpenRouter did not list an M3 nitro slug; keeping M2.7 nitro would leave a stale, unused model in the preset surface.

### 2. Agent assignments (`opencode.json` → `agent`)

Only agents that pointed at M2.7 were updated in this session:

| Agent | Mode | Model (after) | Steps | Notes |
| --- | --- | --- | --- | --- |
| `developer` | subagent | `openrouter/minimax/minimax-m3` | 45 | Primary implementation executor |
| `frontend-dev` | subagent | `openrouter/minimax/minimax-m3` | 45 | Frontend-focused implementation |

**Not in scope for this chat** (unchanged here): `orchestrate`, `build`, `architect`, and other agents — those may be covered by separate routing work (see `2026-06-01-model-routing-configuration.md` in this folder).

### 3. Agent frontmatter (must match `opencode.json`)

| File | Field changed |
| --- | --- |
| `agents/developer.md` | `model: openrouter/minimax/minimax-m3` |
| `agents/frontend-dev.md` | `model: openrouter/minimax/minimax-m3` |

OpenCode validation requires agent markdown frontmatter `model` to match the `opencode.json` agent block.

### 4. Documentation touch-up

| File | Change |
| --- | --- |
| `docs/upgrade-spec/upgrade-plan.md` | Pipeline table text: **MiniMax M2.7** → **MiniMax M3** (architect → orchestrate → subagents description) |

No RUNBOOK edits in this chat (preset guidance already mentions `:nitro` variants generically in `docs/RUNBOOK.md`).

---

## Files modified (complete list)

| File | Summary |
| --- | --- |
| `opencode.json` | Provider: M2.7 + nitro → M3 only; agents `developer`, `frontend-dev` → M3 |
| `agents/developer.md` | Frontmatter model → M3 |
| `agents/frontend-dev.md` | Frontmatter model → M3 |
| `docs/upgrade-spec/upgrade-plan.md` | Spec prose: M2.7 → M3 |

---

## Validation performed

At end of session:

```bash
scripts/validate-opencode-config.sh
```

**Result:** `validate-opencode-config: OK` (agent keys, skills, permissions, architect routing guards, unit tests).

---

## Operator follow-ups (not automated in chat)

1. **OpenRouter preset** — If the API key uses an allowlist preset, add `minimax/minimax-m3` and remove `minimax/minimax-m2.7` / `minimax/minimax-m2.7:nitro` if no longer needed. See `docs/RUNBOOK.md` → “OpenRouter preset (limit Others model spend)”.

2. **Reasoning tokens** — M3 on OpenRouter supports reasoning / `reasoning_details` in streaming. This upgrade did **not** add reasoning parameters to `opencode.json`; optional follow-up if you want extended thinking enabled for `developer` / `frontend-dev`.

3. **Broader routing** — Same-day doc `2026-06-01-model-routing-configuration.md` describes a wider stack change (Qwen3.7 architect, M3 orchestrate/build, etc.). This chat was a **narrow M2.7 → M3 swap** for the implementation tier; reconcile both docs before merge if both sessions apply.

---

## Review checklist

- [ ] `opencode.json` provider has `minimax/minimax-m3` (not `minimax-m2.7`)
- [ ] `minimax/minimax-m2.7:nitro` removed unless you intentionally keep legacy models
- [ ] `agent.developer.model` and `agent.frontend-dev.model` are `openrouter/minimax/minimax-m3`
- [ ] `agents/developer.md` and `agents/frontend-dev.md` frontmatter matches
- [ ] `docs/upgrade-spec/upgrade-plan.md` says MiniMax M3 where the pipeline is described
- [ ] OpenRouter preset allowlist updated
- [ ] `scripts/validate-opencode-config.sh` passes
- [ ] Smoke-test: delegate a small task to `developer` or `frontend-dev` and confirm OpenRouter bills `minimax/minimax-m3`

---

## Quick re-apply (if workspace reverted to M2.7)

```bash
# From repo root — verify after manual edit or merge
rg 'minimax-m2\.7' opencode.json agents/developer.md agents/frontend-dev.md
scripts/validate-opencode-config.sh
```

Expected: no matches for `minimax-m2.7` in those paths; validation OK.

---

## References

- [MiniMax M3 on OpenRouter](https://openrouter.ai/minimax/minimax-m3)
- [MiniMax models on OpenRouter](https://openrouter.ai/minimax)
- In-repo: `opencode.json`, `agents/developer.md`, `agents/frontend-dev.md`
