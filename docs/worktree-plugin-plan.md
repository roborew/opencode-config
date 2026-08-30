# Worktree Plugin Plan (corrected base: `feature/worktrees`)

## Problem

`kdco/worktree` is a third-party OpenCode plugin that is no longer maintained and breaks against the current opencode-server. We need a first-party plugin that drives the upstream `/experimental/worktree` API so worktrees and sessions register in the Desktop GUI, and a subagent that the orchestrator can delegate lifecycle calls to without bypassing GUI registration.

## Why this plan exists

A prior attempt was made against `main` and missed the in-flight changes already on `feature/worktrees`. This plan is re-scoped to that branch: it **amends** existing files rather than duplicating them, and it inherits the branch's agent model choice (`opencode/muse-spark-1.2-contributor-free` for env-touching agents, `opencode/gpt-5-nano` for the new lifecycle agent).

## Branch and base

- Base branch: `origin/feature/worktrees` @ `934acf1 chore: validate CI stabilization and sandbox lifecycle`.
- New branch: `feature/worktree-plugin` (local, not pushed).
- All edits sit on top of `feature/worktrees`. Nothing from `main` is rebased in.

## Inherited from `feature/worktrees` (do not duplicate)

- `agents/orchestrate.md` already allows `code-review` and `test-writer` (no `verifier`), and `worktree-env` is already in the `task:` allow-list. We add `worktree-manager: allow` to that same allow-list.
- `agents/worktree-env.md` and `skills/worktree-env/SKILL.md` already exist (env file copy helper, unrelated to lifecycle).
- `skills/orchestrate/SKILL.md` exists and currently documents raw `worktree_create(branch, baseBranch)` calls with a `git worktree add` fallback. We **rewrite** it to delegate to `worktree-manager`.
- `docs/smoke/feature-worktree-fanout-validation.md` exists with 10 scenarios. We **amend** it with 10 more (API-driven fan-out).
- `scripts/validate-opencode-config.sh` already requires `orchestrate/SKILL.md`, `code-review`/`test-writer` agents and skills, and orchestrate routing. We extend it with asserts for the plugin and the new agent.

## New files

### `plugins/worktree.js`

In-process OpenCode plugin. Exports `WorktreePlugin = async (_ctx) => ({ tool: { worktree_create, worktree_list, worktree_delete, worktree_reset } })`.

- Uses `_ctx.client.worktree.{create,list,remove,reset}` — the in-process SDK carries HTTP Basic Auth automatically. No raw `fetch`.
- Targets `/experimental/worktree` and `/experimental/worktree/reset` (verified from the OpenCode SDK gen types in `node_modules/@opencode-ai/sdk/dist/v2/gen/types.gen.d.ts`).
- `worktree_delete` self-guards against paths under `OPENCODE_APPS_DIR` (mirrors `worktree-delete-guard.py:_is_protected_project_root`). On refusal, returns `{ ok: false, refused: "PROTECTED_PROJECT_ROOT", manualRecovery }`.
- `worktree_create` accepts `{ name }` only. Validates that `name` contains no `/`. Branches are auto-prefixed `opencode/<name>` by the server.
- Every failure path emits a GUI-reachable `manualRecovery` curl snippet (host `*********:4097`, basic auth from env).

### `agents/worktree-manager.md`

`mode: subagent`, `model: opencode/gpt-5-nano`, `steps: 15`. Frontmatter enables only `worktree_create`, `worktree_list`, `worktree_delete`, `worktree_reset`, `bash`, `skill`, and explicitly disables `write`, `edit`. Permission block denies `edit`, allowlists `bash` minus destructive patterns, and self-allows `task: { "*": "deny", "worktree-manager": "allow" }`.

Procedures for five actions: `create_feature`, `create_ticket` (with post-create `git reset` inside the worktree to honor a non-default `base`, since the upstream API only supports the project default base), `delete` (with pre-checks for pushed + clean), `list`, `reset`. Every parent-facing failure is JSON-shaped with `blocker_code` + `manualRecovery`.

### `docs/worktree-plugin-plan.md`

This document.

## Edits to inherited files

### `opencode.json`

Insert `"worktree-manager"` agent block immediately after `"worktree-env"`:

```json
"worktree-manager": {
  "mode": "subagent",
  "model": "opencode/gpt-5-nano",
  "steps": 15
}
```

No other JSON changes. The plugin is loaded by the entrypoint script (copying `plugins/` into `${OPENCODE_CONFIG_DIR}/plugins/`) — no `plugin` array edit needed.

### `agents/orchestrate.md`

Add `worktree-manager: allow` to the `task:` allow-list, immediately after `worktree-env: allow`. Preserve the existing 4-space indentation. No other frontmatter changes.

### `skills/orchestrate/SKILL.md`

Rewrite so the skill is routing-only: it tells the orchestrator to dispatch `worktree-manager` Tasks with one of five actions. Removes the `git worktree add -b feature/<slug>` fallback block. Documents `feat-<slug>` / `ticket-<issue>-<slug>` naming and the resulting `opencode/<name>` branch shape.

### `docs/smoke/feature-worktree-fanout-validation.md`

Append a new section with 10 scenarios that exercise the API-driven path: agent+orchestrate wiring, plugin boot log, feature create, ticket create with `merge-base` check, API-failure stop, restart-reset, Desktop-UI branch label, `OPENCODE_APPS_DIR` self-guard, hard-rule denials, one-shot contract.

### `scripts/validate-opencode-config.sh`

Append a new `echo "Checking worktree-manager + worktree plugin wiring..."` block that asserts:
- `plugins/worktree.js` exists and passes `node --check`.
- `plugins/worktree.js` contains `/experimental/worktree`, `OPENCODE_APPS_DIR`, and all four tool names.
- `agents/worktree-manager.md` exists.
- `opencode.json` contains `"worktree-manager"`.
- `agents/orchestrate.md` contains `worktree-manager: allow`.
- `skills/orchestrate/SKILL.md` does **not** contain `git worktree add`.

## Validation (run locally before commit)

```
node --check plugins/worktree.js
python3 -m json.tool opencode.json
bash -n scripts/validate-opencode-config.sh
python3 -c "import yaml; yaml.safe_load(open('agents/worktree-manager.md').read().split('---',2)[1])"
bash scripts/validate-opencode-config.sh
```

The full validator also runs `migrate_repos_registry` and `existing_issue` unit tests; both must remain green.

## Out of scope

- No change to `main` or to `feature/worktrees`.
- No change to the Desktop GUI itself.
- No change to `worktree-delete-guard.py` (the host-side proxy); the plugin's self-guard is the in-process defense.
- No new dependencies — the plugin uses only Node 22 standard library + the in-process SDK client.