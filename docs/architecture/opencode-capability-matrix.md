# OpenCode capability matrix

| Capability | Owner agent | Skill(s) | Artifact / output | Gate |
|------------|-------------|----------|-------------------|------|
| Feature / plan | `architect` | `architect-plan`, `architect-review` | `.plan/<type>.<slug>.md` via `scribe` | User → `orchestrate` |
| Stage execution | `orchestrate` | `orchestrate-execution`, `orchestrate-recovery` | Graded stages, completion prompt | `verifier` |
| Backend / generic code | `developer` | `developer`, `preflight` | Completion report | `verifier` |
| Frontend | `frontend-dev` | `frontend-dev` | Completion report | `verifier` |
| HTML prototype | `ux-dev` | `ux-dev` | `.prototype/<slug>/` | `verifier` |
| Review (planning) | `review` | `review` + optional `security-reviewer`, `performance-reviewer`, `doc-reviewer` | Review markdown to parent | Architect + `scribe` |
| Evidence check | `verifier` | `verifier` | Verdict + evidence | Orchestrate |
| Docs generation | `document` | `document` | Content to `scribe` | Architect |
| Ship / hotfix / TDD | (user-chosen agent with skill allowed) | `ship`, `hotfix`, `debug-fix`, `tdd` | Git / PR | User confirms each step |

## Preserved strengths

- Per-agent model routing in `opencode.json`.
- MCP: `context7`, `docs-mcp-server`, `dash-api`, `claude-context` (command path unchanged).
- `strategist`, `preflight`, architect plan/review split.
