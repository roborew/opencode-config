# Cost-Split Agent Workflow Runbook

## Overview

- **Expensive agents** (plan, debugger, refactorer, review): produce `.plan/*.md` artifacts. Use `openrouter/openai/gpt-5.3-codex`.
- **Cheap agents** (build, implementor, fix, pr-reviewer): execute from artifacts. Use `openrouter/z-ai/glm-4.7`.

## A. Feature Plan → Build

1. Start OpenCode with the **plan** agent (expensive).
2. Describe the feature; let it analyze code and generate `.plan/plan.<slug>.md`.
3. When satisfied, stop planning.
4. Invoke the **build** subagent and say: "Use `.plan/plan.feature-<slug>.md` as the spec. Implement tasks 1–3."
5. Build reads only that plan file plus code and implements.

## B. Debugger → Fix

1. Start a **debugger** agent session (expensive).
2. Paste logs, failing tests, reproduction steps.
3. Let it write `.plan/debug.<slug>.md` with hypotheses and fix steps.
4. Call the **fix** subagent: "Apply the fix per `.plan/debug.<slug>.md` and update tests."

## C. Refactorer → Implementor

1. Start a **refactorer** agent session (expensive).
2. Describe the refactor scope.
3. Let it write `.plan/refactor.<slug>.md` with invariants and slices.
4. Call the **implementor** subagent: "Execute `.plan/refactor.<slug>.md`."

## D. Review → PR Reviewer

1. Start a **review** agent session (expensive).
2. Provide PR diff or branch to analyze.
3. Let it write `.plan/review.<slug>.md` with required changes.
4. Call the **pr-reviewer** subagent: "Apply changes from `.plan/review.<slug>.md`."

## Artifact Types

| Activity      | Primary agent | Output file              | Subagent     |
|---------------|---------------|--------------------------|--------------|
| Feature plan  | plan          | `.plan/plan.<slug>.md`   | build        |
| Bug analysis  | debugger      | `.plan/debug.<slug>.md`  | fix          |
| Refactor      | refactorer     | `.plan/refactor.<slug>.md` | implementor |
| PR review     | review        | `.plan/review.<slug>.md` | pr-reviewer  |
