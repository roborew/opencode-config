# OpenCode capability matrix

| Capability | Owner agent | Skill(s) | Skill load default | Artifact / output | Gate |
|------------|-------------|----------|-------------------|-------------------|------|
| Feature / plan | `architect` | `architect-plan`, `architect-review` | Parent: sub-skills by mode; **Task** children: `load: full`, `minimal`, or `auto` per [`agents/architect.md`](../../agents/architect.md) | `.plan/<type>.<slug>.md` via `scribe` | User → `orchestrate` |
| Stage execution | `orchestrate` | `orchestrate-execution`, `orchestrate-recovery` | Parent: sub-skills by situation; **Task** children: `load: full`, `minimal`, or `auto` per [`agents/orchestrate.md`](../../agents/orchestrate.md) | Graded stages, completion prompt | `verifier` |
| Worktree env symlinks (opt-in) | `worktree-env` | `worktree-env` | Parent: `load: full` once per bootstrap; trust canonical evidence | Symlink report with `wt_root`, `main_root`, per-file `readlink` | `developer` + `preflight` (verify only) |
| Env bootstrap / repair (opt-in) | `developer` | `preflight` | Parent: `load: full` on preflight-only Task | `Ready` or one `recommended_env_fix`; repair pass for deps/runtime/indexing | `orchestrate` sets `env_gate_passed` |
| Backend / generic code | `developer` | `developer`, `preflight` | `auto` (tiered triggers in agent; parent overrides) | Completion report | `verifier` |
| Frontend | `frontend-dev` | `frontend-dev` | `auto` | Completion report | `verifier` |
| HTML prototype | `ux-dev` | `ux-dev` | `auto` | `.prototype/<slug>/` | `verifier` |
| Review (planning) | `review` | `review` + optional `security-reviewer`, `performance-reviewer`, `doc-reviewer` | `auto` (effective `load: full` for `review`; specialists default `load: full`) | Review markdown to parent | Architect + `scribe` |
| CodeRabbit gate (completion) | `orchestrate` → `review` | `code-review` (+ `review` on `load: full`) | Parent: `load: full` on CodeRabbit Task; **exactly once** per artifact/feature | `CODERABBIT_GATE` + full finding inventory + per-item local resolutions; feature completion summary | After last verifier / queue exhausted; `coderabbit review --agent --base develop` by default; before final push/PR, difficulty gates, and architect — **not** per issue and **not** after remediation |
| Evidence check | `verifier` | `verifier` | `auto` | Verdict + evidence | Orchestrate |
| Docs generation | `document` | `document` | `auto` | Content to `scribe` | Architect |
| Ship / hotfix / TDD | (user-chosen agent with skill allowed) | `ship`, `hotfix`, `debug-fix`, `tdd` | User-chosen | Git / PR | User confirms each step |

Other read-only specialists (`debugger`, `refactor`, `designer`, `strategist`, `helper`, `senior-dev`, `mentor`, `vision`, `scribe`) define **Execution readiness** and **Auto-load triggers** in their agent files; parents still pass `load: full|minimal|auto` on every Task. **`worktree-env`** is a narrow startup subagent (bash/git + `worktree-env` skill only).

## Preserved strengths

- Per-agent model routing in `opencode.json`.
- MCP: `context7`, `docs-mcp-server`, `dash-api`, `claude-context` (command path unchanged).
- `strategist`, `preflight`, architect plan/review split.
