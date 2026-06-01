# OpenCode Model Routing Configuration

**Work completed:** 2026-06-01 (date this chat finished model routing and the `designer` / `ux-dev` Gemini correction)

**Session scope:** Map role-to-model recommendations onto `opencode.json` and sync related agent frontmatter and RUNBOOK documentation.

**Status:** Finalized in chat (including user correction for `designer` / `ux-dev`). Verify on disk before merge — workspace may have diverged since this session.

---

## Objective

Configure OpenCode’s agent stack using an OpenRouter-based model routing plan:

- **Qwen3.7 Max** as the architect / high-level planner
- **MiniMax M3** as the orchestrator and primary implementation tier
- **DeepSeek V4 Pro** for senior / second-opinion work
- **DeepSeek V4 Flash** for fast utility workers
- **Qwen3 VL** for vision / screenshot review
- **GPT-5 Nano** for writing, docs, and low-cost throughput roles
- **Gemini 3 Flash** retained for design and prototype roles (user decision)

---

## Recommendation source (incoming table)

| Layer / role | Recommended model | OpenRouter ID | Rationale (summary) |
| --- | --- | --- | --- |
| Architect | Qwen3.7 Max | `qwen/qwen3.7-max` | Agent-centric planning, long context, structured plans from skills/rules |
| Orchestrator | MiniMax M3 | `minimax/minimax-m3` | Agentic coordination, tool use, alignment with MiniMax worker tier |
| Senior / complex worker | MiniMax M3 or DeepSeek V4 Pro | `minimax/minimax-m3` / `deepseek/deepseek-v4-pro` | M3 for orchestrator alignment; V4 Pro for alternate “second opinion” voice |
| Primary implementation | MiniMax M3 | `minimax/minimax-m3` | End-to-end coding across large codebases |
| Fast utility workers | DeepSeek V4 Flash | `deepseek/deepseek-v4-flash` | Cheap, fast diagnostics, refactors, reviewers |
| Vision / multimodal | Qwen3 VL or MiniMax M3 | `qwen/qwen3-vl-235b-a22b-instruct` / `minimax/minimax-m3` | Qwen3 VL for genuine image/UI review |
| Writing / docs | GPT-5 Nano (or similar cheap text model) | `openai/gpt-5-nano` | Latency/throughput sensitive; low reasoning need |

---

## Final agent-to-model mapping (as agreed in chat)

### Provider models (`opencode.json` → `provider.openrouter.models`)

| OpenRouter ID | Display name | Sampling notes |
| --- | --- | --- |
| `qwen/qwen3.7-max` | Qwen3.7 Max | **Added.** `temperature: 0.1`, `top_p: 0.9` |
| `minimax/minimax-m3` | MiniMax M3 | Existing. `temperature: 0.3`, `top_p: 0.95` |
| `deepseek/deepseek-v4-flash` | DeepSeek V4 Flash | Existing. Includes `frequency_penalty: 0.3` |
| `deepseek/deepseek-v4-pro` | DeepSeek V4 Pro | Existing. `temperature: 0.2`, `top_p: 0.9` |
| `qwen/qwen3-vl-235b-a22b-instruct` | Qwen3 VL 235B (vision) | Existing |
| `openai/gpt-5-nano` | GPT-5 Nano | Existing |
| `google/gemini-3-flash-preview` | Gemini 3 Flash Preview | Existing — **kept for design roles** |

**Provider cleanup:** `qwen/qwen3-next-80b-a3b-instruct` was replaced by `qwen/qwen3.7-max` in the provider block (Next 80B was unused by any agent).

### Agent assignments (`opencode.json` → `agent`)

| Agent | Mode | Final model | Steps | Change from pre-session baseline |
| --- | --- | --- | --- | --- |
| `architect` | primary | `openrouter/qwen/qwen3.7-max` | 30 | Was DeepSeek V4 Flash |
| `orchestrate` | primary | `openrouter/minimax/minimax-m3` | 50 | Was DeepSeek V4 Flash |
| `plan` | built-in | `openrouter/qwen/qwen3.7-max` | 20 | Was DeepSeek V4 Pro; **steps added** |
| `strategist` | subagent | `openrouter/qwen/qwen3.7-max` | 15 | Was DeepSeek V4 Flash |
| `build` | built-in | `openrouter/minimax/minimax-m3` | 30 | Was DeepSeek V4 Flash |
| `developer` | subagent | `openrouter/minimax/minimax-m3` | 45 | Already MiniMax M3 |
| `frontend-dev` | subagent | `openrouter/minimax/minimax-m3` | 45 | Already MiniMax M3 |
| `senior-dev` | subagent | `openrouter/deepseek/deepseek-v4-pro` | 40 | Unchanged (second-opinion tier) |
| `vision` | subagent | `openrouter/qwen/qwen3-vl-235b-a22b-instruct` | 5 | Unchanged |
| `designer` | subagent | `openrouter/google/gemini-3-flash-preview` | 10 | **User: keep Gemini** (briefly switched to M3, then reverted) |
| `ux-dev` | subagent | `openrouter/google/gemini-3-flash-preview` | 30 | **User: keep Gemini** (briefly switched to M3, then reverted) |
| `helper` | subagent | `openrouter/deepseek/deepseek-v4-flash` | 15 | Unchanged |
| `debugger` | subagent | `openrouter/deepseek/deepseek-v4-flash` | 15 | Unchanged |
| `scribe` | subagent | `openrouter/openai/gpt-5-nano` | 5 | Unchanged |
| `stack-bootstrap` | subagent | `openrouter/openai/gpt-5-nano` | 15 | Unchanged |
| `worktree-env` | subagent | `openrouter/openai/gpt-5-nano` | 10 | Unchanged |
| `verifier` | subagent | `openrouter/deepseek/deepseek-v4-flash` | 10 | Unchanged |
| `review` | subagent | `openrouter/deepseek/deepseek-v4-flash` | 15 | Unchanged |
| `security-reviewer` | subagent | `openrouter/deepseek/deepseek-v4-flash` | 15 | Unchanged |
| `performance-reviewer` | subagent | `openrouter/deepseek/deepseek-v4-flash` | 15 | Unchanged |
| `doc-reviewer` | subagent | `openrouter/openai/gpt-5-nano` | 10 | Unchanged |
| `document` | subagent | `openrouter/openai/gpt-5-nano` | 10 | Unchanged |
| `mentor` | subagent | `openrouter/deepseek/deepseek-v4-flash` | 10 | Unchanged |
| `refactor` | subagent | `openrouter/deepseek/deepseek-v4-flash` | 15 | Unchanged |

### Layer summary (final)

| Layer | Agents | Model |
| --- | --- | --- |
| Planning / architecture | `architect`, `plan`, `strategist` | Qwen3.7 Max |
| Orchestration | `orchestrate` | MiniMax M3 |
| Primary implementation | `developer`, `frontend-dev`, `build` | MiniMax M3 |
| Design briefs & HTML prototypes | `designer`, `ux-dev` | Gemini 3 Flash |
| Senior / second opinion | `senior-dev` | DeepSeek V4 Pro |
| Fast utility | `debugger`, `helper`, `refactor`, `verifier`, `review`, `security-reviewer`, `performance-reviewer`, `mentor` | DeepSeek V4 Flash |
| Vision | `vision` | Qwen3 VL |
| Writing / docs | `scribe`, `document`, `doc-reviewer`, `stack-bootstrap`, `worktree-env` | GPT-5 Nano |

---

## User refinement (second message in session)

After the initial mapping, `designer` and `ux-dev` were briefly moved to **MiniMax M3** to align with the orchestrator. The user requested they **continue using Gemini 3 Flash Preview** because:

- `designer` produces structured design briefs (planning-adjacent, UI/UX oriented)
- `ux-dev` generates HTML-only prototypes into `.prototype/<slug>/`

Both were reverted to `openrouter/google/gemini-3-flash-preview` in `opencode.json`, agent frontmatter, and RUNBOOK.

---

## Files modified in session

| File | Changes |
| --- | --- |
| `opencode.json` | Provider model `qwen/qwen3.7-max`; agent model routing; `plan.steps: 20` |
| `agents/architect.md` | Frontmatter `model` → Qwen3.7 Max |
| `agents/orchestrate.md` | Frontmatter `model` → MiniMax M3 |
| `agents/strategist.md` | Frontmatter `model` → Qwen3.7 Max |
| `agents/designer.md` | Frontmatter `model` → Gemini 3 Flash (final) |
| `agents/ux-dev.md` | Frontmatter `model` → Gemini 3 Flash (final) |
| `docs/RUNBOOK.md` | Built-in agent model notes; agent matrix rows for `designer` / execution tier; new **Model routing (OpenRouter)** section with full table and step-cap summary |

**Not modified:** Agent files that already matched the target mapping (`developer`, `frontend-dev`, `senior-dev`, `vision`, utility agents, doc agents, etc.).

---

## RUNBOOK additions

A **Model routing (OpenRouter)** section was added after the OpenRouter preset guidance, including:

- Layer → agents → model → OpenRouter ID table
- Step cap reference (`orchestrate` 50, `developer`/`frontend-dev` 45, `architect` 30, `senior-dev` 40, `scribe` 5)
- Pointer that `opencode.json` is runtime authority for models and sampling

Overview bullets were updated for built-in agents (`plan` → Qwen3.7 Max, `build` → MiniMax M3) and execution matrix (`developer`/`frontend-dev` on M3; `ux-dev` on Gemini).

---

## OpenRouter preset (operator action)

Update the API key preset allowed-model list to include models actually used after this routing:

**Required after this change:**

- `qwen/qwen3.7-max`
- `minimax/minimax-m3`
- `deepseek/deepseek-v4-flash`
- `deepseek/deepseek-v4-pro`
- `qwen/qwen3-vl-235b-a22b-instruct`
- `openai/gpt-5-nano`
- `google/gemini-3-flash-preview`

**Can remove from preset (if present, no longer referenced):**

- `qwen/qwen3-next-80b-a3b-instruct`

See `docs/RUNBOOK.md` → “OpenRouter preset (limit Others model spend)”.

---

## Validation performed

During the session:

```bash
scripts/validate-opencode-config.sh
python3 -m json.tool opencode.json
```

Both passed after each edit round.

---

## Pre-session baseline (for diff context)

Before this session, primaries and several planning agents used **DeepSeek V4 Flash**; `plan` used **DeepSeek V4 Pro**; implementation workers already used **MiniMax M3** for `developer` and `frontend-dev`; `designer` and `ux-dev` already used **Gemini 3 Flash**.

The main shifts were elevating **architect / plan / strategist** to Qwen3.7 Max and **orchestrate / build** to MiniMax M3, plus documentation and provider registration for the new Qwen model.

---

## Review checklist

- [ ] Confirm `opencode.json` on disk matches the **Final agent-to-model mapping** table above
- [ ] Confirm agent frontmatter `model:` fields match `opencode.json` for changed agents
- [ ] Confirm RUNBOOK model routing section is present and accurate
- [ ] Update OpenRouter preset allowlist on the key OpenCode uses
- [ ] Smoke-test: `architect` session (planning), `orchestrate` session (delegation), `ux-dev` prototype stage (Gemini)
- [ ] Re-run `scripts/validate-opencode-config.sh` after applying or merging

---

## References

- [Qwen3.7 Max on OpenRouter](https://openrouter.ai/qwen/qwen3.7-max)
- [MiniMax provider on OpenRouter](https://openrouter.ai/provider/minimax)
- [DeepSeek V4 Flash on OpenRouter](https://openrouter.ai/deepseek/deepseek-v4-flash/apps)
- In-repo authority: `opencode.json`, `docs/RUNBOOK.md`
