# OpenCode capability matrix

| Capability | Owner agent | Skill(s) | Skill load default | Artifact / output | Gate |
|------------|-------------|----------|-------------------|-------------------|------|
| Feature / plan | `architect` | `architect-plan`, `architect-review` | Parent: sub-skills by mode; **Task** children: `load: full`, `minimal`, or `auto` per [`agents/architect.md`](../../agents/architect.md) | `.plan/<type>.<slug>.md` via `scribe` | User → `orchestrate` |
| Stage execution | `orchestrate` | `orchestrate-execution`, `orchestrate-recovery`, `feature-worktree` | Parent: sub-skills by situation; test-writer RED → owner GREEN → code-review ticket gate | Graded stages, completion prompt | `code-review` |
| Worktree env copies (opt-in) | `worktree-env` | `worktree-env` | Parent: `load: full` once per bootstrap; trust canonical evidence | Copy report with `wt_root`, `main_root`, per-file `is_regular_file` | `preflight` (verify only) |
| Env bootstrap / repair (opt-in) | `preflight` | `preflight` | Parent: `load: full` on preflight Task | `Ready` or one `recommended_env_fix`; repair pass for deps/runtime/indexing | `orchestrate` sets `env_gate_passed` |
| Backend / generic code | `developer` | `developer` | `auto` (tiered triggers in agent; parent overrides) | Completion report | `verifier` |
| Frontend | `frontend-dev` | `frontend-dev` | `auto` | Completion report | `verifier` |
| HTML prototype | `ux-dev` | `ux-dev` | `auto` | `.prototype/<slug>/` | `verifier` |
| Review (planning) | `review` | `review` + optional `security-reviewer`, `performance-reviewer`, `doc-reviewer` | `auto` (effective `load: full` for `review`; specialists default `load: full`) | Review markdown to parent | Architect + `scribe` |
| CodeRabbit gate (completion) | `orchestrate` → `review` | `code-review` (+ `review` on `load: full`) | Parent: `load: full` on CodeRabbit Task; **exactly once** per artifact/feature | `CODERABBIT_GATE` + full finding inventory + per-item local resolutions; feature completion summary | After last verifier / queue exhausted; `coderabbit review --agent --base develop` by default; before final push/PR, difficulty gates, and architect — **not** per issue and **not** after remediation |
| Evidence check | `verifier` | `verifier` | `auto` | Verdict + evidence | Orchestrate |
| Docker compose build/test + optional review URL (Sysbox sibling) | `developer`, `frontend-dev`, `verifier` (probe: `preflight`); **`orchestrate` instructs Tasks only — does not load the skill**; menu **(2)** = sandbox feature build/refresh (no issue queue) | `docker-sandbox` | Load when Compose/Docker or web review needed (`sandbox: preferred\|required` / `execution_mode: sandbox_feature_build` from parent, compose in `test_commands`, or preflight `sandbox: ready` + compose file). Soft-skip when unavailable unless required. Not Cloudflare Workers Sandbox. | `sandbox exec` logs; optional `https://{slug}.{apex}` | `OPENCODE_SANDBOX_ENABLED` (expose: localhost publish + host tunnel public hostname + `OPENCODE_SANDBOX_REVIEW_DNS`); rebuild OpenCode image after `CONFIG_REF` change |
| Docs generation | `document` | `document` | `auto` | Content to `scribe` | Architect |
| Ship / hotfix / TDD | (user-chosen agent with skill allowed) | `ship`, `hotfix`, `debug-fix`, `tdd` | User-chosen | Git / PR | User confirms each step |

Other read-only specialists (`debugger`, `refactor`, `designer`, `strategist`, `helper`, `senior-dev`, `mentor`, `vision`, `scribe`) define **Execution readiness** and **Auto-load triggers** in their agent files; parents still pass `load: full|minimal|auto` on every Task. **`worktree-env`** and **`preflight`** are narrow startup subagents (bash + allow-listed skills only; no app-code edits).

## Preserved strengths

- Per-agent model routing in `opencode.json`.
- MCP: `mcpjungle` and `claude-context` (command path unchanged). MCPJungle manages Context7, Cloudflare API, Cloudflare Docs, and `docs-mcp-server` upstream authentication. Narrow Cloudflare skills: `cloudflare`, `wrangler`, `workers-best-practices` (from [cloudflare/skills](https://github.com/cloudflare/skills)).
- `strategist`, `preflight`, architect plan/review split.
